; object.x -- Object-oriented class system (message passing, single inheritance)
(import x/core/alist)
; Fetch the string prims from the catalog (ns `str` is de-registered, R5).
(def %str-append (prim-ref (lit str) (lit append)))
(def %str->symbol (prim-ref (lit str) (lit ->sym)))
; Fetch the type prims from the catalog (ns `type` is de-registered, R5).
(def %make-type (prim-ref (lit type) (lit make)))
(def %make-instance (prim-ref (lit type) (lit make-instance)))
(def %type? (prim-ref (lit type) (lit ?)))
(def %type-by-atom (prim-ref (lit type) (lit by-atom)))
(def %type-call-top (prim-ref (lit type) (lit call-top)))
(def %type-push-call (prim-ref (lit type) (lit push-call)))


;
; CLASSES ARE OBJECTS. A class is a callable %class object; an instance is a
; callable %object. Dispatch mirrors one level up:
;
;            (obj name ...)                 (Class name ...)
;   method   instance method (from class)   static method
;   member   instance member get/set        class-wide member get/set
;   self     the instance                   the class
;
; A class's data is an alist:
;   ((name . N) (fields . MEM) (methods . IM) (parent . P)
;    (s-methods . SM) (statics . STATICS-BOX))
; -- the `fields` key holds the instance members as a (name . default-value) alist;
; IM the instance methods; SM the static methods; STATICS-BOX a one-cell mutable box
; holding the class-wide (static) member alist. An instance's slot 0 holds
; (class . field-box); the field-box is a one-cell mutable (name . value) alist.
;
; Selectors are literal -- both dispatch handlers are OPERATIVES, so (obj name)
; needs no quote, while args evaluate in the caller's env.

(note "Accessors (internal plumbing)")

(def %obj-class  (fn (_ inst) (first (first inst))))   ; an instance's class object
(def %obj-box    (fn (_ inst) (rest  (first inst))))   ; instance field box
(def %obj-fields (fn (_ inst) (first (%obj-box inst))))
(def %class-data (fn (_ c) (first c)))                 ; a class object's alist

; Raw field accessors injected into every instance-method body (closing over
; `self`), so a method can bypass a same-named override to reach a field's
; storage -- the "private data" pattern. Method-local only.
;   (member 'name) / (set-member! 'name v)
(def %method-raw-bindings
  (lit
    ((member     (fn (_ n) (assoc-get n (%obj-fields self))))
     (set-member! (fn (_ n v)
                   (set-first! (%obj-box self) (assoc-put n v (%obj-fields self)))
                   v)))))

(note "Member lookup (walks the single-inheritance parent chain)")

; Look `selector` up in table `key` (methods | s-methods) along the class chain.
(def %lookup
  (fn (loop class key selector)
    (if (null? class)
      ()
      (let ((data (%class-data class)))
        (let ((hit (assoc-get selector (assoc-get key data))))
          (if (null? hit)
            (loop (assoc-get (lit parent) data) key selector)
            hit))))))

; Unwrap a quoted 'x (i.e. (lit x)) to the bare symbol x, so (obj x) and (obj 'x)
; both name the member x.
(def %selector
  (fn (_ s)
    (if (if (pair? s) (eq? (first s) (lit lit)) #f)
      (first (rest s))
      s)))

; Build an instance: instance fields (across the chain) initialised from inits.
; eval? selects how supplied values are treated (see %init-fields): #t = code
; evaluated in e (the new ops), #f = data used as-is (new-from).
(def %instantiate
  (fn (_ class inits e eval?)
    (%make-instance %object
      (list class (%init-fields (%all-fields class) inits e eval?)))))

(note "Dispatch handlers")

; Instance dispatch: a method (from the instance's class) wins; otherwise the
; member is an instance field that (obj f) reads and (obj f v) writes.
(def %object-dispatch
  (op (self sel-raw . rest) e
    (let ((selector (%selector sel-raw)))
      (let ((method (%lookup (%obj-class self) (lit methods) selector)))
        (match
          ((not (null? method))
            (apply method (pair self (%map1 (fn (_ a) (eval a e)) rest))))
          ((assoc-has? selector (%obj-fields self))
            (match
              ((null? rest) (assoc-get selector (%obj-fields self)))
              (#t (let ((v (eval (first rest) e)))
                    (set-first! (%obj-box self) (assoc-put selector v (%obj-fields self)))
                    v))))
          (#t (error "object: no such member")))))))

(def %class-statics-box (fn (_ class) (assoc-get (lit statics) (%class-data class))))
(def %class-statics     (fn (_ class) (first (%class-statics-box class))))

; Class dispatch: a static method wins; (Class new ...) builds an instance;
; otherwise the member is a class-wide field that (Class f) reads, (Class f v) sets.
(def %class-dispatch
  (op (self sel-raw . rest) e
    (let ((selector (%selector sel-raw)))
      (let ((method (%lookup self (lit s-methods) selector)))
        (match
          ((not (null? method))
            (apply method (pair self (%map1 (fn (_ a) (eval a e)) rest))))
          ((eq? selector (lit new))                       ; (Class new k v ...): values are code
            (%instantiate self rest e #t))
          ((assoc-has? selector (%class-statics self))
            (match
              ((null? rest) (assoc-get selector (%class-statics self)))
              (#t (let ((v (eval (first rest) e)))
                    (set-first! (%class-statics-box self) (assoc-put selector v (%class-statics self)))
                    v))))
          (#t (error "object: no such static member")))))))

; --- Value-to-class call dispatch ---
; Build a TYPE call handler so an instance, called as (inst method . args),
; dispatches to a bound CLASS's static method with the instance as the LAST
; positional argument -- the SUBJECT-LAST convention that matches the library's
; Ramda-style data-last methods. So (1/2 numerator) -> (Rational numerator 1/2),
; ("a,b,c" split ",") -> (Str8 split "," "a,b,c"), (lst map f) -> (List map f
; lst). Commutative ops read naturally ((1/2 + 1/3) -> (Rational + 1/3 1/2) ->
; 5/6); non-commutative ones are subject-last too (use the prefix (- a b) form).
; Install via type-push-call: (%type-push-call (%type-by-atom %rational)
; (%class-call-handler Rational)). An `op` (not fn) so the method selector stays
; unevaluated while the remaining args evaluate in the caller's env.
(def %class-call-handler
  (fn (_ class)
    (op (obj . args) e
      ; A method call has a SYMBOL selector as its first arg ((1/2 numerator)).
      ; Anything else is a data list whose head happens to be a value of this
      ; type, re-evaluated as a call -- (1/2 1/3), or a bare (1) -- where dispatch
      ; must NOT fire; reproduce the data form so the list passes through
      ; unchanged, exactly as a non-callable head would. (x_prim_iter
      ; re-evaluates the list it iterates, which is why this path exists.)
      (if (null? args)
        (list obj)
        (let ((sel (%selector (first args))))
          (if (symbol? sel)
            (let ((m (%lookup class (lit s-methods) sel)))
              (if (null? m)
                (error (%str-append "object: no such method " (symbol->str sel)))
                (apply m (pair class (append (%map1 (fn (_ a) (eval a e)) (rest args)) (list obj))))))
            (pair obj (%map1 (fn (_ a) (eval a e)) args))))))))

; Variant for types that ALREADY have a call handler (indexing/matching): a
; SYMBOL selector dispatches to the class method (subject-LAST, as above);
; anything else DELEGATES to the PRIOR handler (captured at install), so the
; existing call form keeps working. So a string gets both ("hi" split ",")
; (method) and ("hi" 0) (code point); a vector both (v ->list) and (v 0).
; Install with %bind-call-over! (below), which captures the current top handler
; before pushing this one.
(def %class-call-handler-over
  (fn (_ class prior)
    (op (obj . args) e
      (if (null? args)
        (apply prior (list obj))
        (let ((sel (%selector (first args))))
          (if (symbol? sel)
            (let ((m (%lookup class (lit s-methods) sel)))
              (if (null? m)
                (error (%str-append "object: no such method " (symbol->str sel)))
                (apply m (pair class (append (%map1 (fn (_ a) (eval a e)) (rest args)) (list obj))))))
            (apply prior (pair obj (%map1 (fn (_ a) (eval a e)) args)))))))))

; Install value-to-class method dispatch OVER a type's existing call handler:
; symbol selector -> the class's static method (subject-last); anything else
; falls through to whatever the type's call slot did before.
(def %bind-call-over!
  (fn (_ type-handle class)
    (let ((ts (%type-by-atom type-handle)))
      (%type-push-call ts (%class-call-handler-over class (%type-call-top ts))))))

(note "Write handlers")

(def %write-fields
  (fn (loop al)
    (if (not (null? al))
      (do
        (display " ")
        (display (first (first al)))
        (display "=")
        (write (rest (first al)))
        (loop (rest al))))))

; An object's write op is not a standalone global -- it lives ON the type
; (below) and asks the INSTANCE to render itself: a class that defines a `repr`
; method (returning a string) controls its own printing; otherwise the type's
; default #<Class field=val ...> dump. (display falls back to write for objects,
; so `repr` governs both.) This is the type / class / instance triad, no global
; write function. %write-fields above is the default dump's shared field walker.

(def %class-write
  (fn (_ self)
    (display "#<class ")
    (display (class-name self))
    (display ">")))

(def %object
  (%make-type "OBJECT"
    (list
      (pair (lit call) %object-dispatch)
      (pair (lit write)
        (fn (_ self)
          (if (null? (%lookup (%obj-class self) (lit methods) (lit repr)))
            (do
              (display "#<")
              (display (class-name self))
              (%write-fields (%obj-fields self))
              (display ">"))
            (display (self repr))))))))
(def %class  (%make-type "CLASS"  (list (pair (lit call) %class-dispatch)  (pair (lit write) %class-write))))

(note "Inheritance")

(doc (def super
  (op (self-expr sel-raw . rest) e
    (let ((inst (eval self-expr e)) (selector (%selector sel-raw)))
      (if (not (object? inst))
        (error "object: super works only inside an instance method")
        ; %super-class is the parent of the class that DEFINED this method (bound by
        ; def-class in the method's scope), so super resolves to the right level even
        ; when the method is inherited by a deeper subclass -- no self-recursion.
        (let ((method (%lookup (eval (lit %super-class) e) (lit methods) selector)))
          (if (null? method)
            (error "object: super has no parent method")
            (apply method (pair inst (%map1 (fn (_ a) (eval a e)) rest)))))))))
  (note "Selector is literal: (super self method args...). Instance methods only.")
  (note "Resolves from the parent of the method's DEFINING class, so it is correct")
  (note "through multi-level inheritance.")
  (example "(super self total)" "the parent total method's result")
  (see def-class)
  "Invoke the parent class's version of a method.")

; method-ref: turn a method into a first-class function value -- the complement
; of a bare (Target sel ...) call. (method-ref Target sel) evaluates Target (a
; class or instance) and the literal selector sel, and returns a closure that,
; when applied, re-drives the normal dispatch: (Target sel . args). It does NOT
; introspect the method tables -- it just defers the call -- so it works for
; static methods, instance methods, and members uniformly, with any arity.
;   (map (method-ref Str upcase) lst)
;   (regex-replace rx s (method-ref Str upcase))
; Each captured value (target, selector, and every applied arg) is spliced as a
; (lit V) literal so the rebuilt call dispatches on the values, not re-evaluation.
(doc (def method-ref
  (op (target-expr sel) e
    (let ((target (eval target-expr e)))
      (fn (_ . args)
        (eval
          (pair (list (lit lit) target)
            (pair (list (lit lit) sel)
              (%map1 (fn (_ a) (list (lit lit) a)) args)))
          e)))))
  (note "Selector is literal: (method-ref Class method). Works for static and instance methods.")
  (example "(map (method-ref Str upcase) (list \"a\" \"b\"))" "(\"A\" \"B\")")
  (see def-class)
  "Make a class/instance method usable as a first-class function value.")

(note "Predicates and introspection")

(doc (def object? (fn (_ (param x ANY "Value to test")) (%type? x %object)))
  (returns BOOL "True if x is an object instance")
  (see class?)
  "Test whether a value is an object instance.")

(doc (def class? (fn (_ (param x ANY "Value to test")) (%type? x %class)))
  (returns BOOL "True if x is a class")
  (see object?)
  "Test whether a value is a class.")

(doc (def class-of
  (fn (_ (param inst OBJECT "Instance"))
    (if (object? inst) (%obj-class inst) (error "class-of: not an instance"))))
  (returns CLASS "The class an instance belongs to")
  (see class-name)
  "Return the class an instance belongs to (itself a callable class object).")

(doc (def class-name
  (fn (_ (param x ANY "An instance or a class"))
    (assoc-get (lit name) (%class-data (if (class? x) x (%obj-class x))))))
  (returns SYMBOL "The class name")
  (see class-of)
  "Return the name symbol of a class, or of an instance's class.")

(doc (def class-parent
  (fn (_ (param c CLASS "A class"))
    (assoc-get (lit parent) (%class-data c))))
  (returns CLASS "The parent class, or nil for a root class")
  (see class-name)
  "Return a class's parent class (the one it extends), or nil if it has none.")

(def %class-ancestor?
  (fn (loop c target)
    (if (null? c)
      #f
      (if (same? c target)                 ; class identity, not value equality
        #t
        (loop (assoc-get (lit parent) (%class-data c)) target)))))

(doc (def instance-of?
  (fn (_ (param inst OBJECT "Instance") (param class CLASS "Class"))
    (%class-ancestor? (%obj-class inst) class)))
  (returns BOOL "True if inst is a class or one of its subclasses")
  (see object?)
  "Test whether an instance belongs to a class or any of its descendants.")

(note "Introspection -- member/method names (own, not inherited), used by help")

(doc (def class-members
  (fn (_ (param c CLASS "A class")) (assoc-keys (assoc-get (lit fields) (%class-data c)))))
  (returns LIST "This class's own instance-member names")
  (see class-methods)
  "List a class's own instance member names (not inherited).")

(doc (def class-methods
  (fn (_ (param c CLASS "A class")) (assoc-keys (assoc-get (lit methods) (%class-data c)))))
  (returns LIST "This class's own instance-method names")
  (see class-members)
  "List a class's own instance method names (not inherited).")

(doc (def class-static-members
  (fn (_ (param c CLASS "A class")) (assoc-keys (%class-statics c))))
  (returns LIST "This class's own static-member names")
  (see class-static-methods)
  "List a class's own static (class-wide) member names (not inherited).")

(doc (def class-static-methods
  (fn (_ (param c CLASS "A class")) (assoc-keys (assoc-get (lit s-methods) (%class-data c)))))
  (returns LIST "This class's own static-method names")
  (see class-static-members)
  "List a class's own static method names (not inherited).")

(note "Class definition")

(def %make-class
  (fn (_ name fields methods parent s-methods statics)
    (%make-instance %class
      (list
        (pair (lit name) name)
        (pair (lit fields) fields)
        (pair (lit methods) methods)
        (pair (lit parent) parent)
        (pair (lit s-methods) s-methods)
        (pair (lit statics) (list statics))))))   ; statics in a one-cell mutable box

; Find a top-level body form whose head is `tag`, returning its rest (or ()).
(def %find-form
  (fn (loop body tag)
    (if (null? body)
      ()
      (if (eq? (first (first body)) tag)
        (rest (first body))
        (loop (rest body) tag)))))

; --- Method documentation ---
; A method may carry an optional leading (doc "desc" (param ...) (returns ...)
; (example ...) ...) as its FIRST body form, and annotate its parameters inline:
;   (method upcase (self (param s STRING "the string"))
;     (doc "Uppercase ASCII" (returns STRING "uppercased"))
;     BODY...)
; The doc is registered under the symbol  Class/method  (e.g. Str8/upcase) so
; (help Class method) finds it. The (doc ...) form and inline (param ...) are
; stripped before the method closure is built. We stash a %bare pending entry
; on the shared doc pipeline (same path the top-level `doc` op uses), so it
; rides the normal lazy %doc-commit! -- no new registry machinery.

; #t if the first body form is a (doc ...) clause.
(def %method-has-doc?
  (fn (_ form)
    (let ((body (rest (rest (rest form)))))
      (if (null? body) #f
        (if (pair? (first body)) (eq? (first (first body)) (lit doc)) #f)))))

; Compose the doc key symbol: Class/method.
(def %method-doc-key
  (fn (_ class-name method-name)
    (%str->symbol (%str-append (symbol->str class-name)
                   (%str-append "/" (symbol->str method-name))))))

; Stash a method's (doc "desc" meta...) as a %bare pending entry. The doc clause
; is (doc DESC META...); DESC may be absent. Inline (param ...) forms from the
; signature are appended to the meta so help shows the parameters too.
(def %stash-method-doc!
  (fn (_ class-name form)
    (let ((mname (first (rest form)))
          (sig   (first (rest (rest form))))
          (dform (first (rest (rest (rest form))))))   ; (doc DESC meta...)
      (let ((dargs (rest dform)))
        ; description = leading string (or ""); meta = the rest + inline params
        (let ((desc (if (null? dargs) ""
                      (if (str? (first dargs)) (first dargs) "")))
              (meta (if (null? dargs) ()
                      (if (str? (first dargs)) (rest dargs) dargs))))
          (set-first! %doc-pending-cell
            (pair (pair (lit %bare)
                     (pair (%method-doc-key class-name mname)
                           (pair desc (%append2 meta (%sig-params sig)))))
                  (first %doc-pending-cell))))))))

; Stash a member's description as a %bare pending doc entry, keyed Class/NAME
; (same namespace as methods; a same-named method shadows it, matching dispatch).
(def %stash-member-doc!
  (fn (_ class-name member-name desc)
    (set-first! %doc-pending-cell
      (pair (pair (lit %bare)
               (pair (%method-doc-key class-name member-name)
                     (pair desc ())))
            (first %doc-pending-cell)))))

; Extract the inline (param ...) forms from a method signature (self . params).
; A variadic tail is written dotted -- (self . (param args ...)) or
; (self k . (param rest ...)) -- so the (param ...) form can arrive as `sig`
; itself (the improper tail), not only as a list element; collect it either way.
(def %sig-params
  (fn (loop sig)
    (if (null? sig) ()
      (if (pair? sig)
        (if (eq? (first sig) (lit param))
          (list sig)                                   ; dotted (param ...) tail
          (if (if (pair? (first sig)) (eq? (first (first sig)) (lit param)) #f)
            (pair (first sig) (loop (rest sig)))
            (loop (rest sig))))
        ()))))

; Strip inline (param name TYPE "desc") annotations from a signature, leaving
; the bare parameter names the fn closure needs.
(def %strip-sig-params
  (fn (loop sig)
    (if (null? sig) ()
      (if (pair? sig)
        ; A dotted (param ...) tail arrives as `sig` itself (e.g. the rest in
        ; (self . (param args ...))); strip it to its NAME as the improper tail
        ; so the fn keeps its variadic arg, rather than splicing param/TYPE/desc
        ; in as extra fixed parameters.
        (if (eq? (first sig) (lit param))
          (first (rest sig))              ; dotted (param NAME ...) tail -> NAME
          (pair
            (if (if (pair? (first sig)) (eq? (first (first sig)) (lit param)) #f)
              (first (rest (first sig)))    ; (param NAME ...) -> NAME
              (first sig))
            (loop (rest sig))))
        sig))))   ; dotted-rest tail passes through

; Build a method closure from (NAME (self . params) body...). The body is wrapped
; in a let binding %super-class (the parent of the defining class, used by super)
; and, for instance methods (raw? true), the raw member/set-member! accessors.
; A leading (doc ...) body form and inline (param ...) signature annotations are
; stripped here (their registration happens in %collect-methods).
(def %make-method
  (fn (_ form raw? parent e)
    (let ((sig  (%strip-sig-params (first (rest (rest form)))))
          (body (if (%method-has-doc? form)
                  (rest (rest (rest (rest form))))     ; drop leading (doc ...)
                  (rest (rest (rest form))))))
      (eval
        (list (lit fn)
          (pair (lit recur) sig)                       ; (recur . user-params)
          (pair (lit let)
            (pair (pair (list (lit %super-class) parent)
                    (if raw? %method-raw-bindings ()))
                  body)))
        e))))

; Collect the (method ...) forms in `forms` into a methods alist. raw? injects the
; raw accessors (instance methods); parent is the defining class's parent (for
; super). class-name keys any per-method docs. Registers a doc entry for each
; documented method as a side effect.
(def %collect-methods
  (fn (loop class-name forms raw? parent e)
    (if (null? forms)
      ()
      (if (eq? (first (first forms)) (lit method))
        (do
          (if (%method-has-doc? (first forms))
            (%stash-method-doc! class-name (first forms))
            ())
          (pair (pair (first (rest (first forms)))
                      (%make-method (first forms) raw? parent e))
                (loop class-name (rest forms) raw? parent e)))
        (loop class-name (rest forms) raw? parent e)))))

; A member declaration is  NAME  |  (NAME value)  |  (NAME value "desc").
(def %member-name (fn (_ form) (if (pair? form) (first form) form)))
(def %member-value
  (fn (_ form e)
    (if (if (pair? form) (not (null? (rest form))) #f)
      (eval (first (rest form)) e)
      ())))                                          ; bare name / (NAME) -> nil default
(def %member-has-desc?
  (fn (_ form)
    (if (pair? form)
      (if (not (null? (rest form))) (not (null? (rest (rest form)))) #f)
      #f)))
(def %member-desc (fn (_ form) (first (rest (rest form)))))

; Collect member declarations from `forms` into a (name . value) alist, skipping
; (method ...) and (static ...) forms. A trailing description string registers a
; doc entry under Class/NAME (the same namespace as methods).
(def %collect-members
  (fn (loop class-name forms e)
    (if (null? forms)
      ()
      (let ((f (first forms)))
        (if (if (pair? f)
              (if (eq? (first f) (lit method)) #t (eq? (first f) (lit static)))
              #f)
          (loop class-name (rest forms) e)           ; skip methods + the static block
          (do
            (if (%member-has-desc? f)
              (%stash-member-doc! class-name (%member-name f) (%member-desc f))
              ())
            (pair (pair (%member-name f) (%member-value f e))
                  (loop class-name (rest forms) e))))))))

(def %resolve-parent
  (fn (_ parent e)
    (if (null? parent)
      ()
      (eval (first (rest parent)) e))))

; A body form is a member NAME (symbol), or a list headed by a symbol --
; (method ...), (static ...), or a (NAME value ...) member declaration.
(def %valid-head?
  (fn (_ form)
    (if (symbol? form) #t
      (if (pair? form) (symbol? (first form)) #f))))

(def %validate-body
  (fn (loop body)
    (if (null? body)
      ()
      (do
        (let ((f (first body)))
          (if (if (pair? f) (eq? (first f) (lit fields)) #f)
            (error "def-class: the (fields ...) wrapper was removed -- declare members directly, e.g. (def-class C () x y (method m (self) ...))")
            (if (%valid-head? f)
              ()
              (error "def-class: invalid body form -- expected a member name, (name value), (method ...), or (static ...)"))))
        (loop (rest body))))))

; Resolve the parent once, validate the body, and build the class object. Kept out
; of the def-class op body so the op's tail stays the bare tail-eval (see below).
(def %build-class
  (fn (_ name parent body e)
    (do
      (%validate-body body)
      (let ((p (%resolve-parent parent e))
            (sblock (%find-form body (lit static))))
        (%make-class
          name
          (%collect-members name body e)             ; instance members (skips methods + static)
          (%collect-methods name body #t p e)        ; instance methods: raw access + super
          p
          (%collect-methods name sblock #f p e)      ; static methods
          (%collect-members name sblock e))))))      ; static members

(doc (def def-class
  (op (name parent . body)
    e
    ; tail-eval must be the op's direct tail so the (def NAME ...) it runs persists
    ; in the caller's env even under (eval form env) (e.g. the spec harness), not
    ; only the REPL's eval!. %build-class does the work (validate, resolve, build).
    (tail-eval
      (list (lit def) name (list (lit lit) (%build-class name parent body e)))
      e)))
  (note "Names are literal (no quotes). Body forms (members and methods intermixed):")
  (note "  NAME | (NAME val) | (NAME val \"desc\")    instance member (val is its default)")
  (note "  (method NAME (self . args) body...)      instance method")
  (note "  (static MEMBER... (method ...)...)       class-wide members + static methods")
  (note "A method shadows a member of the same name. Parent: () or (extends Class).")
  (note "Inside a method, (self m) accesses members; (member 'm)/(set-member! 'm v) are raw.")
  (example "(do (def-class C () (static (n 7) (method get (self) (self n)))) (C get))" "7")
  (see new)
  "Define a class (a callable class object) with fields, methods, and statics.")

(doc (def new
  (op (class-expr . inits)
    e
    (%instantiate (eval class-expr e) inits e #t)))
  (note "Inline construction: member names are literal (bare, not quoted) and")
  (note "values are expressions, evaluated in the caller's env:")
  (note "  (new C name val name val ...)   plist form -- the usual one")
  (note "  (new C (name . val) ...)        dotted-alist form (val is an expression)")
  (note "For a computed/quoted store (a list of ready values) use new-from.")
  (example "(do (def-class P () x) ((new P x 5) x))" "5")
  (see new-from)
  "Construct an instance inline; names literal, values evaluated.")

(doc (def new-from
  (fn (_ (param class CLASS "The class to instantiate")
       (param store LIST "Ready-value store: alist ((k . v) ...) or plist (k v ...)"))
    (%instantiate class store () #f)))
  (note "Data counterpart to new: the store is evaluated (new-from is a fn) and its")
  (note "values are used as-is, not re-evaluated -- so pass a quoted list, a variable,")
  (note "or a built alist/plist.  Unknown keys fall back to declared defaults.")
  (example "(do (def-class P () x y) ((new-from P (lit (x 1 y 2))) x))" "1")
  (see new)
  "Instantiate a class from a computed option store (alist or plist) of values.")

; Reject entries from alist `al` whose name is already a key in `known`.
(def %reject-known
  (fn (loop al known)
    (if (null? al)
      ()
      (if (assoc-has? (first (first al)) known)
        (loop (rest al) known)
        (pair (first al) (loop (rest al) known))))))

; All instance members across the inheritance chain as a (name . default) alist;
; a member redefined in a subclass overrides the inherited one (child wins).
(def %all-fields
  (fn (loop class)
    (if (null? class)
      ()
      (let ((own (assoc-get (lit fields) (%class-data class))))
        (%append2 own
          (%reject-known (loop (assoc-get (lit parent) (%class-data class))) own))))))

; Build the instance field box: each member takes its init value if supplied --
; from a flat plist `name val ...` OR an alist `((name . val) ...)` -- otherwise
; its declared default.  eval? selects how a supplied value is treated: #t (the
; (new ...) ops, whose values are code) evaluates it in caller env e; #f (new-from,
; whose store is data) uses it as-is.  An absent key (%opt-cell returns ()) falls
; back to the declared default, already a value; null? on the box distinguishes a
; supplied 0/nil from a missing key.
(def %init-fields
  (fn (loop members inits e eval?)
    (if (null? members)
      ()
      (let* ((name (first (first members)))
             (default (rest (first members)))
             (cell (%opt-cell name inits)))
        (pair (pair name
                (if (null? cell) default
                  (if eval? (eval (first cell) e) (first cell))))
              (loop (rest members) inits e eval?))))))

(doc (provide x/type/object
  def-class new new-from super method-ref
  object? class? class-of class-name class-parent instance-of?
  class-members class-methods class-static-members class-static-methods)
  (note "Instances: (obj name args...) -- method wins, else member (obj m)/(obj m v).")
  (note "Classes are callable: (Class name args...) -- static method, (Class new ...) to")
  (note "instantiate, else class-wide member (Class m)/(Class m v). Use classes as")
  (note "namespaces of static methods. Raw member access in methods: (member 'm)/(set-member! 'm v).")
  (example "(do (def-class P () x (method get (self) (self x))) ((new P x 5) get))" "5")
  "Object-oriented class system: classes-as-objects, message passing, single inheritance.")
