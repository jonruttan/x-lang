; generic.x -- generic functions: open, multi-argument, type-directed
; dispatch. The cold-path flexibility layer beside message passing (the
; fast, single-receiver common case) -- reach for a generic when behaviour
; depends on the types of SEVERAL arguments, the thing a receiver method
; cannot express. docs/object-system.md names this as the generalization
; of Convert's type-keyed dispatch; Convert itself stays separate: its
; from-alists ARE the promotion lattice this module's ambiguity rule reads
; -- the data layer under generics, not a client of them.
;
;   (import x/type/generic)
;   (def-generic add "Numeric addition.")
;   (on add ((a Rational) (b Rational)) (%rat-add a b))
;   (on add (a b) (fallback a b))              ; bare name = wildcard
;   (add 1/2 1/3)                              ; a generic is a callable value
;
; Signature keys are VALUES, evaluated at registration: a CLASS matches
; its instances (subclasses included, nearer definitions winning), a TYPE
; HANDLE (from (Type of v)) matches that runtime type exactly, and a bare
; parameter name is the wildcard.
;
; Selection is pointwise, with NO scalar rank (ruled): a method applies
; when every position matches; one wins when it is at least as specific
; at every position and strictly more specific at one (per position:
; exact = 0, an ancestor class = its chain distance, wildcard = last).
; Two incomparable candidates fall to the cvt from-lattice -- the method
; whose keys ABSORB the other's (each differing key declares a conversion
; FROM the other) wins, the same relation the C operator arbitration
; reads -- and a silent lattice is an error naming both candidates.
(import x/type/class)
(def %g-str-append (prim-ref (lit str) (lit append)))
(def %g-display-str (prim-ref (lit io) (lit display-to-str)))
(def %g-make-type (prim-ref (lit type) (lit make)))
(def %g-make-instance (prim-ref (lit type) (lit make-instance)))
(def %g-type? (prim-ref (lit type) (lit ?)))
(def %g-type-of (prim-ref (lit type) (lit of)))
(def %g-type-by-atom (prim-ref (lit type) (lit by-atom)))
(def %g-from-cell (prim-ref (lit type) (lit from-cell)))

; The wildcard's distance: any real match beats it, and two wildcards tie.
(def %g-wild 999999)

; Distance of one argument from one signature key: 0 exact, k for a class
; matched k steps up the chain, %g-wild for the wildcard, nil for no match.
(def %g-dist
  (fn (_ key arg)
    (match
      ((eq? key #t) %g-wild)
      ((class? key)
        (when (object? arg)
          (let walk ((c (class-of arg)) (n 0))
            (match
              ((null? c) ())
              ((same? c key) n)
              (#t (walk (class-parent c) (+ n 1)))))))
      (#t (when (eq? (%g-type-of arg) key) 0)))))

; Score a method record's signature against the args: the per-position
; distance list, or nil when any position misses or the arity differs.
(def %g-score
  (fn (loop keys args)
    (match
      ((if (null? keys) (null? args) #f) ())
      ((if (null? keys) #t (null? args)) (lit no))
      (#t
        (let ((d (%g-dist (first keys) (first args))))
          (if (null? d) (lit no)
            (let ((tail (loop (rest keys) (rest args))))
              (if (eq? tail (lit no)) (lit no) (pair d tail)))))))))

; s1 pointwise-beats s2: <= everywhere, < somewhere.
(def %g-beats?
  (fn (loop s1 s2)
    (match
      ((null? s1) #f)
      ((< (first s1) (first s2)) (%g-le? (rest s1) (rest s2)))
      ((< (first s2) (first s1)) #f)
      (#t (loop (rest s1) (rest s2))))))
(def %g-le?
  (fn (loop s1 s2)
    (match
      ((null? s1) #t)
      ((< (first s2) (first s1)) #f)
      (#t (loop (rest s1) (rest s2))))))

; k1 absorbs k2 through the cvt lattice: k1 is a type handle whose type
; struct declares a conversion FROM k2 -- the same from-alist relation the
; C operator arbitration reads. Classes and wildcards sit outside the
; lattice (nil).
(def %g-absorbs?
  (fn (_ k1 k2)
    (when (if (symbol? k1) #f (if (eq? k1 #t) #f (not (class? k1))))
      (let ((ts (%g-type-by-atom k1)))
        (unless (null? ts)
          (not (null? (%assq k2 (first (%g-from-cell ts))))))))))

; m1's keys absorb m2's at every differing position.
(def %g-sig-absorbs?
  (fn (loop k1 k2)
    (match
      ((null? k1) #t)
      ((eq? (first k1) (first k2)) (loop (rest k1) (rest k2)))
      ((%g-absorbs? (first k1) (first k2)) (loop (rest k1) (rest k2)))
      (#t #f))))

(def %g-sig-str
  (fn (_ keys)
    (%g-display-str
      (%map (fn (_ k)
              (match
                ((eq? k #t) (lit *))
                ((class? k) (class-name k))
                (#t k)))
        keys))))

; Select among applicable (record . score) pairs: keep the pointwise
; frontier; a two-deep frontier falls to the lattice; a silent lattice
; errors naming both.
(def %g-select
  (fn (_ gname cands)
    (def %beaten-by?
      (fn (loop c fs)
        (if (null? fs) #f
          (if (%g-beats? (rest (first fs)) (rest c)) #t (loop c (rest fs))))))
    (def %join
      (fn (loop cs front)
        (match
          ((null? cs) front)
          (#t
            (let ((c (first cs)))
              (let ((beaten (%beaten-by? c front)))
                (loop (rest cs)
                  (if beaten front
                    (pair c (%filter (fn (_ f) (not (%g-beats? (rest c) (rest f)))) front))))))))))
    (let ((front (%join cands ())))
      (match
        ((null? front) ())
        ((null? (rest front)) (first (first front)))
        (#t
          ; two-deep frontier: lattice tiebreak, else the teaching error
          (let ((a (first (first front))) (b (first (first (rest front)))))
            (match
              ((%g-sig-absorbs? (first a) (first b)) a)
              ((%g-sig-absorbs? (first b) (first a)) b)
              (#t
                (error (%g-str-append (symbol->str gname)
                  (%g-str-append ": ambiguous -- "
                    (%g-str-append (%g-sig-str (first a))
                      (%g-str-append " vs " (%g-sig-str (first b)))))))))))))))

; Apply a generic to evaluated args: score every method, select, run.
; A total miss goes to the generic's miss handler (settable -- the numeric
; tower installs lattice promotion there); the default is a teaching error
; naming the generic and the argument types.
(def %g-apply
  (fn (_ g args)
    (let ((data (first g)))
      (let ((methods (first (first (rest data))))       ; methods box
            (gname (rest (first data))))
        (def %cands
          (fn (loop ms acc)
            (match
              ((null? ms) acc)
              (#t
                (let ((s (%g-score (first (first ms)) args)))
                  (loop (rest ms)
                    (if (eq? s (lit no)) acc
                      (pair (pair (first ms) s) acc))))))))
        (let ((m (%g-select gname (%cands methods ()))))
          (if (null? m)
            (let ((missf (first (first (rest (rest data))))))   ; miss box
              (if (null? missf)
                (error (%g-str-append (symbol->str gname)
                  (%g-str-append ": no method "
                    (%g-display-str (%map (fn (_ a) (%g-type-of a)) args)))))
                (apply missf (pair g (list args)))))
            (apply (rest m) args)))))))

; The %generic runtime type: instances are callable, evaluating their
; arguments in the caller's env and dispatching on the values' types.
; Payload (slot 0): ((name . SYM) methods-box miss-box) -- reads are
; positional on this spine; the boxes are one-cell mutables.
(def %generic
  (%g-make-type "GENERIC"
    (list
      (pair (lit call)
        (op (self . argfs) e
          (%g-apply self (%map1 (fn (_ a) (eval a e)) argfs))))
      (pair (lit write)
        (fn (_ self) (display "#<generic " (rest (first (first self))) ">"))))))

(def-class Generic ()
  (doc "Generic functions: open, multi-argument, type-directed dispatch. def-generic defines one; (on g (SIG...) body) adds a method; the generic itself is a callable value."
    (example "(do (def-generic sz) (on sz (x) 1) (sz 'a))" "1"))
  (static
    (method make (self (param name SYMBOL "The generic's name (for errors and printing)"))
      (doc "Create a generic function value with no methods."
        (returns ANY "The callable generic"))
      (%g-make-instance %generic
        (list (pair (lit name) name) (list ()) (list ()))))
    (method generic? (self (param x ANY "Value to test"))
      (doc "Test whether a value is a generic function."
        (returns BOOL "#t for a generic"))
      (%g-type? x %generic))
    (method add! (self (param g ANY "The generic") (param keys LIST "Signature keys: class | type handle | #t wildcard, one per argument") (param f CALLABLE "The method body, (fn (_ args...) ...)"))
      (doc "Register a method on a generic (the computed-signature door; (on ...) is the sugar). The newest registration wins ties with an identical signature."
        (returns ANY "nil"))
      (let ((box (first (rest (first g)))))
        (%set-first! box (pair (pair keys f) (first box))))
      ())
    (method miss! (self (param g ANY "The generic") (param f CALLABLE "Handler: (fn (_ g args) ...)"))
      (doc "Install the no-applicable-method handler (the numeric tower's lattice promotion rides here). nil restores the default error."
        (returns ANY "nil"))
      (%set-first! (first (rest (rest (first g)))) f)
      ())
    (method methods-of (self (param g ANY "The generic"))
      (doc "The registered (keys . fn) method records, newest first."
        (returns LIST "Method records"))
      (first (first (rest (first g)))))))

(doc (def def-generic
  (op (name . docstr) e
    (tail-eval
      (list (lit def) name
        (list (lit lit) (Generic make (%selector name))))
      e)))
  (note "(def-generic NAME [\"doc\"]) -- define NAME as a fresh generic. Methods")
  (note "arrive via (on NAME (SIG...) body...) or (Generic add! NAME keys fn).")
  (example "(do (def-generic f) (on f (x) 'hit) (f 1))" "'hit")
  (see def-class)
  "Define a generic function.")

(doc (def on
  (op (gexpr sig . body) e
    (let ((g (eval gexpr e)))
      (def %keys
        (fn (loop ss)
          (unless (null? ss)
            (pair
              (if (pair? (first ss)) (eval (first (rest (first ss))) e) #t)
              (loop (rest ss))))))
      (def %names
        (fn (loop ss)
          (unless (null? ss)
            (pair (if (pair? (first ss)) (first (first ss)) (first ss))
                  (loop (rest ss))))))
      (Generic add! g (%keys sig)
        (eval (pair (lit fn) (pair (pair (lit _) (%names sig)) body)) e)))))
  (note "(on G ((a Class) b (c Type-handle)) body...) -- add a method to generic G.")
  (note "An annotated (name KEY) position matches KEY (a class, subclasses included,")
  (note "or a type handle, exactly); a bare name matches anything. The body is a")
  (note "closure over the definition site, parameters bound by name.")
  (example "(do (def-generic f) (on f (x y) (+ x y)) (f 1 2))" "3")
  (see def-generic)
  "Add a method to a generic function for a signature of argument types.")

(doc (provide x/type/generic Generic def-generic on)
  (note "Message passing stays the hot path; generics are the multi-argument cold path.")
  (note "The ambiguity rule: pointwise specificity, then the cvt from-lattice, then a")
  (note "teaching error naming both candidates. No scalar rank, by ruling.")
  (example "(do (def-generic f) (on f (x) 'one) (f 9))" "'one")
  "Generic functions over the class and type systems.")
