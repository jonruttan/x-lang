; lint.x -- AST linter via the type-system write stacks (def/use analysis)
;
; Drives the interpreter's own traversal: analysis handlers are pushed onto the
; LIST and SYMBOL write stacks and the tree is walked with write-to-str -- type
; dispatch visits every node and nothing is executed.
;
; All symbol comparison is by NAME (string), captured fresh during the walk.
; Symbols read in one reader session can't be eq?-compared with symbols from
; another (different interns; GC relocates/frees heap objects across reader
; calls -- eq? would dereference a stale pointer and crash).  So every symbol is
; converted to its name string at the moment it is encountered, and only those
; strings are compared/stored.  lint-forms returns (defs uses issues) as NAME
; STRINGS; lint-has? tests membership.
(import x/core/list)
(import x/core/alist)
(import x/type/str)
(import x/sys/type)

; Type structs we attach handlers to (LIST = forms, SYMBOL = references).
(def %lint-list-type   (type-by-atom (type-of (list 1))))
(def %lint-symbol-type (type-by-atom (type-of (lit a))))

; A name is "known" if it resolves to an existing binding -- a C primitive or
; a library def.  We test by evaluating the interned symbol under a guard:
; bound -> its value (known), unbound -> the lookup errors -> #f.  (Evaluating
; a bare symbol is a pure lookup, no side effects.)  This replaces a former
; base-layout-dependent env-alist dig that broke when the base layout drifted
; and produced false "undefined" reports for every primitive.
(def %env-known? (fn (_ name)
  (guard (_ #f) (do (eval! (str->symbol name)) #t))))

; --- Analysis state (boxes; all values are NAME STRINGS) ---
(def %lint-scope  (list ()))    ; names in lexical scope
(def %lint-uses   (list ()))    ; names referenced (unique)
(def %lint-issues (list ()))    ; op names where first/rest hit a literal non-list
(def %lint-leaks  (list ()))    ; def names that bind in tail position (leak to global)

; Swappable hooks -- tools/lint.x overrides these for data-driven, construct-
; table dispatch.  Forward-declared; defaults set below once the helpers exist.
(def %lint-binds? ())      ; form -> truthy if it binds a name in a sequence
(def %lint-bound-name ())  ; form -> the bound name (a STRING)
(def %lint-dispatch ())    ; form -> () : scope-aware analysis of one list form

; str=? membership over a list of name strings.
(def %name-member? (fn (self name names)
  (if (null? names) ()
    (if (str=? name (first names)) #t (self name (rest names))))))

; --- Scope helpers (scope holds name strings) ---

; The NAME of one parameter slot.  A slot is normally a bare symbol, but the
; doc DSL lets a fn inline its param docs: (fn (self (param p TYPE "d") ...) ..)
; -- there the real name is the 2nd element of the (param ...) form.  Without
; this, the whole (param ...) form gets stringified and the actual parameter
; is never added to scope (so its uses look "undefined").
(def %param-name (fn (_ p)
  (if (pair? p)
    (if (if (symbol? (first p)) (str=? (convert (first p) %string) "param") #f)
      (convert (first (rest p)) %string)   ; (param NAME TYPE "desc") -> NAME
      (convert (first p) %string))          ; other pair -> its head
    (convert p %string))))                  ; bare symbol

(def %add-params (fn (self params scope)
  (if (null? params) scope
    (if (symbol? params) (pair (convert params %string) scope)
      (if (pair? params)
        (self (rest params) (pair (%param-name (first params)) scope))
        scope)))))

(def %scope-add! (fn (_ name) (set-first! %lint-scope (pair name (first %lint-scope)))))

; --- Traversal core ---

; Walk one form: write dispatches a list to the list handler, a symbol to the
; symbol handler, anything else to its own (harmless) writer.  nil is skipped.
(def %lint-form (fn (_ form) (if (null? form) () (do (write form) ()))))

; Walk a body/clause sequence; a leading binding form adds its name for the rest.
(def %lint-seq (fn (self forms)
  (if (null? forms) ()
    (if (pair? forms)
      (do (%lint-form (first forms))
          (if (%lint-binds? (first forms))
            (%scope-add! (%lint-bound-name (first forms)))
            ())
          (self (rest forms)))
      (%lint-form forms)))))

; --- first/rest argument check ---

; True when arg is a quoted non-list literal: (lit X) with X neither pair nor
; nil -- exactly (first 'sym) / (rest 'sym), the static form of the crash.
; Compared by name (the head symbol is fresh -- it is part of the walked form).
(def %lint-literal-non-list? (fn (_ arg)
  (if (pair? arg)
    (if (if (symbol? (first arg)) (str=? (convert (first arg) %string) "lit") #f)
      (let ((x (first (rest arg))))
        (if (null? x) #f (if (pair? x) #f #t)))
      #f)
    #f)))

(def %lint-first-rest (fn (_ form)
  (if (%lint-literal-non-list? (first (rest form)))
    (set-first! %lint-issues
      (pair (convert (first form) %string) (first %lint-issues)))
    ())
  (%lint-seq form)))            ; record use of first/rest + recurse into the arg

; --- def-in-tail-position leak check ---
;
; A `def` in a fn/op body's TAIL position binds GLOBALLY, not locally: TCO pops
; the closure frame before the tail runs, so `def` sees an empty save-stack and
; writes to the global BST -- silently clobbering any caller variable of the
; same name.  The fix is always `let`.  From each fn/op body's last form we
; descend the "leak zone" -- through `do` (every form), `if`/`when`/`unless`
; (branches) and `match` (clause results) -- recording each `def` found.  We
; STOP at `let`/`fn`/`op`/`guard`/calls: those push a fresh frame, ending the
; zone (their inner defs are local again).

; Last element of a list (the tail/return form of a body).
(def %last (fn (self xs)
  (if (pair? xs) (if (pair? (rest xs)) (self (rest xs)) (first xs)) xs)))

(def %lint-leak! (fn (_ form)
  (set-first! %lint-leaks (pair (%lint-bound-name form) (first %lint-leaks)))))

(def %lint-leak-scan (fn (_ form)
  (if (if (pair? form) (symbol? (first form)) ())
    (let ((h (convert (first form) %string)))
      (match
        ((str=? h "def")    (%lint-leak! form))
        ((str=? h "do")     (%lint-leak-list (rest form)))
        ((str=? h "if")     (%lint-leak-list (rest (rest form))))      ; then/else
        ((str=? h "when")   (%lint-leak-list (rest (rest form))))
        ((str=? h "unless") (%lint-leak-list (rest (rest form))))
        ((str=? h "match")  (%lint-leak-clauses (rest form)))
        (#t ())))                                                       ; zone ends
    ()))) ; non-list / non-symbol head: nothing to flag

(def %lint-leak-list (fn (self forms)
  (if (pair? forms) (do (%lint-leak-scan (first forms)) (self (rest forms))) ())))

; match clause = (test result); the result form is in tail position.
(def %lint-leak-clauses (fn (self clauses)
  (if (pair? clauses)
    (do (if (pair? (first clauses)) (%lint-leak-scan (first (rest (first clauses)))) ())
        (self (rest clauses)))
    ())))

; --- Per-form handlers (scope-aware; scope holds name strings) ---

(def %lint-fn (fn (_ form)
  (def saved (first %lint-scope))
  (set-first! %lint-scope (%add-params (first (rest form)) saved))
  (%lint-seq (rest (rest form)))
  (%lint-leak-scan (%last (rest (rest form))))   ; flag def in the body's tail
  (set-first! %lint-scope saved)))

(def %lint-op (fn (_ form)
  (def saved (first %lint-scope))
  (set-first! %lint-scope
    (pair (convert (first (rest (rest form))) %string)
          (%add-params (first (rest form)) saved)))
  (%lint-seq (rest (rest (rest form))))
  (%lint-leak-scan (%last (rest (rest (rest form)))))   ; flag def in the body's tail
  (set-first! %lint-scope saved)))

(def %lint-let-bindings (fn (self bindings)
  (if (null? bindings) ()
    (do (%lint-form (first (rest (first bindings))))   ; init in current scope
        (%scope-add! (convert (first (first bindings)) %string))
        (self (rest bindings))))))

(def %lint-let (fn (_ form)
  (def saved (first %lint-scope))
  (def a (first (rest form)))
  (if (symbol? a)
    (do (%scope-add! (convert a %string))              ; named let
        (%lint-let-bindings (first (rest (rest form))))
        (%lint-seq (rest (rest (rest form))))
        (%lint-leak-scan (%last (rest (rest (rest form))))))  ; let body has its own tail
    (do (%lint-let-bindings a)                         ; regular let
        (%lint-seq (rest (rest form)))
        (%lint-leak-scan (%last (rest (rest form))))))
  (set-first! %lint-scope saved)))

(def %lint-def (fn (_ form)
  (def name-part (first (rest form)))
  (if (pair? name-part)
    (let ((saved (first %lint-scope)))                 ; (def (name params) body)
        (%scope-add! (convert (first name-part) %string))
        (set-first! %lint-scope (%add-params (rest name-part) (first %lint-scope)))
        (%lint-seq (rest (rest form)))
        (%lint-leak-scan (%last (rest (rest form))))   ; def-form body has its own tail
        (set-first! %lint-scope saved))
    (do (%scope-add! (convert name-part %string))      ; (def name val): self-ref ok
        (%lint-form (first (rest (rest form))))))))

(def %lint-set (fn (_ form)
  (%lint-form (first (rest form)))
  (%lint-form (first (rest (rest form))))))

(def %lint-guard (fn (_ form)
  (def clause (first (rest form)))
  (def saved (first %lint-scope))
  (%scope-add! (convert (first clause) %string))       ; error var for the handler
  (%lint-form (first (rest clause)))
  (set-first! %lint-scope saved)
  (%lint-seq (rest (rest form)))))                     ; body in outer scope

(def %lint-quasi (fn (self form)
  (if (null? form) ()
    (if (pair? form)
      (if (if (symbol? (first form)) (str=? (convert (first form) %string) "unquote") #f)
          (%lint-form (first (rest form)))
        (if (if (symbol? (first form)) (str=? (convert (first form) %string) "unquote-splicing") #f)
            (%lint-form (first (rest form)))
          (do (self (first form)) (self (rest form)))))
      ()))))

; --- Default hook implementations (tools/lint.x overrides these) ---

(set! %lint-binds? (fn (_ form)
  (if (if (pair? form) (symbol? (first form)) ())
    (str=? (convert (first form) %string) "def")
    ())))

(set! %lint-bound-name (fn (_ form)
  (let ((np (first (rest form))))
    (convert (if (pair? np) (first np) np) %string))))

; Hardcoded special forms (by name); everything else is a function call.
(set! %lint-dispatch (fn (_ form)
  (def head (first form))
  (if (not (symbol? head)) (%lint-seq form)
    (let ((h (convert head %string)))
      (match
        ((str=? h "fn")    (%lint-fn form))
        ((str=? h "op")    (%lint-op form))
        ((str=? h "let")   (%lint-let form))
        ((str=? h "def")   (%lint-def form))
        ((str=? h "set!")  (%lint-set form))
        ((str=? h "guard") (%lint-guard form))
        ((str=? h "quasi") (%lint-quasi (rest form)))
        ((str=? h "lit")   ())
        ((str=? h "if")    (%lint-seq (rest form)))
        ((str=? h "do")    (%lint-seq (rest form)))
        ((str=? h "match") (%lint-seq (rest form)))
        ((str=? h "first") (%lint-first-rest form))
        ((str=? h "rest")  (%lint-first-rest form))
        (#t                (%lint-seq form)))))))

; --- The write handlers ---

; SYMBOL: record its NAME unless bound or already seen.
(def %lint-symbol-handler (fn (_ sym)
  (let ((name (convert sym %string)))
    (if (%name-member? name (first %lint-scope)) ()
      (if (%name-member? name (first %lint-uses)) ()
        (set-first! %lint-uses (pair name (first %lint-uses))))))
  ()))

; LIST: delegate to the (swappable) dispatch; return nil (output is unused).
(def %lint-list-handler (fn (_ form) (%lint-dispatch form) ()))

(def %lint-push (fn (_)
  (type-push-write %lint-list-type %lint-list-handler)
  (type-push-write %lint-symbol-type %lint-symbol-handler)))

(def %lint-pop (fn (_)
  (type-pop-write %lint-list-type)
  (type-pop-write %lint-symbol-type)))

; --- Analysis entry points ---

(def %lint-top (fn (self forms defs)
  (if (null? forms) defs
    ; `let`, not `def`: this is %lint-top's tail, so a `def` here would itself
    ; leak (the very bug we detect).  We dogfood the fix.
    (let ((form (first forms))
          (new-defs (if (%lint-binds? (first forms))
                      (pair (%lint-bound-name (first forms)) defs) defs)))
      (set-first! %lint-scope ())
      (write-to-str form)                              ; drive the walk (string discarded)
      (self (rest forms) new-defs)))))

(doc (def lint-forms (fn (_ forms defs uses)
  (set-first! %lint-uses uses)
  (set-first! %lint-issues ())
  (set-first! %lint-leaks ())
  (set-first! %lint-scope ())
  (%lint-push)
  (def result-defs (%lint-top forms defs))
  (%lint-pop)
  (list result-defs (first %lint-uses) (first %lint-issues) (first %lint-leaks))))
  (param forms LIST "List of top-level forms to analyze")
  (param defs LIST "Accumulator for defined symbol NAMES")
  (param uses LIST "Accumulator for used symbol NAMES")
  (returns LIST "(defs uses issues leaks) -- all NAME STRINGS; issues are op names for first/rest on a literal non-list; leaks are def names that bind in tail position")
  "Walk top-level forms via the write stacks, collecting def/use names, first/rest issues, and tail-position def leaks.")

(doc (def lint-undefined (fn (_ defs uses)
  (filter (fn (_ name)
    (if (%name-member? name defs) ()
      (if (%env-known? name) () #t)))
    uses)))
  (param defs LIST "Defined names from lint-forms")
  (param uses LIST "Used names from lint-forms")
  (returns LIST "Names used but not defined")
  "Compute undefined names: used but not in env or file defs.")

(doc (def lint-unused (fn (_ defs uses lib-mode)
  (if lib-mode ()
    (filter (fn (_ name)
      (if (Str starts? "%" name) ()
        (if (%name-member? name uses) () #t)))
      defs))))
  (param defs LIST "Defined names from lint-forms")
  (param uses LIST "Used names from lint-forms")
  (param lib-mode BOOLEAN "If true, skip unused check")
  (returns LIST "Names defined but never used")
  "Compute unused names: defined but not referenced. Skips %-prefixed internals.")

(doc (def lint-first-rest (fn (_ result) (first (rest (rest result)))))
  (param result LIST "Result of lint-forms")
  (returns LIST "Op names (first/rest) applied to a literal non-list")
  "Extract the first/rest-on-non-list findings from a lint-forms result.")

(doc (def lint-leaks (fn (_ result) (first (rest (rest (rest result))))))
  (param result LIST "Result of lint-forms")
  (returns LIST "Def names that bind in tail position (leak to global; use let)")
  "Extract the tail-position-def leak findings from a lint-forms result.")

(doc (def lint-has? (fn (_ name names) (%name-member? name names)))
  (param name STRING "A symbol name")
  (param names LIST "A list of names (e.g. from lint-undefined)")
  (returns BOOL "#t if name is in names")
  "Test whether a name string is in a names list (string equality).")

(doc (provide x/tool/lint
  lint-forms lint-undefined lint-unused lint-first-rest lint-leaks lint-has?)
  "AST linter via the type-system write stacks: name-based def/use analysis + first/rest + tail-def-leak checks.")
