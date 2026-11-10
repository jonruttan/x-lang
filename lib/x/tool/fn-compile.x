; fn-compile.x -- a program's closure compiled where it stands
; lint-known: %isa-bare %isa-keep %isa-catalogue
;
; (compile-fn! NAME F) rewrites the closure F into the function world of
; compile-asm (lib/x/tool/asm-compile.x) and installs the compiled version
; into F itself through (Compiled in-place ...): every holder of F calls it,
; and the interpreted version stays on the list as the reference.  A body
; the rewrite cannot carry is refused with its reason, and F stays
; interpreted.
;
; What the rewrite carries:
;
;   integers   int+ int- int* int/ int% int& int| int<< int>> on raw words,
;              boxed only where a value leaves the arithmetic; int< and int=
;              as a branch in a test, #t or #f as a value
;   objects    first rest pair eq? null? not obj-ref obj-set!, and pair? and
;              symbol? as a read of the operand's type name
;   control    if when unless match do and or, def of a local, set! of a
;              local or a free name, let as fresh locals (not a named let),
;              guard outlined into closures the engine's guard runs
;   calls      a call of F itself (a jump in tail position), and a call of
;              any closure or any C primitive the engine's ISA manifest does
;              not label spine, with values; a send (C SEL ...) to a class's
;              public static method, as a call of the method method-of
;              resolves
;
; A free name is read through its binding cell, found by the engine's lookup
; when F is compiled ((Env cell ...)): a later set! or def of the name is
; seen, as interpreted code sees it.  A head is decided when F is compiled,
; by the value its name is bound to then: an integer door is compiled as the
; operation, a closure as a call, a class send as a call of the method it
; resolves to then.  Rebinding one of those names, or redefining that
; method, afterwards is not seen until F is compiled again.
;
; A call runs code that can collect, so an object the frame holds across a
; call must be in a cell (the function world, asm-compile.x).  The rewrite
; binds to a local every operand that holds a value while a later operand
; makes a call.

(module x/tool/fn-compile)
(import x/type/class)
(import x/type/env)
(import x/core/fn)
(import x/tool/compiled)
(import x/tool/asm-cache asm-compile-cached)
(import x/core/doors int+ int- int* int/ int% int< int= int& int| int<< int>>
  obj-ref obj-set! obj-same? io-display-to-str str->sym type-of)

; --- What a head means --------------------------------------------------------

; The integer doors that compile to one instruction on raw words.
(def %fc-raw-ops
  (list (pair int+ (lit +)) (pair int- (lit -)) (pair int* (lit *))
        (pair int/ (lit /)) (pair int% (lit %)) (pair int& (lit &))
        (pair int| (lit |)) (pair int<< (lit <<)) (pair int>> (lit >>))))
(def %fc-cmp-ops
  (list (pair int< (lit <)) (pair int= (lit =))))

; The forms the rewrite knows, by the value their name is bound to.
(def %fc-forms
  (list (pair if (lit if)) (pair when (lit when)) (pair unless (lit unless))
        (pair match (lit match)) (pair do (lit do)) (pair def (lit def))
        (pair set! (lit set!)) (pair lit (lit lit)) (pair and (lit and))
        (pair or (lit or)) (pair not (lit not)) (pair first (lit first))
        (pair rest (lit rest)) (pair pair (lit pair)) (pair eq? (lit eq?))
        (pair null? (lit null?)) (pair obj-ref (lit obj-ref))
        (pair obj-set! (lit obj-set!)) (pair pair? (lit pair?))
        (pair symbol? (lit symbol?))))

; The type-name handle each type test asks for, as type-of answers it for
; a value of the type.
(def %fc-type-of (prim-ref (lit type) (lit of)))
(def %fc-type-names
  (list (pair (lit pair?) (%fc-type-of (pair 1 2)))
        (pair (lit symbol?) (%fc-type-of (lit a)))))

; The primitives a compiled body may call with values: every one the engine's
; ISA manifest files under a label other than spine.  A spine primitive is
; the evaluator itself (def, fn, guard, lit, match, apply) and is handed its
; operands as forms; every other C primitive evaluates its operands as an
; applicative does.  A manifest name bound to something other than a
; primitive (the library's wrappers of the raw bitwise operators) adds
; nothing, and a primitive the manifest does not list is not called.
(include (Str append %engine-root "/tools/contract/isa.x"))
(def %fc-prim-type (%fc-type-of eq?))
(def %fc-isa-value
  (fn (_ v acc) (if (eq? (%fc-type-of v) %fc-prim-type) (pair v acc) acc)))
(def %fc-isa-bare
  (fn (self rows acc)
    (match
      ((null? rows) acc)
      ((eq? (first (rest (first rows))) (lit spine)) (self (rest rows) acc))
      (#t (self (rest rows)
            (guard (_ acc) (%fc-isa-value (eval (first (first rows))) acc)))))))
(def %fc-isa-catalogue
  (fn (self rows acc)
    (def row (if (null? rows) () (first rows)))
    (match
      ((null? rows) acc)
      ((eq? (first (rest (rest row))) (lit spine)) (self (rest rows) acc))
      (#t (self (rest rows)
            (guard (_ acc)
              (%fc-isa-value (prim-ref (first row) (first (rest row))) acc)))))))
(def %fc-applicatives
  (%fc-isa-catalogue %isa-catalogue
    (%fc-isa-bare %isa-keep (%fc-isa-bare %isa-bare ()))))
; And every closure compile-fn! has been given, which is a primitive once
; it is compiled.
(def %fc-compiled ())
(def %fc-applicative?
  (fn (_ v)
    (or (eq? (Fn label v) (lit fn))
        (List any? (fn (_ a) (obj-same? a v)) %fc-applicatives)
        (List any? (fn (_ a) (obj-same? a v)) %fc-compiled))))

(def %fc-assq
  (fn (self v l)
    (match
      ((null? l) ())
      ((obj-same? (first (first l)) v) (first l))
      (#t (self v (rest l))))))

(def %fc-memq
  (fn (self x l)
    (match ((null? l) #f) ((eq? (first l) x) #t) (#t (self x (rest l))))))

; --- The rewrite's state, one closure at a time ---------------------------------

(def %fc-target ())
(def %fc-env ())
(def %fc-self ())                ; the self parameter as F wrote it
(def %fc-names ())               ; parameters and locals
(def %fc-fvars ())               ; ((name . value) ...), newest first
(def %fc-cells ())               ; ((free-name . fvar-name) ...)
(def %fc-count 0)

(def %fc-refuse
  (fn (_ . parts)
    (Err raise (lit value) (%fold (fn (_ a s) (Str append a s)) "fn-compile: " parts) ())))

(def %fc-fresh
  (fn (_ stem)
    (set! %fc-count (int+ %fc-count 1))
    (str->sym (Str append stem (%number->str %fc-count)))))

; A constant, as an fvar holding it.
(def %fc-const
  (fn (_ v)
    (match
      ((null? v) ())
      ((eq? v #f) (lit %false))
      (#t ((fn (_ name)
             (set! %fc-fvars (pair (pair name v) %fc-fvars))
             name)
           (%fc-fresh "%fc-k"))))))

; A free name's binding cell, as an fvar.
(def %fc-binding
  (fn (_ name)
    (def cell (Env cell %fc-env name))
    (when (null? cell)
      (%fc-refuse "the free name " (symbol->str name) " is unbound"))
    cell))

(def %fc-cell
  (fn (_ name)
    (def known (%fc-assq name %fc-cells))
    (if (null? known)
      ((fn (_ fv)
         (set! %fc-fvars (pair (pair fv (%fc-binding name)) %fc-fvars))
         (set! %fc-cells (pair (pair name fv) %fc-cells))
         fv)
       (%fc-fresh "%fc-c"))
      (rest known))))

; What NAME means at the head of a call: (self), (local), or (free . value).
(def %fc-meaning
  (fn (_ name)
    (match
      ((eq? name %fc-self) (lit (self)))
      ((%fc-memq name %fc-names) (lit (local)))
      (#t (pair (lit free) (rest (%fc-binding name)))))))

; The defs of a body, by name, in the order they first appear.
(def %fc-defs
  (fn (_ body)
    (def acc (pair () ()))
    ((fn (walk e)
       (when (pair? e)
         (match
           ((eq? (first e) (lit lit)) ())
           (#t
             (do
               (when (and (eq? (first e) (lit def)) (pair? (rest e)) (symbol? (first (rest e)))
                          (not (%fc-memq (first (rest e)) (first acc))))
                 (%set-first! acc (pair (first (rest e)) (first acc))))
               ((fn (each l) (when (pair? l) (do (walk (first l)) (each (rest l))))) e))))))
     body)
    (List reverse (first acc))))

; --- Calls and the operands held across them ------------------------------------

; Does a rewritten expression make a call?
(def %fc-calls?
  (fn (self e)
    (match
      ((not (pair? e)) #f)
      ((eq? (first e) (lit %call-q)) #t)
      ((eq? (first e) (lit %fc-self)) #t)
      (#t ((fn (each l)
             (match ((not (pair? l)) #f) ((self (first l)) #t) (#t (each (rest l)))))
           e)))))

; An operand nothing can change or free while a call runs: a local, a
; constant (the function itself is one), or nil.
(def %fc-stable?
  (fn (_ e)
    (match
      ((null? e) #t)
      ((symbol? e) #t)
      (#t #f))))

; OPS rewritten to values, and the locals they need: each operand up to the
; last that makes a call is bound to a local first unless it is stable.
; Answers (hoists . operands), the hoists as (def NAME EXPR) forms in order.
(def %fc-hold
  (fn (_ ops)
    (def last
      ((fn (self l i at) (match ((null? l) at) ((%fc-calls? (first l)) (self (rest l) (int+ i 1) i)) (#t (self (rest l) (int+ i 1) at))))
       ops 0 -1))
    ((fn (self l i hoists out)
       (match
         ((null? l) (pair (List reverse hoists) (List reverse out)))
         ((or (int< last i) (%fc-stable? (first l)))
           (self (rest l) (int+ i 1) hoists (pair (first l) out)))
         (#t
           ((fn (_ t)
              (set! %fc-names (pair t %fc-names))
              (self (rest l) (int+ i 1)
                    (pair (list (lit def) t (first l)) hoists) (pair t out)))
            (%fc-fresh "%fc-t")))))
     ops 0 () ())))

; (do HOIST ... FORM), or FORM alone.
(def %fc-with
  (fn (_ hoists form)
    (if (null? hoists) form (pair (lit do) (%append hoists (list form))))))

; --- The rewrite ------------------------------------------------------------------

(def %fc-value ())
(def %fc-raw ())
(def %fc-test ())

(def %fc-bool
  (fn (_ test)
    (list (lit if) test (%fc-const #t) (lit %false))))

(def %fc-body
  (fn (_ forms)
    (match
      ((null? forms) ())
      ((null? (rest forms)) (%fc-value (first forms)))
      (#t (pair (lit do) (List map %fc-value forms))))))

; A raw operation over two or more operands, folded left; one operand of -
; is its negation.
(def %fc-raw-op
  (fn (_ op args)
    (match
      ((null? args) (%fc-refuse "an integer operation with no operand"))
      ((null? (rest args))
        (if (eq? op (lit -)) (list (lit -) (%fc-raw (first args))) (%fc-raw (first args))))
      (#t ((fn (self acc l)
             (if (null? l) acc (self (list op acc (%fc-raw (first l))) (rest l))))
           (list op (%fc-raw (first args)) (%fc-raw (first (rest args))))
           (rest (rest args)))))))

; The template a call site fills and evaluates (asm-compile.x, the function
; world): one (lit ()) for the callee and one for each of N arguments, made
; here with list, so the evaluator reads it as a call.
(def %fc-template
  (fn (_ n)
    ((fn (self k acc) (if (int< k 0) acc (self (int- k 1) (pair (list (lit lit) ()) acc))))
     n ())))

; A call with values: HEAD and ARGS rewritten, held, then (%call-q T ...)
; or a self-call (%fc-self T ...), T the site's template.
(def %fc-call
  (fn (_ head args)
    (def t (%fc-const (%fc-template (%length args))))
    ((fn (_ held)
       (%fc-with (first held)
         (if (eq? head (lit %fc-self))
           (pair (lit %fc-self) (pair t (rest held)))
           (pair (lit %call-q) (pair t (rest held))))))
     (%fc-hold (if (eq? head (lit %fc-self))
                 (List map %fc-value args)
                 (pair head (List map %fc-value args)))))))

; obj-ref and obj-set!: word i of the object's data, with the operands held
; as values and the index read raw.
(def %fc-obj
  (fn (_ form args)
    (def held (%fc-hold (List map %fc-value args)))
    (def ops (rest held))
    ; An index bound to a local is read from it; one that was not is
    ; rewritten raw, without the box its value form would build.
    (def index
      (list (lit +) %obj-meta-len
        (if (List any? (fn (_ h) (eq? (first (rest h)) (first (rest ops)))) (first held))
          (list (lit %unbox) (first (rest ops)))
          (%fc-raw (first (rest args))))))
    (%fc-with (first held)
      (if (eq? form (lit obj-ref))
        (list (lit %mem-ref-at) (first ops) index)
        (list (lit %mem-set-at!) (first ops) index (first (rest (rest ops))))))))

(def %fc-form
  (fn (_ form args)
    (match
      ((eq? form (lit lit)) (%fc-const (first args)))
      ((eq? form (lit if))
        (list (lit if) (%fc-test (first args)) (%fc-value (first (rest args)))
              (if (null? (rest (rest args))) () (%fc-value (first (rest (rest args)))))))
      ((eq? form (lit when))
        (list (lit if) (%fc-test (first args)) (%fc-body (rest args)) ()))
      ((eq? form (lit unless))
        (list (lit if) (%fc-test (first args)) () (%fc-body (rest args))))
      ; An arm is a test and one expression, as match reads it.
      ((eq? form (lit match))
        (pair (lit match)
          (List map
            (fn (_ arm)
              (list (if (eq? (first arm) #t) #t (%fc-test (first arm)))
                    (if (null? (rest arm)) () (%fc-value (first (rest arm))))))
            args)))
      ((eq? form (lit do)) (%fc-body args))
      ((eq? form (lit def))
        (list (lit def) (first args) (%fc-value (first (rest args)))))
      ((eq? form (lit set!))
        (if (%fc-memq (first args) %fc-names)
          (list (lit def) (first args) (%fc-value (first (rest args))))
          (list (lit %mem-set-at!) (%fc-cell (first args)) (int+ %obj-meta-len 1)
                (%fc-value (first (rest args))))))
      ((eq? form (lit and)) (pair (lit and) (List map %fc-value args)))
      ((eq? form (lit or)) (pair (lit or) (List map %fc-value args)))
      ((eq? form (lit not))
        (list (lit if) (%fc-test (first args)) (lit %false) (%fc-const #t)))
      ((eq? form (lit first)) (list (lit first) (%fc-value (first args))))
      ((eq? form (lit rest)) (list (lit rest) (%fc-value (first args))))
      ; A pair the evaluator and pair? read as one is a list pair, which
      ; the pair primitive makes.
      ((eq? form (lit pair)) (%fc-call (%fc-const pair) args))
      ((or (eq? form (lit eq?)) (eq? form (lit null?))
           (eq? form (lit pair?)) (eq? form (lit symbol?)))
        (%fc-bool (%fc-test (pair form args))))
      ((or (eq? form (lit obj-ref)) (eq? form (lit obj-set!))) (%fc-obj form args))
      (#t (%fc-refuse "no rewrite for " (symbol->str form))))))

; (H . ARGS) with H a symbol: what its name means decides the rewrite.
; The free head's value V decides it.  Raw mode answers a raw word: an
; integer door does so itself, and any other form's value is unboxed.
(def %fc-free-call
  (fn (_ h v args mode)
    (def raw (%fc-assq v %fc-raw-ops))
    (def cmp (%fc-assq v %fc-cmp-ops))
    (def form (%fc-assq v %fc-forms))
    (def value
      (fn (_ e) (if (eq? mode (lit raw)) (list (lit %unbox) e) e)))
    (match
      ((obj-same? v %fc-target) (value (%fc-call (lit %fc-self) args)))
      ((not (null? raw))
        (if (eq? mode (lit raw))
          (%fc-raw-op (rest raw) args)
          (list (lit %box) (%fc-raw-op (rest raw) args))))
      ((not (null? cmp))
        ((fn (_ t) (if (eq? mode (lit test)) t (value (%fc-bool t))))
         (list (rest cmp) (%fc-raw (first args)) (%fc-raw (first (rest args))))))
      ((not (null? form)) (value (%fc-form (rest form) args)))
      ((%fc-applicative? v)
        (value (%fc-call (list (lit rest) (%fc-cell h)) args)))
      ((and (class? v) (pair? args)) (value (%fc-send h v args)))
      (#t (%fc-refuse "the head " (symbol->str h)
            " is bound to neither a closure nor a form the rewrite knows")))))

; (C SEL ARG ...) with C a class: the class runs its public static method
; SEL as (M C ARG ...), so the send is that call, M resolved by method-of
; when F is compiled and C read from its binding.  A static field, a
; guarded member or no member of that name is refused.
(def %fc-send
  (fn (_ h c args)
    (def s (first args))
    (def sel (if (and (pair? s) (eq? (first s) (lit lit)) (pair? (rest s))) (first (rest s)) s))
    (unless (symbol? sel)
      (%fc-refuse "a send to " (symbol->str h) " whose selector is not a name"))
    (def m (method-of c sel))
    (when (null? m)
      (%fc-refuse "the send (" (symbol->str h) " " (symbol->str sel)
        ") is not a public static method"))
    (%fc-call (%fc-const m) (pair h (rest args)))))

; (H . ARGS) with H a symbol: what its name means decides the rewrite.
(def %fc-named-call
  (fn (_ h args mode)
    (def m (%fc-meaning h))
    (def value
      (fn (_ e) (if (eq? mode (lit raw)) (list (lit %unbox) e) e)))
    (match
      ((eq? (first m) (lit self)) (value (%fc-call (lit %fc-self) args)))
      ((eq? (first m) (lit local)) (value (%fc-call h args)))
      (#t (%fc-free-call h (rest m) args mode)))))

; E rewritten in MODE: value (an object), raw (a raw word) or test.
(def %fc-expr
  (fn (_ e mode)
    (match
      ((and (pair? e) (eq? (first e) (lit %fc-guarded)))
        ((fn (_ c) (if (eq? mode (lit raw)) (list (lit %unbox) c) c))
         (%fc-call (%fc-const %fc-guard-door) (rest e))))
      ((pair? e)
        (if (symbol? (first e))
          (%fc-named-call (first e) (rest e) mode)
          (%fc-refuse "a call whose head is not a name: " (io-display-to-str (first e)))))
      ((eq? mode (lit raw))
        (if (eq? (type-of e) (type-of 0))
          e
          (list (lit %unbox) (%fc-expr e (lit value)))))
      ((null? e) ())
      ((eq? e #t) (if (eq? mode (lit test)) #t (%fc-const #t)))
      ((symbol? e)
        (match
          ((eq? e %fc-self) (lit %self))
          ((%fc-memq e %fc-names) e)
          (#t (list (lit rest) (%fc-cell e)))))
      (#t (%fc-const e)))))

(set! %fc-value (fn (_ e) (%fc-expr e (lit value))))
; The form a free head names, or nil.
(def %fc-form-of
  (fn (_ e)
    (if (and (pair? e) (symbol? (first e)) (not (%fc-memq (first e) %fc-names))
             (not (eq? (first e) %fc-self)) (not (eq? (first e) (lit %fc-guarded))))
      ((fn (_ hit) (if (null? hit) () (rest hit)))
       (%fc-assq (rest (%fc-binding (first e))) %fc-forms))
      ())))

; In a test, null? and eq? compare words and branch, and pair? and symbol?
; read the operand's type name, with no #t or #f built.
(set! %fc-test
  (fn (_ e)
    ((fn (_ form)
       (match
         ((eq? form (lit null?)) (list (lit =) (%fc-value (first (rest e))) ()))
         ((or (eq? form (lit pair?)) (eq? form (lit symbol?)))
           (list (lit %type-is?) (%fc-value (first (rest e)))
                 (%fc-const (rest (%fc-assq form %fc-type-names)))))
         ((eq? form (lit eq?))
           ((fn (_ held) (%fc-with (first held) (pair (lit =) (rest held))))
            (%fc-hold (List map %fc-value (rest e)))))
         (#t (%fc-expr e (lit test)))))
     (%fc-form-of e))))
(set! %fc-raw (fn (_ e) (%fc-expr e (lit raw))))

; --- let, as locals ----------------------------------------------------------------
;
; (let ((N E) ...) BODY ...) is ((fn (_ N ...) BODY ...) E ...): each E is
; evaluated in the enclosing scope, then BODY runs in a scope of its own.
; Before the rest of the rewrite it becomes (do (def N' E) ... BODY ...),
; with a fresh local N' for each N and for each def of BODY's own scope,
; renamed through BODY.  Each E keeps the enclosing names, so the binding
; stays parallel.  A named let, (let NAME BINDINGS ...), is a loop and is
; refused.

; Is `let` in the closure being rewritten the let of x/core/control?
(def %fc-let? #f)

(def %fc-let-here?
  (fn (_ ps body)
    (def cell (Env cell %fc-env (lit let)))
    (and (not (null? cell)) (obj-same? (rest cell) let)
         (not (%fc-memq (lit let) ps)) (not (%fc-memq (lit let) (%fc-defs body))))))

(def %fc-let-form?
  (fn (_ e) (and %fc-let? (pair? e) (eq? (first e) (lit let)))))

; The names a let body binds in its own scope: NAMES, then each def of
; BODY not already among them.  A nested let's body is a scope of its own,
; and its values are evaluated in this one.
(def %fc-scope-names
  (fn (_ names body)
    (def acc (pair (List reverse names) ()))
    ((fn (walk e)
       (when (pair? e)
         (match
           ((eq? (first e) (lit lit)) ())
           ((%fc-let-form? e)
             (when (and (pair? (rest e)) (List list? (first (rest e))))
               (List map (fn (_ b) (when (pair? b) (walk (rest b)))) (first (rest e)))))
           (#t
             (do
               (when (and (eq? (first e) (lit def)) (pair? (rest e)) (symbol? (first (rest e)))
                          (not (%fc-memq (first (rest e)) (first acc))))
                 (%set-first! acc (pair (first (rest e)) (first acc))))
               ((fn (each l) (when (pair? l) (do (walk (first l)) (each (rest l))))) e))))))
     body)
    (List reverse (first acc))))

(def %fc-rename
  (fn (_ s m) ((fn (_ hit) (if (null? hit) s (rest hit))) (%fc-assq s m))))

(def %fc-unlet ())
(def %fc-unlet-list
  (fn (self l m)
    (if (pair? l) (pair (%fc-unlet (first l) m) (self (rest l) m)) (%fc-unlet l m))))

(def %fc-let-binding?
  (fn (_ b)
    (and (pair? b) (symbol? (first b)) (pair? (rest b)) (null? (rest (rest b))))))

(def %fc-unlet-let
  (fn (_ e m)
    (when (and (pair? (rest e)) (symbol? (first (rest e))))
      (%fc-refuse "a named let"))
    (def bs (if (pair? (rest e)) (first (rest e)) ()))
    (unless (and (pair? (rest e)) (List list? bs) (List all? %fc-let-binding? bs))
      (%fc-refuse "a let whose bindings are not a list of (name value)"))
    (def body (rest (rest e)))
    (unless (pair? body) (%fc-refuse "a let with no body"))
    (def inits (List map (fn (_ b) (%fc-unlet (first (rest b)) m)) bs))
    (def inner
      (%fold (fn (_ acc n) (pair (pair n (%fc-fresh "%fc-l")) acc)) m
        (%fc-scope-names (List map first bs) body)))
    (def defs
      ((fn (self l vs)
         (if (null? l) ()
           (pair (list (lit def) (%fc-rename (first (first l)) inner) (first vs))
                 (self (rest l) (rest vs)))))
       bs inits))
    (pair (lit do) (%append defs (%fc-unlet-list body inner)))))

; --- guard, outlined ---------------------------------------------------------------
;
; The engine's guard catches a raise by returning to the C stack it saved
; when it was entered, and code compiled here cannot save one.  So
; (guard (V H) B) is outlined: B becomes (fn (_ L ...) B) and H becomes
; (fn (_ V L ...) H), both made in F's environment, where L are the locals
; of F they read.  F calls %fc-guard-door with the two and the values of
; L, and the door runs the engine's guard.  Each outlined closure is given
; to compile-fn! after F.  A B or H that would def or set! a local of F is
; refused: the outlined copy cannot write it back.  A guard inside B or H
; stays a guard there, outlined when that closure is compiled.

(def %fc-guard? #f)
(def %fc-outer ())                ; F's parameters and defs, during the pre-pass
(def %fc-outlined ())             ; ((name . closure) ...), compiled after F

(def %fc-guard-door
  (fn (_ body handler . vals)
    (guard (e (apply handler (pair e vals))) (apply body vals))))

(def %fc-guard-here?
  (fn (_ ps body)
    (def cell (Env cell %fc-env (lit guard)))
    (and (not (null? cell)) (obj-same? (rest cell) guard)
         (not (%fc-memq (lit guard) ps)) (not (%fc-memq (lit guard) (%fc-defs body))))))

(def %fc-guard-form?
  (fn (_ e) (and %fc-guard? (pair? e) (eq? (first e) (lit guard)))))

; The names E mentions outside lit, each once, in the order they appear.
(def %fc-mentions
  (fn (_ e)
    (def acc (pair () ()))
    ((fn (walk x)
       (match
         ((symbol? x)
           (unless (%fc-memq x (first acc)) (%set-first! acc (pair x (first acc)))))
         ((not (pair? x)) ())
         ((eq? (first x) (lit lit)) ())
         (#t ((fn (each l) (if (pair? l) (do (walk (first l)) (each (rest l))) (walk l))) x))))
     e)
    (List reverse (first acc))))

; The names E defs or set!s, outside lit.
(def %fc-writes
  (fn (_ e)
    (def acc (pair () ()))
    ((fn (walk x)
       (when (and (pair? x) (not (eq? (first x) (lit lit))))
         (do
           (when (and (or (eq? (first x) (lit def)) (eq? (first x) (lit set!)))
                      (pair? (rest x)) (symbol? (first (rest x))))
             (%set-first! acc (pair (first (rest x)) (first acc))))
           ((fn (each l) (when (pair? l) (do (walk (first l)) (each (rest l))))) x))))
     e)
    (first acc)))

(def %fc-unguard
  (fn (_ e m)
    (def spec (if (pair? (rest e)) (first (rest e)) ()))
    (unless (and (pair? spec) (symbol? (first spec)) (pair? (rest spec))
                 (null? (rest (rest spec))) (pair? (rest (rest e)))
                 (null? (rest (rest (rest e)))))
      (%fc-refuse "a guard not of the form (guard (NAME HANDLER) BODY)"))
    (def v (%fc-fresh "%fc-e"))
    (set! %fc-guard? #f)
    (def body (%fc-unlet (first (rest (rest e))) m))
    (def handler (%fc-unlet (first (rest spec)) (pair (pair (first spec) v) m)))
    (set! %fc-guard? #t)
    (def known (%append %fc-outer (List map rest m)))
    (when (List any? (fn (_ s) (%fc-memq s known)) (%fc-writes (list body handler)))
      (%fc-refuse "a guard that defines or sets a local of the function"))
    (def locals
      (List filter (fn (_ s) (and (not (eq? s (lit _))) (%fc-memq s known)))
        (%fc-mentions (list body handler))))
    (def bf (eval (list (lit fn) (pair (lit _) locals) body) %fc-env))
    (def hf (eval (list (lit fn) (pair (lit _) (pair v locals)) handler) %fc-env))
    (set! %fc-outlined
      (pair (pair (lit %fc-guard-body) bf) (pair (pair (lit %fc-guard-handler) hf) %fc-outlined)))
    (pair (lit %fc-guarded) (pair (list (lit lit) bf) (pair (list (lit lit) hf) locals)))))

(set! %fc-unlet
  (fn (_ e m)
    (match
      ((symbol? e) (%fc-rename e m))
      ((not (pair? e)) e)
      ((eq? (first e) (lit lit)) e)
      ((%fc-let-form? e) (%fc-unlet-let e m))
      ((%fc-guard-form? e) (%fc-unguard e m))
      (#t (%fc-unlet-list e m)))))

; F as a function world expression and its fvars: (form . fvars).
(def %fc-rewrite
  (fn (_ f)
    (def ps (Fn params f))
    ; List list? first: List all? walks rest until (), and on a rest
    ; parameter, (_ . args), it would take first of the symbol.
    (unless (and (pair? ps) (List list? ps) (List all? symbol? ps))
      (%fc-refuse "the parameters are not a list of names"))
    (set! %fc-target f)
    (set! %fc-env (Fn env f))
    (set! %fc-self (first ps))
    (set! %fc-count 0)
    (set! %fc-outlined ())
    (set! %fc-outer (%append ps (%fc-defs (Fn body f))))
    (set! %fc-let? (%fc-let-here? ps (Fn body f)))
    (set! %fc-guard? (%fc-guard-here? ps (Fn body f)))
    (def src (%fc-unlet-list (Fn body f) ()))
    (set! %fc-let? #f)
    (set! %fc-guard? #f)
    (set! %fc-names (%append (rest ps) (%fc-defs src)))
    (set! %fc-fvars (list (pair (lit %self) f)))
    (set! %fc-cells ())
    (def body (%fc-body src))
    (def made
      (pair (list (lit fn) (pair (lit %fc-self) (rest ps)) body) %fc-fvars))
    (set! %fc-target ())
    (set! %fc-env ())
    made))

(def compile-fn!
  (fn (_ name f)
    ; Anything but a closure raises before an entry is made: an entry
    ; installs a version into F's own words, which would overwrite a value
    ; that is not a function.
    (unless (eq? (Fn label f) (lit fn))
      (Err raise (lit type) "fn-compile: only a closure made by fn compiles" f))
    ; Rewritten once, now: the closure's parts are read while F is still
    ; the closure.  A refusal is kept as the entry's reason.
    (def made
      (guard (e (pair #f (io-display-to-str e)))
        (pair #t (%fc-rewrite f))))
    ; Taken before the closures guard outlined are compiled: each of those
    ; is a rewrite of its own, and starts the list again.
    (def outlined (if (first made) %fc-outlined ()))
    (set! %fc-outlined ())
    (set! %fc-compiled (pair f %fc-compiled))
    (def entry
      (Compiled in-place name f
        (fn (_)
          (if (first made)
            (asm-compile-cached (first (rest made)) (rest (rest made)) (lit function))
            (Err raise (lit value) (rest made) ())))))
    (List map (fn (_ o) (compile-fn! (first o) (rest o))) outlined)
    entry))

(doc compile-fn!
  (param name SYMBOL "What the list of compiled functions calls it")
  (param f ANY "A closure made by fn")
  (returns Compiled "The entry: (entry state) is compiled, or failed with (entry reason)")
  (sample "((compile-fn! 'fib fib) state)" "compiled, and every holder of fib now calls the compiled version")
  "Compile the closure F where it stands: every holder of F calls the compiled version from here on, and the interpreted version stays on the Compiled list as the reference. Integer doors, obj-ref, obj-set!, first, rest, pair, eq?, null?, pair?, symbol?, not, if, when, unless, match, do, and, or, def, set! and let (not a named let) compile in place; a (guard (name handler) body) is outlined into two closures, run by the engine's guard and compiled in turn; a call of any other closure, or of a C primitive the engine's ISA manifest does not label spine, passes it values, and a send (C sel ...) to a class's public static method calls the method method-of resolves when F is compiled. A body with a form the rewrite cannot carry leaves F interpreted, with the reason on the entry; anything but a closure raises a type error and makes no entry.")

; The library's own hot loops, compiled wherever the compiler loads: the
; tower dialects import this module at boot, and a program on helium that
; imports it gets them too.  Hash fnv-1a's byte loop (x/type/hash, loaded in
; every context) is the inner loop of every Dict op on a string or symbol
; key.  On an engine with no JIT the entry fails and the loop stays as
; written.
(compile-fn! (lit fnv-1a) (eval (lit %fnv-go) (module x/type/hash)))

(doc (provide x/tool/fn-compile compile-fn!)
  (sample "(import x/tool/fn-compile compile-fn!) (compile-fn! 'fib fib)" "fib compiled where it stands, its interpreted version kept on the Compiled list")
  "A program's closures compiled where they stand, through compile-asm's function world.")
