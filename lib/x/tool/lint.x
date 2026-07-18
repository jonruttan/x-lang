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
; Fetch the string prims from the catalog (ns `str` is de-registered, R5).
(def %str->symbol (prim-ref (lit str) (lit ->sym)))

; Fetch the type-system helpers from the catalog (registered by sys/type.x).
(def %type-by-atom (prim-ref (lit type) (lit by-atom)))
(def %type-push-write (prim-ref (lit type) (lit push-write)))
(def %type-pop-write (prim-ref (lit type) (lit pop-write)))

; Fetch the conversion dispatcher from the catalog (registered by sys/convert.x).
(def %cvt (prim-ref (lit convert) (lit to)))
; Fetch the type prims from the catalog (ns `type` is de-registered, R5).
(def %type-of (prim-ref (lit type) (lit of)))


(import x/core/alist)
(import x/type/str)
; Fetch the io plumbing prims from the catalog (ns `io` partly de-registered, R5).
(def %write-to-str (prim-ref (lit io) (lit write-to-str)))

(import x/sys/type)

; Type structs we attach handlers to (LIST = forms, SYMBOL = references).
(def %lint-list-type   (%type-by-atom (%type-of (list 1))))
(def %lint-symbol-type (%type-by-atom (%type-of (lit a))))

; A name is "known" if it resolves to an existing binding -- a C primitive or
; a library def.  We test by evaluating the interned symbol under a guard:
; bound -> its value (known), unbound -> the lookup errors -> #f.  (Evaluating
; a bare symbol is a pure lookup, no side effects.)  This replaces a former
; base-layout-dependent env-alist dig that broke when the base layout drifted
; and produced false "undefined" reports for every primitive.
(def %env-known? (fn (_ name)
  (guard (_ #f) (do (eval! (%str->symbol name)) #t))))

; --- Analysis state (boxes; all values are NAME STRINGS) ---
(def %lint-scope  (list ()))    ; names in lexical scope
(def %lint-uses   (list ()))    ; names referenced (unique)
(def %lint-issues (list ()))    ; op names where first/rest hit a literal non-list
(def %lint-leaks  (list ()))    ; def names that bind in tail position (leak to global)

; --- Pedantic findings (kind . name) pairs; one bag for all the extra checks ---
; x-lang does not enforce arity (missing args -> nil, extra -> ignored) and
; silently overwrites redefinitions, so these mistakes never error at runtime;
; the linter is the only thing that catches them.
(def %lint-warn (list ()))
(def %warn! (fn (_ kind name)
  (set-first! %lint-warn (pair (pair kind name) (first %lint-warn)))))

; Swappable hooks -- tools/lint.x overrides these for data-driven, construct-
; table dispatch.  Forward-declared; defaults set below once the helpers exist.
(def %lint-binds? ())      ; form -> truthy if it binds a name in a sequence
(def %lint-bound-name ())  ; form -> the bound name (a STRING)
(def %lint-dispatch ())    ; form -> () : scope-aware analysis of one list form

; str=? membership over a list of name strings.
(def %name-member? (fn (self name names)
  (if (null? names) ()
    (if (str=? name (first names)) #t (self name (rest names))))))

; Unwrap (doc DEFN meta...) -> DEFN so def-name and arity collection see the
; real (def ...) / (set! ...) underneath.  Most lib functions are doc-wrapped;
; without this the linter is blind to their definitions -- arity can't check
; them and in-file self-references look "undefined".
(def %lint-unwrap-doc (fn (_ form)
  (if (if (pair? form) (symbol? (first form)) #f)
    (if (str=? (%cvt (first form) %string) "doc") (first (rest form)) form)
    form)))

; --- Scope helpers (scope holds name strings) ---

; The NAME of one parameter slot.  A slot is normally a bare symbol, but the
; doc DSL lets a fn inline its param docs: (fn (self (param p TYPE "d") ...) ..)
; -- there the real name is the 2nd element of the (param ...) form.  Without
; this, the whole (param ...) form gets stringified and the actual parameter
; is never added to scope (so its uses look "undefined").
(def %param-name (fn (_ p)
  (if (pair? p)
    (if (if (symbol? (first p)) (str=? (%cvt (first p) %string) "param") #f)
      (%cvt (first (rest p)) %string)   ; (param NAME TYPE "desc") -> NAME
      (%cvt (first p) %string))          ; other pair -> its head
    (%cvt p %string))))                  ; bare symbol

; Does scope (a list of (name . used-box) entries) already bind this name?
(def %scope-has-name? (fn (self pn scope)
  (if (null? scope) ()
    (if (str=? pn (first (first scope))) #t
      (self pn (rest scope))))))

; Warn "shadow" when nm shadows an ENCLOSING LOCAL already present in `scope`
; (an outer param/let-var, or an earlier param of the same list -- a duplicate).
; We deliberately do NOT warn for shadowing a global: param names like
; `rest`/`name`/`op` routinely and harmlessly shadow library functions, and
; flagging every one drowned the signal.  Lexical shadows -- an inner binding
; hiding an outer one of the same name -- are the actual footgun.  `_` and
; `self` are conventional self-slot names that nested scopes reuse on purpose,
; so they are never flagged.
(def %shadow-check! (fn (_ nm scope)
  (if (if (if (str=? nm "_") #t (str=? nm "self")) #f (%scope-has-name? nm scope))
    (%warn! "shadow" nm) ())))

; Add one parameter to scope as a (name . used-box) entry, checking for shadows
; against the params/enclosing bindings accumulated so far.
(def %add-param-name (fn (_ pn scope)
  (%shadow-check! pn scope)
  (pair (pair pn (list #f)) scope)))

; A REST param (`. rest` / variadic) collects "any extra args"; uniform
; signatures routinely accept one and ignore it, so an unused rest param is not
; a finding.  We still shadow-check it, but pre-mark its used-box #t so it is
; never reported unused (and, being the last/trailing slot, it does not mask a
; genuine trailing-unused fixed param -- there is none after a rest).
(def %add-rest-name (fn (_ pn scope)
  (%shadow-check! pn scope)
  (pair (pair pn (list #t)) scope)))

(def %add-params (fn (self params scope)
  (if (null? params) scope
    (if (symbol? params) (%add-rest-name (%cvt params %string) scope)   ; improper tail = rest
      (if (pair? params)
        ; A bare `param` symbol is the flattened remnant of an inline-doc rest
        ; param `. (param NAME TYPE "desc")` (the reader flattens `. (list)`):
        ; the NEXT element is the real rest-param name; add it and stop, since
        ; everything after is doc metadata (TYPE, description), not params.
        (if (if (symbol? (first params)) (str=? (%cvt (first params) %string) "param") #f)
          (if (pair? (rest params))
            (%add-rest-name (%param-name (first (rest params))) scope)
            scope)
          (self (rest params) (%add-param-name (%param-name (first params)) scope)))
        scope)))))

(def %scope-add! (fn (_ name)
  (set-first! %lint-scope (pair (pair name (list #f)) (first %lint-scope)))))

; A reference resolved to a local: find it in scope, flip its used-box to #t,
; and return #t.  Return () when name is not a local (a free/global reference).
; This is how we learn which locals are actually used.  Walks from the head, so
; the INNERMOST binding of a shadowed name is the one marked (lexically correct).
(def %scope-mark-used! (fn (self name scope)
  (if (null? scope) ()
    (if (str=? name (first (first scope)))
      (do (set-first! (rest (first scope)) #t) #t)
      (self name (rest scope))))))

; When a scope frame closes, the entries added since `saved` are this frame's
; own locals (the prefix of the scope list before `saved`).  Warn "unused" for
; any whose used-box is still #f.  We find the prefix by LENGTH difference, not
; by eq? on the `saved` tail: GC can relocate heap pairs between write-stack
; callbacks, so pointer identity is unsafe.  `_` is exempt.
(def %check-unused! (fn (self entries n)
  (if (if (> n 0) (pair? entries) #f)
    (do (if (if (str=? (first (first entries)) "_") #f
              (not (first (rest (first entries)))))
          (%warn! "unused" (first (first entries))) ())
        (self (rest entries) (- n 1)))
    ())))

(def %frame-unused! (fn (_ saved)
  (%check-unused! (first %lint-scope)
    (- (length (first %lint-scope)) (length saved)))))

; Parameters are POSITIONAL: a middle unused param cannot be dropped without
; shifting the ones after it, and fixed-signature callbacks (e.g. a reader's
; (_ buffer score chr)) must declare slots they don't all use.  So we flag only
; TRAILING unused params -- walking from the last param backward (entries are in
; reverse source order) and stopping at the first one that IS used.  `_` is
; never flagged but does not stop the scan (an ignored trailing slot is fine).
(def %check-trailing-unused! (fn (self entries n)
  (if (if (> n 0) (pair? entries) #f)
    (if (first (rest (first entries)))            ; used -> earlier params are positional; stop
      ()
      (do (if (str=? (first (first entries)) "_") ()
            (%warn! "unused" (first (first entries))))
          (self (rest entries) (- n 1))))
    ())))

; Does `form` reference a symbol named `name` (recursively, skipping (lit ...)
; data)?  Used to recognise the rebind idiom (let ((x (f x))) ...): a let-var
; whose init mentions the name it shadows is a deliberate refinement, not an
; accidental hide, so it should not be flagged as a shadow.
(def %form-mentions? (fn (self name form)
  (if (pair? form)
    (if (if (symbol? (first form)) (str=? (%cvt (first form) %string) "lit") #f)
      #f
      (if (self name (first form)) #t (self name (rest form))))
    (if (symbol? form) (str=? (%cvt form %string) name) #f))))

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
            (let ((bn (%lint-bound-name (first forms))))
              ; %lint-def already added this name to the persistent scope (its
              ; else-branch does no save/restore).  Re-adding would create a
              ; second box that nothing marks -> a phantom "unused".  Only add
              ; when it is not already in scope.
              (if (%scope-has-name? bn (first %lint-scope)) () (%scope-add! bn)))
            ())
          (self (rest forms)))
      (%lint-form forms)))))

; --- first/rest argument check ---

; True when arg is a quoted non-list literal: (lit X) with X neither pair nor
; nil -- exactly (first 'sym) / (rest 'sym), the static form of the crash.
; Compared by name (the head symbol is fresh -- it is part of the walked form).
(def %lint-literal-non-list? (fn (_ arg)
  (if (pair? arg)
    (if (if (symbol? (first arg)) (str=? (%cvt (first arg) %string) "lit") #f)
      (let ((x (first (rest arg))))
        (if (null? x) #f (if (pair? x) #f #t)))
      #f)
    #f)))

(def %lint-first-rest (fn (_ form)
  (if (%lint-literal-non-list? (first (rest form)))
    (set-first! %lint-issues
      (pair (%cvt (first form) %string) (first %lint-issues)))
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
    (let ((h (%cvt (first form) %string)))
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
  (def params (first %lint-scope))               ; param entries (boxes shared with scope)
  (def nparams (- (length params) (length saved)))
  (%lint-seq (rest (rest form)))
  (%lint-leak-scan (%last (rest (rest form))))   ; flag def in the body's tail
  (%check-unused! (first %lint-scope)            ; body-level defs above params: any unused is dead
    (- (length (first %lint-scope)) (length params)))
  (%check-trailing-unused! params nparams)       ; params: only trailing unused (positional)
  (set-first! %lint-scope saved)))

(def %lint-op (fn (_ form)
  (def saved (first %lint-scope))
  (set-first! %lint-scope
    (pair (pair (%cvt (first (rest (rest form))) %string) (list #f))   ; env var entry
          (%add-params (first (rest form)) saved)))
  (def params (first %lint-scope))                      ; params + env var (boxes shared)
  (def nparams (- (length params) (length saved)))
  (%lint-seq (rest (rest (rest form))))
  (%lint-leak-scan (%last (rest (rest (rest form)))))   ; flag def in the body's tail
  (%check-unused! (first %lint-scope)
    (- (length (first %lint-scope)) (length params)))
  (%check-trailing-unused! params nparams)
  (set-first! %lint-scope saved)))

(def %lint-let-bindings (fn (self bindings)
  (if (null? bindings) ()
    (do (%lint-form (first (rest (first bindings))))   ; init in current scope
        (let ((vn (%cvt (first (first bindings)) %string)))
          ; skip the rebind idiom (let ((x (f x))) ..): init mentions x -> a
          ; deliberate refinement, not an accidental hide
          (if (%form-mentions? vn (first (rest (first bindings)))) ()
            (%shadow-check! vn (first %lint-scope)))   ; let-var hiding an enclosing local
          (%scope-add! vn))
        (self (rest bindings))))))

(def %lint-let (fn (_ form)
  (def saved (first %lint-scope))
  (def a (first (rest form)))
  (if (symbol? a)
    (do (%scope-add! (%cvt a %string))              ; named let
        (%lint-let-bindings (first (rest (rest form))))
        (%lint-seq (rest (rest (rest form))))
        (%lint-leak-scan (%last (rest (rest (rest form))))))  ; let body has its own tail
    (do (%lint-let-bindings a)                         ; regular let
        (%lint-seq (rest (rest form)))
        (%lint-leak-scan (%last (rest (rest form))))))
  (%frame-unused! saved)                               ; flag let-bindings never referenced
  (set-first! %lint-scope saved)))

(def %lint-def (fn (_ form)
  (def name-part (first (rest form)))
  (if (pair? name-part)
    (let ((saved (first %lint-scope)))                 ; (def (name params) body)
        (%scope-add! (%cvt (first name-part) %string))
        (set-first! %lint-scope (%add-params (rest name-part) (first %lint-scope)))
        (%lint-seq (rest (rest form)))
        (%lint-leak-scan (%last (rest (rest form))))   ; def-form body has its own tail
        (set-first! %lint-scope saved))
    (do (%scope-add! (%cvt name-part %string))      ; (def name val): self-ref ok
        (%lint-form (first (rest (rest form))))))))

(def %lint-set (fn (_ form)
  (%lint-form (first (rest form)))
  (%lint-form (first (rest (rest form))))))

(def %lint-guard (fn (_ form)
  (def clause (first (rest form)))
  (def saved (first %lint-scope))
  (%scope-add! (%cvt (first clause) %string))       ; error var for the handler
  (def evar (first (first %lint-scope)))               ; its (name . used-box) entry
  (%lint-seq (rest clause))                            ; walk ALL handler forms
  ; Check only the error var.  A handler may `def` names that leak to the
  ; enclosing scope and are used by the body or elsewhere (e.g. fallback
  ; stubs); those are not locals, so reporting them unused would be wrong --
  ; only the error var's scope is truly the handler.
  (if (str=? (first evar) "_") ()
    (if (first (rest evar)) () (%warn! "unused" (first evar))))
  (set-first! %lint-scope saved)
  (%lint-seq (rest (rest form)))))                     ; body in outer scope

(def %lint-quasi (fn (self form)
  (if (null? form) ()
    (if (pair? form)
      (if (if (symbol? (first form)) (str=? (%cvt (first form) %string) "unquote") #f)
          (%lint-form (first (rest form)))
        (if (if (symbol? (first form)) (str=? (%cvt (first form) %string) "unquote-splicing") #f)
            (%lint-form (first (rest form)))
          (do (self (first form)) (self (rest form)))))
      ()))))

; --- Default hook implementations (tools/lint.x overrides these) ---

(set! %lint-binds? (fn (_ form)
  (if (if (pair? form) (symbol? (first form)) ())
    (str=? (%cvt (first form) %string) "def")
    ())))

(set! %lint-bound-name (fn (_ form)
  (let ((np (first (rest form))))
    (%cvt (if (pair? np) (first np) np) %string))))

; Hardcoded special forms (by name); everything else is a function call.
(set! %lint-dispatch (fn (_ form)
  (def head (first form))
  (if (not (symbol? head)) (%lint-seq form)
    (let ((h (%cvt head %string)))
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

; --- Arity + non-callable checks ---
;
; x-lang fn calls are lenient: missing args bind to nil, extra are ignored, so
; a wrong-arity call never errors -- only the linter catches it.  We collect
; arities of file-local named fns in a pre-pass and flag mismatching calls.  A
; fn's first param is the implicit self, so callable arity = (proper params) -
; 1; an improper tail (. rest) means variadic (a minimum only).

(def %lint-arity (list ()))   ; alist: (name . (min . variadic?))

(def %alist-find-name (fn (self name alist)
  (if (null? alist) ()
    (if (str=? (first (first alist)) name) (first alist)
      (self name (rest alist))))))

(def %params-arity (fn (self params n)   ; -> (proper-count . variadic?)
  (if (null? params) (pair n #f)
    (if (pair? params)
      ; A bare `param` symbol element is the flattened remnant of an inline-doc
      ; rest param `. (param NAME ...)` (the reader flattens `. (list)`), so the
      ; rest is variadic.  (A param literally named `param` is vanishingly rare.)
      (if (if (symbol? (first params)) (str=? (%cvt (first params) %string) "param") #f)
        (pair n #t)
        (self (rest params) (+ n 1)))
      (pair n #t))))) ; bare symbol tail -> rest param

(def %fn-arity (fn (_ fn-form)           ; (fn PARAMS body) -> (callable-min . variadic?)
  ; A fn's first param is the implicit self, so callable = params - 1 -- except
  ; (fn () ...) has NO self slot, so floor at 0 (0 params -> 0 callable, not -1).
  (let ((pa (%params-arity (first (rest fn-form)) 0)))
    (pair (if (< (first pa) 1) 0 (- (first pa) 1)) (rest pa)))))

(def %arity-record (fn (_ name val)
  (if (if (pair? val) (symbol? (first val)) #f)
    (if (if (str=? (%cvt (first val) %string) "fn") (symbol? name) #f)
      (set-first! %lint-arity
        (pair (pair (%cvt name %string) (%fn-arity val)) (first %lint-arity)))
      ())
    ())))

; Pre-pass over top-level (def NAME (fn ..)) / (set! NAME (fn ..)).
(def %arity-collect (fn (self forms)
  (if (pair? forms)
    (do (let ((f (%lint-unwrap-doc (first forms))))
          (if (if (pair? f) (symbol? (first f)) #f)
            (if (if (str=? (%cvt (first f) %string) "def") #t
                  (str=? (%cvt (first f) %string) "set!"))
              (%arity-record (first (rest f)) (first (rest (rest f))))
              ())
            ()))
        (self (rest forms)))
    ())))

(def %lint-check-arity (fn (_ form)
  (let ((entry (if (if (pair? form) (symbol? (first form)) #f)
                 (%alist-find-name (%cvt (first form) %string) (first %lint-arity))
                 ())))
    (if (null? entry) ()
      (let ((nargs (- (length form) 1))
            (mn (first (rest entry)))
            (vararg (rest (rest entry))))
        (if (if vararg (< nargs mn) (not (= nargs mn)))
          (%warn! "arity" (first entry))
          ()))))))

; A code form whose head is a (lit ...) form calls a non-function (it
; evaluates to a symbol/value, not a procedure) -- a clear bug.  We do NOT
; flag a bare-literal head (number/string/char): such a list is usually DATA
; passed unevaluated to an operative (e.g. ("0" 0) as a pad spec), which the
; linter cannot distinguish from a call.
(def %lint-noncallable? (fn (_ head)
  (if (pair? head)
    (if (symbol? (first head)) (str=? (%cvt (first head) %string) "lit") #f)
    #f)))

; --- Malformed core form check ---
; Minimum total length for forms whose structure is required.  x-lang is
; lenient at runtime (a missing piece just becomes nil), so a structurally
; short core form is a silent mistake.
(def %lint-min-len (fn (_ h)
  (if (str=? h "if") 3              ; (if cond then [else])
    (if (str=? h "def") 3           ; (def name value)
      (if (str=? h "set!") 3        ; (set! name value)
        (if (str=? h "fn") 2        ; (fn params [body...])
          (if (str=? h "op") 3      ; (op params env [body...])
            (if (str=? h "let") 2   ; (let bindings [body...])
              0))))))))             ; 0 = no minimum

(def %lint-check-malformed (fn (_ form)
  (if (if (pair? form) (symbol? (first form)) #f)
    (let ((mn (%lint-min-len (%cvt (first form) %string))))
      (if (if (= mn 0) #f (< (length form) mn))
        (%warn! "malformed" (%cvt (first form) %string))
        ()))
    ())))

; --- The write handlers ---

; SYMBOL: record its NAME unless bound or already seen.
(def %lint-symbol-handler (fn (_ sym)
  (let ((name (%cvt sym %string)))
    (if (%scope-mark-used! name (first %lint-scope)) ()   ; local ref -> mark its box used
      (if (%name-member? name (first %lint-uses)) ()
        (set-first! %lint-uses (pair name (first %lint-uses))))))
  ()))

; LIST: run the head/arity checks, then delegate to the (swappable) dispatch.
; Doing the checks here (not in %lint-dispatch) means both the lib's default
; dispatch and tools/lint.x's construct-table override get them for free.
(def %lint-list-handler (fn (_ form)
  (if (%lint-noncallable? (first form))
    (%warn! "call-nonfn" (guard (_ "?") (%cvt (first form) %string)))
    ())
  (%lint-check-arity form)
  (%lint-check-malformed form)
  (%lint-dispatch form) ()))

(def %lint-push (fn (_)
  (%type-push-write %lint-list-type %lint-list-handler)
  (%type-push-write %lint-symbol-type %lint-symbol-handler)))

(def %lint-pop (fn (_)
  (%type-pop-write %lint-list-type)
  (%type-pop-write %lint-symbol-type)))

; --- Analysis entry points ---

(def %lint-top (fn (self forms defs)
  (if (null? forms) defs
    ; `let`, not `def`: this is %lint-top's tail, so a `def` here would itself
    ; leak (the very bug we detect).  We dogfood the fix.
    (let ((form (first forms)))
      (let ((eff (%lint-unwrap-doc form)))             ; see through (doc (def ..) ..)
        (let ((nm (if (%lint-binds? eff) (%lint-bound-name eff) ())))
          (if (if (null? nm) #f (%name-member? nm defs))
            (%warn! "dup-def" nm) ())                  ; same top-level name defined twice
          (set-first! %lint-scope ())
          (%write-to-str form)                         ; drive the walk (string discarded)
          (self (rest forms) (if (null? nm) defs (pair nm defs)))))))))

(doc (def lint-forms (fn (_ forms defs uses)
  (set-first! %lint-uses uses)
  (set-first! %lint-issues ())
  (set-first! %lint-leaks ())
  (set-first! %lint-warn ())
  (set-first! %lint-arity ())
  (set-first! %lint-scope ())
  (%arity-collect forms)                             ; pre-pass: file-local fn arities
  (%lint-push)
  (def result-defs (%lint-top forms defs))
  (%lint-pop)
  (list result-defs (first %lint-uses) (first %lint-issues)
        (first %lint-leaks) (first %lint-warn))))
  (param forms LIST "List of top-level forms to analyze")
  (param defs LIST "Accumulator for defined symbol NAMES")
  (param uses LIST "Accumulator for used symbol NAMES")
  (returns LIST "(defs uses issues leaks warnings) -- defs/uses/issues/leaks are NAME STRINGS; warnings are (kind . name) pairs for arity / call-nonfn / dup-def / malformed / shadow / unused")
  "Walk top-level forms via the write stacks, collecting def/use names, first/rest issues, tail-position def leaks, and pedantic warnings (arity, non-callable calls, duplicate defs, malformed forms, lexical shadows, and unused locals).")

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
  (param lib-mode BOOL "If true, skip unused check")
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

(doc (def lint-warnings (fn (_ result) (first (rest (rest (rest (rest result)))))))
  (param result LIST "Result of lint-forms")
  (returns LIST "Pedantic findings as (kind . name) pairs")
  "Extract all pedantic warnings (arity, call-nonfn, dup-def, ...) from a result.")

(doc (def lint-warnings-of (fn (_ kind result)
  (map (fn (_ w) (rest w))
    (filter (fn (_ w) (str=? (first w) kind)) (lint-warnings result)))))
  (param kind STRING "Warning kind: arity | call-nonfn | dup-def | malformed | shadow | unused")
  (param result LIST "Result of lint-forms")
  (returns LIST "The names for warnings of that kind")
  "Filter pedantic warnings to one kind, returning their names.")

(doc (def lint-has? (fn (_ name names) (%name-member? name names)))
  (param name STRING "A symbol name")
  (param names LIST "A list of names (e.g. from lint-undefined)")
  (returns BOOL "#t if name is in names")
  "Test whether a name string is in a names list (string equality).")

(doc (provide x/tool/lint
  lint-forms lint-undefined lint-unused lint-first-rest lint-leaks
  lint-warnings lint-warnings-of lint-has?)
  "AST linter via the type-system write stacks: name-based def/use analysis + first/rest + tail-def-leak + pedantic (arity / non-callable / duplicate-def) checks.")
