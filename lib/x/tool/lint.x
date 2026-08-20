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
(def %str->symbol (prim-ref 'str '->sym))

; Fetch the type-system helpers from the catalog (registered by sys/type.x).
(def %type-by-atom (prim-ref 'type 'by-atom))
(def %type-push-write (prim-ref 'type 'push-write))
(def %type-pop-write (prim-ref 'type 'pop-write))

; Fetch the conversion dispatcher from the catalog (registered by sys/convert.x).
(def %cvt (prim-ref 'convert 'to))
; Fetch the type prims from the catalog (ns `type` is de-registered, R5).
(def %type-of (prim-ref 'type 'of))


(import x/core/alist)
(import x/type/str)
; Fetch the io plumbing prims from the catalog (ns `io` partly de-registered, R5).
(def %write-to-str (prim-ref 'io 'write-to-str))

(import x/type/struct)

; Type structs we attach handlers to (LIST = forms, SYMBOL = references).
(def %lint-list-type   (%type-by-atom (%type-of (list 1))))
(def %lint-symbol-type (%type-by-atom (%type-of 'a)))

; A name is "known" if it resolves to an existing binding -- a C primitive or
; a library def.  We test by evaluating the interned symbol under a guard:
; bound -> its value (known), unbound -> the lookup errors -> #f.  (Evaluating
; a bare symbol is a pure lookup, no side effects.)  This replaces a former
; base-layout-dependent env-alist dig that broke when the base layout drifted
; and produced false "undefined" reports for every primitive.
; Embedder-contract names: documented as supplied by the embedder BEFORE the
; library loads (boot/module.x -- "%install-root"), deliberately unbound in a
; repo-mode session, and every use is guarded.  Known by contract, not env.


; --- Analysis state (boxes; all values are NAME STRINGS) ---
(def %lint-scope  (list ()))    ; names in lexical scope
(def %lint-uses   (list ()))    ; names referenced (unique, in first-seen order)
; ADJUDICATED BY BENCHMARK (#344): membership stays %member-str? and
; the tables stay alists.  A Dict variant was built and measured SLOWER
; (5.6s vs 4.0s on class.x): every (d get k) rides the class value-call
; dispatch, which loses to a few hundred C-speed str=? probes -- and
; the x/type/dict import cost ~0.1s per lint boot besides.  Re-visit
; only with a dispatch-free table or the #323 batch harness landed.
; The current list node's head, converted ONCE per node by the list
; handler (#344): arity/malformed/dispatch each re-ran the conversion
; catalog on the same head -- 5-6 full %convert-to dispatches per node.
; Valid only within the handler's dynamic extent; nil for non-symbol
; heads.
(def %lint-head-cell (list ()))
(def %lint-issues (list ()))    ; op names where first/rest hit a literal non-list
(def %lint-leaks  (list ()))    ; def names that bind in tail position (leak to global)

; --- Pedantic findings (kind . name) pairs; one bag for all the extra checks ---
; x-lang does not enforce arity (missing args -> nil, extra -> ignored) and
; silently overwrites redefinitions, so these mistakes never error at runtime;
; the linter is the only thing that catches them.
(def %lint-warn (list ()))
(def %warn! (fn (_ kind name)
  (%set-first! %lint-warn (pair (pair kind name) (first %lint-warn)))))

; Swappable hooks -- tools/dev/lint.x overrides these for data-driven, construct-
; table dispatch.  Forward-declared; defaults set below once the helpers exist.
(def %lint-binds? ())      ; form -> truthy if it binds a name in a sequence
(def %lint-bound-name ())  ; form -> the bound name (a STRING)
(def %lint-dispatch ())    ; form -> () : scope-aware analysis of one list form


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
; Entries are always pairs, so the canonical entry lookup is safe here.
(def %scope-has-name? (fn (_ pn scope)
  (not (null? (%assoc-str pn scope)))))

; Warn "shadow" when nm shadows an ENCLOSING LOCAL already present in `scope`
; (an outer param/let-var, or an earlier param of the same list -- a duplicate).
; We deliberately do NOT warn for shadowing a global: param names like
; `rest`/`name`/`op` routinely and harmlessly shadow library functions, and
; flagging every one drowned the signal.  Lexical shadows -- an inner binding
; hiding an outer one of the same name -- are the actual footgun.  `_` and
; `self` are conventional self-slot names that nested scopes reuse on purpose,
; so they are never flagged.
(def %shadow-check! (fn (_ nm scope)
  (when (if (if (str=? nm "_") #t (str=? nm "self")) #f (%scope-has-name? nm scope))
    (%warn! "shadow" nm))))

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
  (%set-first! %lint-scope (pair (pair name (list #f)) (first %lint-scope)))))

; A reference resolved to a local: find it in scope, flip its used-box to #t,
; and return #t.  Return () when name is not a local (a free/global reference).
; This is how we learn which locals are actually used.  Walks from the head, so
; the INNERMOST binding of a shadowed name is the one marked (lexically correct).
(def %scope-mark-used! (fn (self name scope)
  (unless (null? scope)
    (if (str=? name (first (first scope)))
      (do (%set-first! (rest (first scope)) #t) #t)
      (self name (rest scope))))))

; When a scope frame closes, the entries added since `saved` are this frame's
; own locals (the prefix of the scope list before `saved`).  Warn "unused" for
; any whose used-box is still #f.  We find the prefix by LENGTH difference, not
; by eq? on the `saved` tail: GC can relocate heap pairs between write-stack
; callbacks, so pointer identity is unsafe.  `_` is exempt.
(def %check-unused! (fn (self entries n)
  (when (if (> n 0) (pair? entries) #f)
    (do (when (if (str=? (first (first entries)) "_") #f
              (not (first (rest (first entries)))))
          (%warn! "unused" (first (first entries))))
        (self (rest entries) (- n 1))))))

(def %frame-unused! (fn (_ saved)
  (%check-unused! (first %lint-scope)
    (- (%length (first %lint-scope)) (%length saved)))))

; Parameters are POSITIONAL: a middle unused param cannot be dropped without
; shifting the ones after it, and fixed-signature callbacks (e.g. a reader's
; (_ buffer score chr)) must declare slots they don't all use.  So we flag only
; TRAILING unused params -- walking from the last param backward (entries are in
; reverse source order) and stopping at the first one that IS used.  `_` is
; never flagged but does not stop the scan (an ignored trailing slot is fine).
(def %check-trailing-unused! (fn (self entries n)
  (when (if (> n 0) (pair? entries) #f)
    (unless (first (rest (first entries)))
      (do (unless (str=? (first (first entries)) "_")
            (%warn! "unused" (first (first entries))))
          (self (rest entries) (- n 1)))))))

; Does `form` reference a symbol named `name` (recursively, skipping '...
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
(def %lint-form (fn (_ form) (unless (null? form) (do (write form) ()))))

; Walk a body/clause sequence; a leading binding form adds its name for the rest.
(def %lint-seq (fn (self forms)
  (unless (null? forms)
    (if (pair? forms)
      ; Adjacent output calls in a SEQUENCE are one variadic call (#291);
      ; warn (advisory) so the swept unary chains do not grow back.
      ; Branch arms are not sequences and never reach here adjacently.
      (do (when (if (Lint %lint-out-verb? (first forms))
                  (if (pair? (rest forms)) (Lint %lint-out-verb? (first (rest forms))) #f)
                  #f)
            (%warn! "display-chain" (%cvt (first (first forms)) %string)))
          (%lint-form (first forms))
          (when (%lint-binds? (first forms))
            (let ((bn (%lint-bound-name (first forms))))
              ; %lint-def already added this name to the persistent scope (its
              ; else-branch does no save/restore).  Re-adding would create a
              ; second box that nothing marks -> a phantom "unused".  Only add
              ; when it is not already in scope.
              (unless (%scope-has-name? bn (first %lint-scope)) (%scope-add! bn))))
          (self (rest forms)))
      (%lint-form forms)))))

; --- first/rest argument check ---

; True when arg is a quoted non-list literal: 'X with X neither pair nor
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
  (when (%lint-literal-non-list? (first (rest form)))
    (%set-first! %lint-issues
      (pair (%cvt (first form) %string) (first %lint-issues))))
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
  (%set-first! %lint-leaks (pair (%lint-bound-name form) (first %lint-leaks)))))

(def %lint-leak-scan (fn (_ form)
  (when (and (pair? form) (symbol? (first form)))
    (let ((h (%cvt (first form) %string)))
      (match
        ((str=? h "def")    (%lint-leak! form))
        ((str=? h "do")     (%lint-leak-list (rest form)))
        ((str=? h "if")     (%lint-leak-list (rest (rest form))))      ; then/else
        ((str=? h "when")   (%lint-leak-list (rest (rest form))))
        ((str=? h "unless") (%lint-leak-list (rest (rest form))))
        ((str=? h "match")  (%lint-leak-clauses (rest form)))
        (#t ())))))) ; non-list / non-symbol head: nothing to flag

(def %lint-leak-list (fn (self forms)
  (when (pair? forms) (do (%lint-leak-scan (first forms)) (self (rest forms))))))

; match clause = (test result); the result form is in tail position.
(def %lint-leak-clauses (fn (self clauses)
  (when (pair? clauses)
    (do (when (pair? (first clauses)) (%lint-leak-scan (first (rest (first clauses)))))
        (self (rest clauses))))))

; --- Per-form handlers (scope-aware; scope holds name strings) ---

(def %lint-fn (fn (_ form)
  (def saved (first %lint-scope))
  (%set-first! %lint-scope (%add-params (first (rest form)) saved))
  (def params (first %lint-scope))               ; param entries (boxes shared with scope)
  (def nparams (- (%length params) (%length saved)))
  (%lint-seq (rest (rest form)))
  (%lint-leak-scan (%last (rest (rest form))))   ; flag def in the body's tail
  (%check-unused! (first %lint-scope)            ; body-level defs above params: any unused is dead
    (- (%length (first %lint-scope)) (%length params)))
  (%check-trailing-unused! params nparams)       ; params: only trailing unused (positional)
  (%set-first! %lint-scope saved)))

(def %lint-op (fn (_ form)
  (def saved (first %lint-scope))
  ; The env slot may be () -- "ignore the caller env", legal at runtime
  ; (apps/logo's logo-repl) -- so only a SYMBOL adds a scope entry.  %cvt
  ; on the nil slot answered nil (catalog misses are silent), and that nil
  ; NAME later reached str=? -- an unchecked C prim -- and crashed.
  (%set-first! %lint-scope
    (let ((envp (first (rest (rest form)))))
      (if (symbol? envp)
        (pair (pair (%cvt envp %string) (list #f))                     ; env var entry
              (%add-params (first (rest form)) saved))
        (%add-params (first (rest form)) saved))))
  (def params (first %lint-scope))                      ; params + env var (boxes shared)
  (def nparams (- (%length params) (%length saved)))
  (%lint-seq (rest (rest (rest form))))
  (%lint-leak-scan (%last (rest (rest (rest form)))))   ; flag def in the body's tail
  (%check-unused! (first %lint-scope)
    (- (%length (first %lint-scope)) (%length params)))
  (%check-trailing-unused! params nparams)
  (%set-first! %lint-scope saved)))

(def %lint-let-bindings (fn (self bindings)
  (unless (null? bindings)
    (do (%lint-form (first (rest (first bindings))))   ; init in current scope
        (let ((vn (%cvt (first (first bindings)) %string)))
          ; skip the rebind idiom (let ((x (f x))) ..): init mentions x -> a
          ; deliberate refinement, not an accidental hide
          (unless (%form-mentions? vn (first (rest (first bindings))))
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
  (%set-first! %lint-scope saved)))

(def %lint-def (fn (_ form)
  (def name-part (first (rest form)))
  (if (pair? name-part)
    (let ((saved (first %lint-scope)))                 ; (def (name params) body)
        (%scope-add! (%cvt (first name-part) %string))
        (%set-first! %lint-scope (%add-params (rest name-part) (first %lint-scope)))
        (%lint-seq (rest (rest form)))
        (%lint-leak-scan (%last (rest (rest form))))   ; def-form body has its own tail
        (%set-first! %lint-scope saved))
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
  (unless (str=? (first evar) "_")
    (unless (first (rest evar)) (%warn! "unused" (first evar))))
  (%set-first! %lint-scope saved)
  (%lint-seq (rest (rest form)))))                     ; body in outer scope

; A match clause evaluates ONE body expression -- anything after it is dead
; code, and the miss is silent: nothing errors, a side effect just never
; happens (#163: the Logo arity-0 branch ran its handler and never recursed).
; There is no legitimate multi-expression clause body, so no allowlist: every
; hit wants a do-wrap.  The warning name is the clause test's head symbol --
; NOT the test rendered: the walk runs with analysis handlers pushed on the
; LIST/SYMBOL write stacks, so %write-to-str on a non-atom here would run the
; analyser, not the printer.
(def %lint-match (fn (_ form)
  (def %clause-extra? (fn (_ clause)
    (match
      ((not (pair? clause)) #f)
      ((not (pair? (rest clause))) #f)
      (#t (not (null? (rest (rest clause))))))))
  (def %clause-name (fn (_ test)
    (match
      ((pair? test) (if (symbol? (first test)) (%cvt (first test) %string) "?"))
      ((symbol? test) (%cvt test %string))
      (#t (guard (_ "?") (%write-to-str test))))))
  (def %scan (fn (self clauses)
    (unless (null? clauses)
      (do
        (when (%clause-extra? (first clauses))
          (%warn! "match-multi" (%clause-name (first (first clauses)))))
        (self (rest clauses))))))
  (%scan (rest form))
  (%lint-seq (rest form))))

(def %lint-quasi (fn (self form)
  (unless (null? form)
    (when (pair? form)
      (if (if (symbol? (first form)) (str=? (%cvt (first form) %string) "unquote") #f)
          (%lint-form (first (rest form)))
        (if (if (symbol? (first form)) (str=? (%cvt (first form) %string) "unquote-splicing") #f)
            (%lint-form (first (rest form)))
          (do (self (first form)) (self (rest form)))))))))

; --- Value-call dispatch ---
; (Subject selector args...) -- when the head resolves to a NON-callable
; value (a class or instance), the call routes through %class-call-handler
; and the second element is a MESSAGE NAME: data, never a variable
; reference.  Recording it as a use made every method spelling (`append`,
; `close`, ...) read "Undefined" in class-call-heavy code (the apps).
; Heads that are locals or unbound keep plain call analysis -- their values
; are unknown statically, so nothing can be assumed about element 2.
; --- def-class ---
; Class names def-class'd in the FILE: a value call through one
; dispatches its selector as a message name (x/type/class.x), so the
; subject test below must say yes even though the name is in scope.
; (doc TARGET meta...): a pair target is a real definition to walk; a
; bare-symbol target documents a REGISTRY name (doc-prims.x, str.x) --
; not a value reference, so it must not count as a use.

(def %lint-class-names (list ()))

; Sibling method names of the class currently being walked: instance
; methods call each other bare, and the calling convention also binds
; recur (self-reference) and the member/set-member! accessors.

; (method NAME (self params...) body...) -- a named fn, shifted one.
; The method NAME is a member, not a global: never recorded, so it can
; neither collide nor count as unused; selectors that call it ride the
; class-call skip.

         ; (name value "doc"): the value is code

; Collect a class body's method NAMES (through static and doc wrappers):
; they are bound as siblings inside every method of that class.


; Order independence: file-bottom loader code may call (Class ...) before
; the reversed-or-not walk reaches the def-class, so class NAMES register
; in a pre-pass (like %arity-collect).

(def %lint-value-subject? (fn (_ head)
  (match
    ((not (symbol? head)) #f)
    ; A class defined in this file IS in scope -- but a call through it
    ; dispatches the selector as a message, so it is a subject.
    ((%member-str? (%cvt head %string) (first %lint-class-names)) #t)
    ((%scope-has-name? (%cvt head %string) (first %lint-scope)) #f)
    (#t (guard (_ #f)
      (let ((v (eval! (%str->symbol (%cvt head %string)))))
        (match
          ((null? v) #f)
          ((procedure? v) #f)
          ((operative? v) #f)
          (#t #t))))))))

; (subject X ...) where the subject is a bound local (self, an instance,
; a named-let var) and X resolves nowhere: under value-call dispatch X
; is a message name, not a variable.  Narrow on purpose: a BOUND first
; argument (plain fn self-recursion passing a local) still records
; normally; only a name that would have been a guaranteed false
; 'undefined' is treated as a message.  The cost: a genuine typo in
; that exact position is not flagged -- statically undecidable under
; value-call dispatch, adjudicated toward zero false positives.
(def %lint-member-send? (fn (_ form)
  (match
    ((not (symbol? (first form))) #f)
    ((not (%scope-has-name? (%cvt (first form) %string) (first %lint-scope))) #f)
    ((not (pair? (rest form))) #f)
    ((not (symbol? (first (rest form)))) #f)
    ((%scope-has-name? (%cvt (first (rest form)) %string) (first %lint-scope)) #f)
    (#t (guard (_ #t)
      (do (eval! (%str->symbol (%cvt (first (rest form)) %string))) #f))))))

; Computed subject: ((self %d) keys ...) -- a pair-headed call whose
; second element is an unresolvable symbol is a value-call send; the
; head expression lints on its own, the message name is skipped.
; Dispatched from the non-symbol-head path of %lint-dispatch.

(def %lint-call (fn (_ form)
  (match
    ((if (%lint-value-subject? (first form))
       (symbol? (first (rest form))) #f)
      (do (%lint-form (first form))          ; the subject is a real use
          (%lint-seq (rest (rest form)))))   ; selector skipped, args walked
    ((%lint-member-send? form)
      (do (%lint-form (first form))          ; self is a real use (the param)
          (%lint-seq (rest (rest form)))))   ; member name skipped, args walked
    (#t (%lint-seq form)))))

; (method-ref Target sel) -- Target is evaluated, sel is a MESSAGE NAME
; (x/type/class.x): walk the subject, skip the selector.
(def %lint-method-ref (fn (_ form)
  (%lint-form (first (rest form)))
  (%lint-seq (rest (rest (rest form))))))

; --- Default hook implementations (tools/dev/lint.x overrides these) ---

(set! %lint-binds? (fn (_ form)
  (when (and (pair? form) (symbol? (first form)))
    (str=? (%cvt (first form) %string) "def"))))

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
        ((str=? h "match") (%lint-match form))
        ((str=? h "first") (%lint-first-rest form))
        ((str=? h "rest")  (%lint-first-rest form))
        ((str=? h "method-ref") (%lint-method-ref form))
        (#t                (%lint-call form)))))))

; --- Arity + non-callable checks ---
;
; x-lang fn calls are lenient: missing args bind to nil, extra are ignored, so
; a wrong-arity call never errors -- only the linter catches it.  We collect
; arities of file-local named fns in a pre-pass and flag mismatching calls.  A
; fn's first param is the implicit self, so callable arity = (proper params) -
; 1; an improper tail (. rest) means variadic (a minimum only).

(def %lint-arity (list ()))   ; alist: (name . (min . variadic?))


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
  (when (if (pair? val) (symbol? (first val)) #f)
    (when (if (str=? (%cvt (first val) %string) "fn") (symbol? name) #f)
      (%set-first! %lint-arity
        (pair (pair (%cvt name %string) (%fn-arity val)) (first %lint-arity)))))))

; Pre-pass over top-level (def NAME (fn ..)) / (set! NAME (fn ..)).
(def %arity-collect (fn (self forms)
  (when (pair? forms)
    (do (let ((f (%lint-unwrap-doc (first forms))))
          (when (if (pair? f) (symbol? (first f)) #f)
            (when (if (str=? (%cvt (first f) %string) "def") #t
                  (str=? (%cvt (first f) %string) "set!"))
              (%arity-record (first (rest f)) (first (rest (rest f)))))))
        (self (rest forms))))))

(def %lint-check-arity (fn (_ form)
  (let ((h (first %lint-head-cell)))
    (unless (null? h)
      (let ((entry (%assoc-str h (first %lint-arity))))
        (unless (null? entry)
          (let ((nargs (- (%length form) 1))
                (mn (first (rest entry)))
                (vararg (rest (rest entry))))
            (when (if vararg (< nargs mn) (not (= nargs mn)))
              (%warn! "arity" h)))))))))

; A code form whose head is a '... form calls a non-function (it
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
  (let ((h (first %lint-head-cell)))
    (unless (null? h)
      (let ((mn (%lint-min-len h)))
        (when (if (= mn 0) #f (< (%length form) mn))
          (%warn! "malformed" h)))))))

; --- The write handlers ---

; SYMBOL: record its NAME unless bound or already seen.
(def %lint-symbol-handler (fn (_ sym)
  (let ((name (%cvt sym %string)))
    ; A #/.../ spelling is a reader-macro literal (regex), not a variable
    ; reference -- the linter reads the file as data, so the macro never
    ; ran.  Two byte compares (#344): the (Str8 starts? ...) spelling
    ; cost ~6 dispatches and a substring per symbol occurrence.
    (unless (if (< (%str-byte-len name) 2) #f
              (if (eq? 35 (%char->integer (%str-byte-ref name 0)))
                  (eq? 47 (%char->integer (%str-byte-ref name 1))) #f))
      (unless (%scope-mark-used! name (first %lint-scope))   ; local ref -> mark its box used
        (unless (%member-str? name (first %lint-uses))
          (%set-first! %lint-uses (pair name (first %lint-uses)))))))
  ()))

; LIST: run the head/arity checks, then delegate to the (swappable) dispatch.
; Doing the checks here (not in %lint-dispatch) means both the lib's default
; dispatch and tools/dev/lint.x's construct-table override get them for free.
(def %lint-list-handler (fn (_ form)
  ; The head converts ONCE here (#344); every consumer below (and the
  ; driver's dispatch override) reads %lint-head-cell instead of
  ; re-running the conversion catalog.
  (%set-first! %lint-head-cell
    (if (symbol? (first form)) (guard (_ ()) (%cvt (first form) %string)) ()))
  (when (%lint-noncallable? (first form))
    (%warn! "call-nonfn" (guard (_ "?") (%cvt (first form) %string))))
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

; --- The Lint class: the cold analysis surface (#percent-globals) ---
; The pin.x treatment, applied to the class/doc/prepass analysers added
; with the lib-wide sweep: homed as %-statics so the file stays inside
; its shrinking %-globals budget.  The per-form walk core (scope ops,
; handlers, send rules) stays as %-defs on MEASURED hot-path grounds:
; it runs per node of every form of every swept file.
(def-class Lint ()
  (static
    (%lint-class-siblings (list ()) "Sibling method names of the class being walked")
    (%lint-embedder-known (list "%install-root" "%pin-file") "Embedder-contract names, announced before any file runs")
    (method %lint-out-verb? (self form)
      (match
        ((not (pair? form)) #f)
        ((not (symbol? (first form))) #f)
        (#t (let ((h (%cvt (first form) %string)))
              (match
                ((str=? h "display") #t)
                ((str=? h "newline") #t)
                ((str=? h "%stderr") #t)
                (#t #f))))))
    (method %env-known? (self name)
  (match
    ((%member-str? name (Lint %lint-embedder-known)) #t)
    (#t (guard (_ #f) (do (eval! (%str->symbol name)) #t)))))
    (method %lint-doc (self form)
  (match
    ((null? (rest form)) ())
    ((symbol? (first (rest form))) (%lint-seq (rest (rest form))))
    (#t (%lint-seq (rest form)))))
    (method %lint-class-methods (self clauses acc)
  (match
    ((null? clauses) acc)
    (#t (let ((c (first clauses)))
          (recur self (rest clauses)
            (match
              ((not (pair? c)) acc)
              ((eq? (first c) 'method) (pair (%cvt (first (rest c)) %string) acc))
              ((eq? (first c) 'static) (recur self (rest c) acc))
              ((if (eq? (first c) 'doc) (if (pair? (first (rest c))) (eq? (first (first (rest c))) 'method) #f) #f)
                (pair (%cvt (first (rest (first (rest c)))) %string) acc))
              (#t acc)))))))
    (method %lint-class-clause (self c)
  (match
    ((not (pair? c)) ())                          ; bare symbol member: a declaration
    ((eq? (first c) 'method) (Lint %lint-method c))
    ((eq? (first c) 'static) (%for-each (fn (_ k) (recur self k)) (rest c)))
    ((eq? (first c) 'interface) ())               ; declared NAMES, not references
    ((eq? (first c) 'doc) ())                     ; class-level doc: prose + DSL
    (#t (%lint-form (first (rest c))))))
    (method %lint-method (self form)
  (def saved (first %lint-scope))
  ; The calling convention binds recur (the method's own self-reference),
  ; the member/set-member! instance accessors, and the class's sibling
  ; method names (instance methods call each other bare).
  (%scope-add! "recur")
  (%scope-add! "member")
  (%scope-add! "set-member!")
  (%for-each (fn (_ n) (%scope-add! n)) (first (Lint %lint-class-siblings)))
  (%set-first! %lint-scope (%add-params (first (rest (rest form))) (first %lint-scope)))
  (%lint-seq (rest (rest (rest form))))
  (%lint-leak-scan (%last (rest (rest (rest form)))))
  (%set-first! %lint-scope saved))
    (method %lint-class (self form)
  (def name-str (%cvt (first (rest form)) %string))
  (%scope-add! name-str)
  (%set-first! %lint-class-names (pair name-str (first %lint-class-names)))
  ; def-record has NO parents slot -- (def-record NAME field...) -- so its
  ; whole tail is member declarations; def-class's third element is the
  ; parents form, (Parent ...) or (extends Proto ...): the extends KEYWORD
  ; is not a reference, everything else is.
  (def body
    (if (eq? (first form) 'def-record)
      (rest (rest form))
      (do
        (let ((parents (first (rest (rest form)))))
          (match
            ((if (pair? parents) (eq? (first parents) 'extends) #f) (%lint-seq (rest parents)))
            (#t (%for-each (fn (_ p) (%lint-form p)) parents))))
        (rest (rest (rest form))))))
  (let ((saved-sibs (first (Lint %lint-class-siblings))))
    (%set-first! (Lint %lint-class-siblings)
      (Lint %lint-class-methods body ()))
    (%for-each (fn (_ c) (Lint %lint-class-clause c)) body)
    (%set-first! (Lint %lint-class-siblings) saved-sibs)))
    (method %lint-class-prepass (self forms)
  (unless (null? forms)
    (do (let ((f (%lint-unwrap-doc (first forms))))
          (when (if (pair? f)
                  (if (eq? (first f) 'def-class) #t (eq? (first f) 'def-record))
                  #f)
            (%set-first! %lint-class-names
              (pair (%cvt (first (rest f)) %string) (first %lint-class-names)))))
        (recur self (rest forms)))))
    (method %lint-computed-call (self form)
  (match
    ((if (pair? (rest form))
       (if (symbol? (first (rest form)))
         (if (%scope-has-name? (%cvt (first (rest form)) %string) (first %lint-scope)) #f
           (guard (_ #t)
             (do (eval! (%str->symbol (%cvt (first (rest form)) %string))) #f)))
         #f) #f)
      (do (%lint-form (first form))
          (%lint-seq (rest (rest form)))))
    (#t (%lint-seq form))))))

(def %lint-top (fn (self forms defs)
  (if (null? forms) defs
    ; `let`, not `def`: this is %lint-top's tail, so a `def` here would itself
    ; leak (the very bug we detect).  We dogfood the fix.
    (let ((form (first forms)))
      (let ((eff (%lint-unwrap-doc form)))             ; see through (doc (def ..) ..)
        (let ((nm (when (%lint-binds? eff) (%lint-bound-name eff))))
          (when (if (null? nm) #f (%member-str? nm defs))
            (%warn! "dup-def" nm))                  ; same top-level name defined twice
          (%set-first! %lint-scope ())
          (%write-to-str form)                         ; drive the walk (string discarded)
          (self (rest forms) (if (null? nm) defs (pair nm defs)))))))))

(doc (def lint-forms (fn (_ forms defs uses)
  (%set-first! %lint-uses uses)
  (%set-first! %lint-issues ())
  (%set-first! %lint-leaks ())
  (%set-first! %lint-warn ())
  (%set-first! %lint-arity ())
  (%set-first! %lint-scope ())
  (%set-first! %lint-class-names ())
  (%set-first! (Lint %lint-class-siblings) ())
  (%arity-collect forms)                             ; pre-pass: file-local fn arities
  (Lint %lint-class-prepass forms)                        ; pre-pass: class names (order independence)
  (%lint-push)
  (def result-defs (%lint-top forms defs))
  (%lint-pop)
  (list result-defs (first %lint-uses) (first %lint-issues)
        (first %lint-leaks) (first %lint-warn))))
  (param forms LIST "List of top-level forms to analyze")
  (param defs LIST "Accumulator for defined symbol NAMES")
  (param uses LIST "Accumulator for used symbol NAMES")
  (returns LIST "(defs uses issues leaks warnings) -- defs/uses/issues/leaks are NAME STRINGS; warnings are (kind . name) pairs for arity / call-nonfn / dup-def / malformed / match-multi / shadow / unused")
  "Walk top-level forms via the write stacks, collecting def/use names, first/rest issues, tail-position def leaks, and pedantic warnings (arity, non-callable calls, duplicate defs, malformed forms, lexical shadows, and unused locals).")

(doc (def lint-undefined (fn (_ defs uses)
  (%filter (fn (_ name)
    (unless (%member-str? name defs)
      (unless (Lint %env-known? name) #t)))
    uses)))
  (param defs LIST "Defined names from lint-forms")
  (param uses LIST "Used names from lint-forms")
  (returns LIST "Names used but not defined")
  "Compute undefined names: used but not in env or file defs.")

(doc (def lint-unused (fn (_ defs uses lib-mode)
  (unless lib-mode
    (%filter (fn (_ name)
      (unless (Str starts? "%" name)
        (unless (%member-str? name uses) #t)))
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
  (%map (fn (_ w) (rest w))
    (%filter (fn (_ w) (str=? (first w) kind)) (lint-warnings result)))))
  (param kind STRING "Warning kind: arity | call-nonfn | dup-def | malformed | match-multi | shadow | unused")
  (param result LIST "Result of lint-forms")
  (returns LIST "The names for warnings of that kind")
  "Filter pedantic warnings to one kind, returning their names.")

(doc (def lint-has? (fn (_ name names) (%member-str? name names)))
  (param name STRING "A symbol name")
  (param names LIST "A list of names (e.g. from lint-undefined)")
  (returns BOOL "#t if name is in names")
  "Test whether a name string is in a names list (string equality).")

(doc (provide x/tool/lint
  lint-forms lint-undefined lint-unused lint-first-rest lint-leaks
  lint-warnings lint-warnings-of lint-has?)
  "AST linter via the type-system write stacks: name-based def/use analysis + first/rest + tail-def-leak + pedantic (arity / non-callable / duplicate-def) checks.")
