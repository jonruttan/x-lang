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
;              local or a free name
;   calls      a call of F itself (a jump in tail position), and a call of
;              any closure or any C primitive the engine's ISA manifest does
;              not label spine, with values
;
; A free name is read through its binding cell, found by the engine's lookup
; when F is compiled ((Env cell ...)): a later set! or def of the name is
; seen, as interpreted code sees it.  A head is decided when F is compiled,
; by the value its name is bound to then: an integer door is compiled as the
; operation, a closure as a call.  Rebinding one of those names to something
; else afterwards is not seen until F is compiled again.
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
      (#t (%fc-refuse "the head " (symbol->str h)
            " is bound to neither a closure nor a form the rewrite knows")))))

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
             (not (eq? (first e) %fc-self)))
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

; F as a function world expression and its fvars: (form . fvars).
(def %fc-rewrite
  (fn (_ f)
    (def ps (Fn params f))
    (unless (and (pair? ps) (List all? symbol? ps))
      (%fc-refuse "the parameters are not a list of names"))
    (set! %fc-target f)
    (set! %fc-env (Fn env f))
    (set! %fc-self (first ps))
    (set! %fc-names (%append (rest ps) (%fc-defs (Fn body f))))
    (set! %fc-fvars (list (pair (lit %self) f)))
    (set! %fc-cells ())
    (set! %fc-count 0)
    (def body (%fc-body (Fn body f)))
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
    (set! %fc-compiled (pair f %fc-compiled))
    (Compiled in-place name f
      (fn (_)
        (if (first made)
          (asm-compile-cached (first (rest made)) (rest (rest made)) (lit function))
          (Err raise (lit value) (rest made) ()))))))

(doc compile-fn!
  (param name SYMBOL "What the list of compiled functions calls it")
  (param f ANY "A closure made by fn")
  (returns Compiled "The entry: (entry state) is compiled, or failed with (entry reason)")
  (sample "((compile-fn! 'fib fib) state)" "compiled, and every holder of fib now calls the compiled version")
  "Compile the closure F where it stands: every holder of F calls the compiled version from here on, and the interpreted version stays on the Compiled list as the reference. Integer doors, obj-ref, obj-set!, first, rest, pair, eq?, null?, pair?, symbol?, not, if, when, unless, match, do, and, or, def and set! compile in place; a call of any other closure, or of a C primitive the engine's ISA manifest does not label spine, passes it values. A body with a form the rewrite cannot carry leaves F interpreted, with the reason on the entry; anything but a closure raises a type error and makes no entry.")

(doc (provide x/tool/fn-compile compile-fn!)
  (sample "(import x/tool/fn-compile compile-fn!) (compile-fn! 'fib fib)" "fib compiled where it stands, its interpreted version kept on the Compiled list")
  "A program's closures compiled where they stand, through compile-asm's function world.")
