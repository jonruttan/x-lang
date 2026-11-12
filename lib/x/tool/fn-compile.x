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
;   closures   a fn literal outlined, handed the locals it reads as values
;   calls     a call of F itself (a jump in tail position), and a call of
;              any closure or any C primitive the engine's ISA manifest does
;              not label spine, with values; a send (C SEL ...) to a class's
;              public static method, as a call of the method method-of
;              resolves, and to its own public static field, as a call of
;              the class
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
(import x/tool/asm-cache asm-compile-cached asm-compile-kept asm-fn-values)
(import x/type/base)
(import x/core/doors int+ int- int* int/ int% int< int= int& int| int<< int>>
  char->int image-transient! obj-ref obj-set! obj-same? obj->ptr ptr->int ptr-ref-word ptr-set-word! io-display-to-str
  str->sym str-byte-len str-byte-ref str-byte-sub
  type-of)

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
(def %fc-lits ())                ; the body's literals, in the order %fc-literals walks them
(def %fc-count 0)

(def %fc-refuse
  (fn (_ . parts)
    (Err raise (lit value) (%fold (fn (_ a s) (Str append a s)) "fn-compile: " parts) ())))

(def %fc-fresh
  (fn (_ stem)
    (set! %fc-count (int+ %fc-count 1))
    (str->sym (Str append stem (%number->str %fc-count)))))

; --- What an fvar's name says ---------------------------------------------------
; An fvar's value is this process's: a binding cell, a list a call site
; fills, a method.  Its NAME says how the value is come by from F alone, so
; the compiled code can be kept apart from the process that made it and the
; values found again by name (%fc-fvar-values), with no rewrite of F:
;
;   %self            F
;   %c:NAME          the binding cell of the free name NAME in F's environment
;   %t:N:I           a call site's template for N arguments, the I-th name
;                    the rewrite made, so each site has its own
;   %k:true          #t
;   %l:K             the K-th literal of F's body, as %fc-literals walks it
;   %q:NAME          the symbol NAME
;   %m:HEAD:SEL      the method (method-of C SEL), C the value of HEAD
;   %y:FORM          the type name pair? or symbol? asks for
;   %x:pair %x:guard the pair primitive and the door a guard runs through
;
; A constant that is none of these has a name that says nothing, %fc-kN: an
; outlined guard's two closures are made by the rewrite and by nothing else.
(def %fc-name (fn (_ . parts) (str->sym (%fold (fn (_ a s) (Str append a s)) "" parts))))
(def %fc-x-pair (%fc-name "%x:pair"))
(def %fc-x-guard (%fc-name "%x:guard"))
(def %fc-k-true (%fc-name "%k:true"))

; The literals of BODY, in order: each (lit X)'s X, whole, and each atom
; that is neither a name nor nil.
(def %fc-literals
  (fn (_ body)
    (def acc (pair () ()))
    ((fn (walk e)
       (match
         ((null? e) ())
         ((symbol? e) ())
         ((not (pair? e)) (%set-first! acc (pair e (first acc))))
         ((and (eq? (first e) (lit lit)) (pair? (rest e)))
           (%set-first! acc (pair (first (rest e)) (first acc))))
         (#t ((fn (each l) (when (pair? l) (do (walk (first l)) (each (rest l))))) e))))
     body)
    (List reverse (first acc))))

; NAME bound to V among the fvars, once.
(def %fc-fvar!
  (fn (_ name v)
    (when (null? (%fc-assq name %fc-fvars))
      (set! %fc-fvars (pair (pair name v) %fc-fvars)))
    name))

; The name of constant V when the rewrite gives none: the literal of the
; body it is, or a name that says nothing.
(def %fc-const-name
  (fn (_ v)
    (def k
      ((fn (self l i) (match ((null? l) ()) ((obj-same? (first l) v) i) (#t (self (rest l) (int+ i 1)))))
       %fc-lits 0))
    (match
      ((symbol? v) (%fc-name "%q:" (symbol->str v)))
      ((null? k) (%fc-fresh "%fc-k"))
      (#t (%fc-name "%l:" (%number->str k))))))

; A constant, as an fvar holding it; NAME when the rewrite knows what it is.
(def %fc-const
  (fn (_ v . name)
    (match
      ((null? v) ())
      ((eq? v #f) (lit %false))
      ((eq? v #t) (%fc-fvar! %fc-k-true v))
      ((null? name) (%fc-fvar! (%fc-const-name v) v))
      (#t (%fc-fvar! (first name) v)))))

; A template's name: its arguments, and a count that makes it the site's own.
(def %fc-template-name
  (fn (_ n)
    (set! %fc-count (int+ %fc-count 1))
    (%fc-name "%t:" (%number->str n) ":" (%number->str %fc-count))))

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
       (%fc-name "%c:" (symbol->str name)))
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
    (def t (%fc-const (%fc-template (%length args)) (%fc-template-name (%length args))))
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
      ((eq? form (lit pair)) (%fc-call (%fc-const pair %fc-x-pair) args))
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
; when F is compiled and C read from its binding.  A send to one of C's own
; public static fields, (C SEL) to read it or (C SEL V) to write it, is a
; call of C itself with (lit SEL) and the values: the class's dispatch reads
; or writes the field where it lives, when the code runs.  A guarded member,
; an inherited field or no member of that name is refused.
(def %fc-send
  (fn (_ h c args)
    (def s (first args))
    (def sel (if (and (pair? s) (eq? (first s) (lit lit)) (pair? (rest s))) (first (rest s)) s))
    (unless (symbol? sel)
      (%fc-refuse "a send to " (symbol->str h) " whose selector is not a name"))
    (def m (method-of c sel))
    (match
      ((not (null? m))
        (%fc-call (%fc-const m (%fc-name "%m:" (symbol->str h) ":" (symbol->str sel))) (pair h (rest args))))
      ((%fc-static-field? c sel)
        (%fc-call (list (lit rest) (%fc-cell h)) (pair (list (lit lit) sel) (rest args))))
      (#t (%fc-refuse "the send (" (symbol->str h) " " (symbol->str sel)
            ") is neither a public static method nor a public static field")))))

; SEL is one of C's own static fields, and reading it from the root
; environment does not raise, as a private or protected one does there.
; A read has no effect.
(def %fc-static-field?
  (fn (_ c sel)
    (and (%fc-memq sel (class-static-fields c))
         (guard (_ #f) (do (eval (list c (list (lit lit) sel)) (Env root)) #t)))))

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

; Is H what an outlined fn literal left at the head of a call?
(def %fc-outlined-head?
  (fn (_ h)
    (and (pair? h) (pair? (rest h))
         (or (eq? (first h) (lit %fc-outcall))
             (and (eq? (first h) (lit lit)) (List any? (fn (_ o) (obj-same? (rest o) (first (rest h)))) %fc-outlined))))))

; E rewritten in MODE: value (an object), raw (a raw word) or test.
(def %fc-expr
  (fn (_ e mode)
    (match
      ((and (pair? e) (eq? (first e) (lit %fc-guarded)))
        ((fn (_ c) (if (eq? mode (lit raw)) (list (lit %unbox) c) c))
         (%fc-call (%fc-const %fc-guard-door %fc-x-guard) (rest e))))
      ; An outlined fn literal: its closure M called with values, or a call
      ; of what M or the literal's one closure answers.
      ((and (pair? e) (eq? (first e) (lit %fc-outcall)))
        ((fn (_ c) (if (eq? mode (lit raw)) (list (lit %unbox) c) c))
         (%fc-call (%fc-value (first (rest e))) (rest (rest e)))))
      ((and (pair? e) (%fc-outlined-head? (first e)))
        ((fn (_ c) (if (eq? mode (lit raw)) (list (lit %unbox) c) c))
         (%fc-call (%fc-value (first e)) (rest e))))
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
             (not (eq? (first e) %fc-self)) (not (eq? (first e) (lit %fc-guarded)))
             (not (eq? (first e) (lit %fc-outcall))))
      ((fn (_ hit) (if (null? hit) () (rest hit)))
       (%fc-assq (rest (%fc-binding (first e))) %fc-forms))
      ())))

; eq? compares value words (docs/spec.md, eq?): an integer or a character
; by its value, any other object by its first data word, and nil only to
; nil.  Comparing the two objects' addresses answers #f for two integer
; objects of one value, which the interpreter answers #t.  Both operands
; are bound to locals, in order, and nil is tested before %unbox reads
; either one's first data word.
(def %fc-eq
  (fn (_ ops)
    (def a (%fc-fresh "%fc-t"))
    (def b (%fc-fresh "%fc-t"))
    (set! %fc-names (pair a (pair b %fc-names)))
    (def yes (%fc-const #t))
    (list (lit do)
      (list (lit def) a (first ops))
      (list (lit def) b (first (rest ops)))
      (list (lit if) (list (lit =) a ())
        (list (lit if) (list (lit =) b ()) yes (lit %false))
        (list (lit if) (list (lit =) b ()) (lit %false)
          (list (lit if) (list (lit =) (list (lit %unbox) a) (list (lit %unbox) b))
            yes (lit %false)))))))

; In a test, null? compares words and branches, eq? compares value words
; (%fc-eq), and pair? and symbol? read the operand's type name, with no #t
; or #f built.
(set! %fc-test
  (fn (_ e)
    ((fn (_ form)
       (match
         ((eq? form (lit null?)) (list (lit =) (%fc-value (first (rest e))) ()))
         ((or (eq? form (lit pair?)) (eq? form (lit symbol?)))
           (list (lit %type-is?) (%fc-value (first (rest e)))
                 (%fc-const (rest (%fc-assq form %fc-type-names)) (%fc-name "%y:" (symbol->str form)))))
         ((eq? form (lit eq?)) (%fc-eq (List map %fc-value (rest e))))
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

; Is NAME, in the closure being rewritten, the form V: bound to it in F's
; environment, and neither a parameter of F nor a def of BODY?
(def %fc-core-here?
  (fn (_ name v ps body)
    (def cell (Env cell %fc-env name))
    (and (not (null? cell)) (obj-same? (rest cell) v)
         (not (%fc-memq name ps)) (not (%fc-memq name (%fc-defs body))))))

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
    ; A fn literal in B or H is outlined when that closure is compiled.
    (def fn? %fc-fn?)
    (set! %fc-guard? #f)
    (set! %fc-fn? #f)
    (def body (%fc-unlet (first (rest (rest e))) m))
    (def handler (%fc-unlet (first (rest spec)) (pair (pair (first spec) v) m)))
    (set! %fc-guard? #t)
    (set! %fc-fn? fn?)
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

; --- fn literals, outlined ---------------------------------------------------------
;
; A (fn PARAMS BODY ...) in F makes a closure over F's scope, and F's
; locals live on the machine stack, where no closure keeps them.  So the
; literal is outlined and handed the locals of F it reads, L, as values:
;
;   ((fn (S P ...) B ...) A ...), called where it is written, with S only
;   at the head of a call in B, is (G L ... A ...).  G is
;   (fn (S L ... P ...) B' ...), each (S X ...) of B being (S L ... X ...)
;   in B'; G is made in F's environment and compiled after F.
;
;   Any other literal that reads no L is made once, in F's environment when
;   F is compiled, and compiled after F: each evaluation of the literal
;   answers that one closure.
;
;   Any other is (M L ...), M being (fn (_ L ...) (fn PARAMS BODY ...)) made
;   in F's environment, and the closure M answers is interpreted.
;
; The closure holds L's values and not F's bindings, so a literal whose
; body set!s an L is refused, and so is a closure M makes over an L that F
; defines after it, or defines again or sets after it.

(def %fc-fn? #f)
(def %fc-captures ())             ; the (%fc-outcall M L ...) forms, by identity

(def %fc-fn-form?
  (fn (_ e) (and %fc-fn? (pair? e) (eq? (first e) (lit fn)) (pair? (rest e)))))

; The names of a parameter list, a rest parameter last.
(def %fc-flat
  (fn (self l) (match ((null? l) ()) ((pair? l) (pair (first l) (self (rest l)))) (#t (list l)))))

; E with the names of M renamed and nothing else rewritten: a literal's body
; is rewritten when its own closure is compiled.
(def %fc-renamed
  (fn (_ e m)
    (def flags (list %fc-let? %fc-guard? %fc-fn?))
    (set! %fc-let? #f)
    (set! %fc-guard? #f)
    (set! %fc-fn? #f)
    (def r (%fc-unlet-list e m))
    (set! %fc-let? (first flags))
    (set! %fc-guard? (first (rest flags)))
    (set! %fc-fn? (first (rest (rest flags))))
    r))

; The locals of F the literal R reads, in the order they appear: names of F
; that are not R's parameters or the defs of its body.
(def %fc-held-locals
  (fn (_ r m)
    (def known (%append %fc-outer (List map rest m)))
    (def own (%append (%fc-flat (first (rest r))) (%fc-defs (rest (rest r)))))
    (def held
      (List filter (fn (_ s) (and (not (eq? s (lit _))) (%fc-memq s known) (not (%fc-memq s own))))
        (%fc-mentions r)))
    (when (List any? (fn (_ s) (%fc-memq s held)) (%fc-writes (rest (rest r))))
      (%fc-refuse "a fn literal that sets a local of the function"))
    held))

(def %fc-outline!
  (fn (_ c)
    (set! %fc-outlined (pair (pair (lit %fc-fn) c) %fc-outlined))
    c))

; The literal R, renamed, in value position.
(def %fc-unfn
  (fn (_ r m)
    (def held (%fc-held-locals r m))
    (if (null? held)
      (list (lit lit) (%fc-outline! (eval r %fc-env)))
      ((fn (_ call) (set! %fc-captures (pair call %fc-captures)) call)
       (pair (lit %fc-outcall)
         (pair (list (lit lit) (eval (list (lit fn) (pair (lit _) held) r) %fc-env)) held))))))

; BODY with each (S X ...) as (S L ... X ...), or #f when S is anywhere but
; at the head of a call: as a value, bound, or a match arm's test.  A fn
; literal whose parameters bind S is left as it is.
(def %fc-self-calls
  (fn (_ s held body)
    (def ok (pair #t ()))
    (def bad (fn (_ ) (%set-first! ok #f) ()))
    (def walk ())
    (def each
      (fn (self l)
        (match ((pair? l) (pair (walk (first l)) (self (rest l)))) ((eq? l s) (bad)) (#t l))))
    (def name-ok (fn (_ n) (if (eq? n s) (bad) n)))
    (set! walk
      (fn (_ e)
        (def h (if (pair? e) (first e) ()))
        (match
          ((eq? e s) (bad))
          ((not (pair? e)) e)
          ((eq? h s) (pair s (%append held (each (rest e)))))
          ((eq? h (lit lit)) e)
          ((not (pair? (rest e))) (each e))
          ((eq? h (lit fn))
            (if (%fc-memq s (%fc-flat (first (rest e)))) e
              (pair h (pair (first (rest e)) (each (rest (rest e)))))))
          ((or (eq? h (lit def)) (eq? h (lit set!)))
            (pair h (pair (name-ok (first (rest e))) (each (rest (rest e))))))
          ((eq? h (lit let))
            (if (List list? (first (rest e)))
              (pair h (pair (List map (fn (_ b) (if (pair? b) (pair (name-ok (first b)) (each (rest b))) b))
                              (first (rest e)))
                            (each (rest (rest e)))))
              (bad)))
          ((eq? h (lit guard))
            (if (pair? (first (rest e)))
              (pair h (pair (pair (name-ok (first (first (rest e)))) (each (rest (first (rest e)))))
                            (each (rest (rest e)))))
              (bad)))
          ((eq? h (lit match))
            (pair h (List map (fn (_ arm) (if (and (pair? arm) (eq? (first arm) s)) (bad) (each arm))) (rest e))))
          (#t (each e)))))
    (def out (each body))
    (if (first ok) out #f)))

; ((fn ...) A ...), the literal called where it is written.
(def %fc-unfn-call
  (fn (_ e m)
    (def r (%fc-renamed (first e) m))
    (def args (%fc-unlet-list (rest e) m))
    (def ps (first (rest r)))
    (def s (if (pair? ps) (first ps) ()))
    (def proper (and (symbol? s) (List all? symbol? (%fc-flat ps))))
    (def held (if proper (%fc-held-locals r m) ()))
    (def body (if proper (%fc-self-calls s held (rest (rest r))) #f))
    (if body
      (pair (lit %fc-outcall)
        (pair (list (lit lit) (%fc-outline! (eval (pair (lit fn) (pair (pair s (%append held (rest ps))) body)) %fc-env)))
          (%append held args)))
      (pair (%fc-unfn r m) args))))

; Each closure M makes holds the values its locals have when it is made: a
; local F defines after that, or defines again or sets, is refused.  SRC is
; walked as it runs, PS bound from the start.
(def %fc-check-captures
  (fn (_ src ps)
    (def known (pair ps ()))
    (def held (pair () ()))
    (def write!
      (fn (_ n)
        (when (%fc-memq n (first held))
          (%fc-refuse "a fn literal reads the local " (symbol->str n) ", which the function writes after it"))
        (%set-first! known (pair n (first known)))))
    ((fn (walk e)
       (def each (fn (self l) (when (pair? l) (do (walk (first l)) (self (rest l))))))
       (when (pair? e)
         (match
           ((eq? (first e) (lit lit)) ())
           ((List any? (fn (_ c) (obj-same? c e)) %fc-captures)
             (List map
               (fn (_ n)
                 (unless (%fc-memq n (first known))
                   (%fc-refuse "a fn literal reads the local " (symbol->str n) ", which the function defines after it"))
                 (%set-first! held (pair n (first held))))
               (rest (rest e))))
           ((and (or (eq? (first e) (lit def)) (eq? (first e) (lit set!)))
                 (pair? (rest e)) (symbol? (first (rest e))))
             (do (each (rest (rest e))) (write! (first (rest e)))))
           (#t (each e)))))
     src)))

(set! %fc-unlet
  (fn (_ e m)
    (match
      ((symbol? e) (%fc-rename e m))
      ((not (pair? e)) e)
      ((eq? (first e) (lit lit)) e)
      ((%fc-let-form? e) (%fc-unlet-let e m))
      ((%fc-guard-form? e) (%fc-unguard e m))
      ((%fc-fn-form? e) (%fc-unfn (%fc-renamed e m) m))
      ((%fc-fn-form? (first e)) (%fc-unfn-call e m))
      (#t (%fc-unlet-list e m)))))

; F as a function world expression and its fvars: (form . fvars).
(def %fc-rewrite
  (fn (_ f)
    ; The parameters as F wrote them, and as a list: a rest parameter, the
    ; name a dotted list ends in, is the last of PS.
    (def given (Fn params f))
    (def ps (%fc-flat given))
    ; A self parameter there must be: (fn args ...) has none to name.
    (unless (and (pair? given) (List all? symbol? ps))
      (%fc-refuse "the parameters are not a list of names"))
    (set! %fc-target f)
    (set! %fc-env (Fn env f))
    (set! %fc-self (first ps))
    (set! %fc-count 0)
    (set! %fc-outlined ())
    (set! %fc-outer (%append ps (%fc-defs (Fn body f))))
    (set! %fc-let? (%fc-core-here? (lit let) let ps (Fn body f)))
    (set! %fc-guard? (%fc-core-here? (lit guard) guard ps (Fn body f)))
    (set! %fc-fn? (%fc-core-here? (lit fn) fn ps (Fn body f)))
    (set! %fc-captures ())
    (def src (%fc-unlet-list (Fn body f) ()))
    (set! %fc-let? #f)
    (set! %fc-guard? #f)
    (set! %fc-fn? #f)
    (%fc-check-captures src ps)
    (set! %fc-captures ())
    (set! %fc-names (%append (rest ps) (%fc-defs src)))
    (set! %fc-fvars (list (pair (lit %self) f)))
    (set! %fc-lits (%fc-literals (Fn body f)))
    (set! %fc-cells ())
    (def body (%fc-body src))
    (def made
      (pair (list (lit fn) (pair (lit %fc-self) (rest given)) body) %fc-fvars))
    (set! %fc-target ())
    (set! %fc-env ())
    made))

; --- The fvars' values, from their names ----------------------------------------
; What the names say, read back: the values of NAMES for the closure F, in
; order, or #f when one of them says nothing or what it says is not there
; (a free name no longer bound, a class with no such method).  F is read and
; not rewritten.
(def %fc-digits
  (fn (_ s)
    (def n (str-byte-len s))
    ((fn (self i acc)
       (if (int= i n) acc
         (let ((d (int- (char->int (str-byte-ref s i)) 48)))
           (if (if (int< d 0) #t (int< 9 d)) () (self (int+ i 1) (int+ (int* acc 10) d))))))
     0 0)))

(def %fc-fvar-values
  (fn (_ f names)
    (def env (Fn env f))
    ; the body's literals by name, made at the first %l: asked for
    (def lits (pair () #f))
    (def literal
      (fn (_ name)
        (unless (rest lits)
          (%set-first! lits
            ((fn (self l k acc)
               (if (null? l) acc
                 (self (rest l) (int+ k 1) (pair (pair (%fc-name "%l:" (%number->str k)) (first l)) acc))))
             (%fc-literals (Fn body f)) 0 ()))
          (%set-rest! lits #t))
        (def e (%fc-assq name (first lits)))
        (if (null? e) () (list (rest e)))))
    ; (VALUE), or () when NAME's value is not to be had
    (def one
      (fn (_ name)
        (def s (symbol->str name))
        ; the letter of a %L:REST name, as its code, or 0
        (def letter
          (if (int< (str-byte-len s) 3) 0
            (if (int= (char->int (str-byte-ref s 2)) 58) (char->int (str-byte-ref s 1)) 0)))
        (def tail (fn (_ ) (str-byte-sub s 3 (int- (str-byte-len s) 3))))
        (match
          ((eq? name (lit %self)) (list f))
          ((eq? name %fc-k-true) (list #t))
          ((eq? name %fc-x-pair) (list pair))
          ((eq? name %fc-x-guard) (list %fc-guard-door))
          ((int= letter 99)
            (let ((cell (Env cell env (str->sym (tail)))))
              (if (null? cell) () (list cell))))
          ((int= letter 108) (literal name))
          ((int= letter 113) (list (str->sym (tail))))
          ((int= letter 116)
            (let ((n (%fc-digits (first (Str split ":" (tail))))))
              (if (null? n) () (list (%fc-template n)))))
          ((int= letter 121)
            (let ((e (%fc-assq (str->sym (tail)) %fc-type-names)))
              (if (null? e) () (list (rest e)))))
          ((int= letter 109)
            (let ((parts (Str split ":" (tail))))
              (if (if (null? (rest parts)) #t (not (null? (rest (rest parts))))) ()
                (let ((cell (Env cell env (str->sym (first parts)))))
                  (def m
                    (if (null? cell) ()
                      (if (class? (rest cell)) (method-of (rest cell) (str->sym (first (rest parts)))) ())))
                  (if (null? m) () (list m))))))
          (#t ()))))
    ((fn (self ns acc)
       (if (null? ns) (List reverse acc)
         (let ((v (one (first ns))))
           (if (null? v) #f (self (rest ns) (pair (first v) acc))))))
     names ())))

; --- An apply of a compiled function -------------------------------------------
; A call hands a function its argument expressions and an apply hands it
; values.  A closure is told which by the engine, which binds values as they
; are; a compiled function is a primitive, and the engine calls a primitive
; one way.  So the engine's apply routine is stood in for, in the base's slot
; (Base slot!): the routine below sets the function world's word (asm-fn-values)
; and calls the function when what is applied is one of these, and calls the
; routine it replaced for anything else.
;
; One of these is known by its state word, which holds the address of
; asm-fn-values: no closure's state and no other primitive's is that object.
; The word after the one the function reads holds the address of the routine
; replaced, which is this process's and so is read, not compiled in.
(def %fc-apply-expr
  (let ((head (list (lit %mem-ref) (lit call) %obj-meta-len)))
    (list (lit fn) (lit (self call))
      (list (lit if)
        (list (lit and) (lit call) head
          (list (lit =) (list (lit %mem-ref) head (int+ %obj-meta-len 1)) (lit %values)))
        (list (lit do)
          (list (lit %mem-set!) (lit %values) (int+ %obj-meta-len 1) 1)
          (list (lit %call-routine) (list (lit %mem-ref) head %obj-meta-len) (lit call)))
        (list (lit %call-routine)
          (list (lit %mem-ref) (lit %values) (int+ %obj-meta-len 2))
          (lit (%run-args)))))))

; The routine, once this base's apply slot holds it; nil until then, and on an
; engine where a compiled function has no word to read.
(def %fc-apply ())
(def %fc-arm-apply!
  (fn (_)
    (when (if (null? %fc-apply) (not (null? asm-fn-values)) #f)
      (def routine
        (asm-compile-cached %fc-apply-expr (list (pair (lit %values) asm-fn-values)) (lit (run integer))))
      (ptr-set-word! (obj->ptr asm-fn-values) (%data-word-off 2)
        (Base slot (%base) (lit callable-apply)))
      (Base slot! (%base) (lit callable-apply) routine)
      (Fn apply-values!
        (fn (_ f)
          (int= (ptr-ref-word (obj->ptr f) (%data-word-off 1)) (ptr->int (obj->ptr asm-fn-values)))))
      (set! %fc-apply routine))))

; The engine's routine back in the slot.  The writer of a state image runs
; this in the child it images, after which nothing there is marked: every
; entry is interpreted again (x/tool/compiled), and the first compile after
; the image is loaded arms the slot of the base that loaded it.
(def %fc-disarm-apply!
  (fn (_)
    (unless (null? %fc-apply)
      (Base slot! (%base) (lit callable-apply)
        (ptr-ref-word (obj->ptr asm-fn-values) (%data-word-off 2)))
      (Fn apply-values! ())
      (set! %fc-apply ()))))
(image-transient! (fn (_) (%fc-disarm-apply!)))

; V, a compiled function, marked as one the apply routine hands values.
(def %fc-mark!
  (fn (_ v)
    (unless (null? %fc-apply)
      (ptr-set-word! (obj->ptr v) (%data-word-off 1) (ptr->int (obj->ptr asm-fn-values))))
    v))

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
    ; What the first compile found, for the compiles after it: an entry is
    ; compiled again after every state image load.
    (def kept (pair () ()))
    (def entry
      (Compiled in-place name f
        (fn (_)
          (if (first made)
            (do (%fc-arm-apply!)
                (%fc-mark! (asm-compile-kept kept (first (rest made)) (rest (rest made)) (lit function))))
            (Err raise (lit value) (rest made) ())))))
    (List map (fn (_ o) (compile-fn! (first o) (rest o))) outlined)
    entry))

(doc compile-fn!
  (param name SYMBOL "What the list of compiled functions calls it")
  (param f ANY "A closure made by fn")
  (returns Compiled "The entry: (entry state) is compiled, or failed with (entry reason)")
  (sample "((compile-fn! 'fib fib) state)" "compiled, and every holder of fib now calls the compiled version")
  "Compile the closure F where it stands: every holder of F calls the compiled version from here on, and the interpreted version stays on the Compiled list as the reference. Integer doors, obj-ref, obj-set!, first, rest, pair, eq?, null?, pair?, symbol?, not, if, when, unless, match, do, and, or, def, set! and let (not a named let) compile in place; a (guard (name handler) body) is outlined into two closures, run by the engine's guard and compiled in turn. A fn literal is outlined and handed the locals of F it reads as values: one called where it is written, ((fn (self ...) ...) arg ...), with self only at the head of a call, becomes a closure taking those locals as parameters, compiled in turn; one that reads no local is made once and compiled in turn; any other answers an interpreted closure over the values, and one whose locals F writes after it, or whose body sets one, is refused. A call of any other closure, or of a C primitive the engine's ISA manifest does not label spine, passes it values, and a send (C sel ...) to a class's public static method calls the method method-of resolves when F is compiled, and one to its own public static field calls the class to read or write it. A rest parameter, (fn (self a . more) ...), is bound to the list of the arguments after a's, and such a function's self-call is a call and not a jump. Applied, by apply or by the engine as a type's handler is, the compiled F takes the values it is handed as a closure does: the first compile puts a routine in this base's callable-apply slot (Base slot!) that tells it so, and a state image is written with the engine's routine back in the slot. A body with a form the rewrite cannot carry leaves F interpreted, with the reason on the entry; anything but a closure raises a type error and makes no entry.")

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
