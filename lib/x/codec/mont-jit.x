; mont-jit.x -- Montgomery arithmetic compiled, for one modulus at a time.
;
; Loaded lazily, as the other engines are: this module pulls the JIT
; toolchain.  For a modulus x/codec/mont built, it generates three
; straight-line functions over a scratch of 64-bit words -- multiply, add
; and subtract mod m, each (fn (_ a h f g)) with h, f and g word offsets
; of n-limb numbers -- the modulus's limbs and n' written in as
; immediates, and compiles them.  The multiply is mont.x's CIOS unrolled:
; the lane has no locals, so a row's sum and carry ride two scratch words.
; The last step of each operation, subtracting m when the value reached
; it, is branch-free: the borrow of the trial subtraction, 0 or -1 by the
; lane's arithmetic shift, masks which of the two results is written.
; The engine is adopted only after it agrees with mont.x's pure-x
; operations, limb for limb.
(module x/codec/mont-jit)

(import x/tool/compile compile-asm)
(import x/type/vector)
; A pure engine's inverse collects at fixed points, as mont-pow does.
(import x/sys/gc)
(import x/codec/mont mont-n mont-mul mont-add mont-sub mont-to mont-number mont-bytes mont-minus-two mont-r2)

(def %mj-make-str (prim-ref (lit str) (lit make)))
(def %mj-str->ptr (prim-ref (lit str) (lit ->ptr)))
(def %mj-ptr->int (prim-ref (lit ptr) (lit ->int)))
(def %mj-pset (prim-ref (lit ptr) (lit set-word!)))
(def %mj-pref (prim-ref (lit ptr) (lit ref-word)))
(def %mj-oref (prim-ref (lit obj) (lit ref)))
(def %mj-oset! (prim-ref (lit obj) (lit set!)))
(def %mj-byte-ref (prim-ref (lit str) (lit byte-ref)))
(def %mj-char->int (prim-ref (lit char) (lit ->int)))

(def %M 67108863)

; --- expression builders (generation time) ---------------------------------
;
; The scratch: SLOTS numbers of n words from word 0, then the work area at
; W: the row t (n + 2 words), the trial difference d (n words), and the
; sum, carry and quotient words.

(def %mj-at (fn (_ off i) (list '%mem-ref-at 'a (list '+ off i))))
(def %mj-set (fn (_ off i v) (list '%mem-set-at! 'a (list '+ off i) v)))
(def %mj-w (fn (_ i) (list '%mem-ref 'a i)))
(def %mj-w! (fn (_ i v) (list '%mem-set! 'a i v)))
(def %mj-seq
  (fn (_ k f) (pair 'do ((fn (self i) (if (= i k) () (pair (f i) (self (+ i 1))))) 0))))

; The work area's words, for n limbs at base W.
(def %mj-layout
  (fn (_ n w)
    (list (+ w 0)                  ; T: the row, n + 2 words
          (+ w n 2)                ; D: the trial difference, n words
          (+ w n 2 n)              ; S: a row's sum
          (+ w n 2 n 1)            ; C: its carry
          (+ w n 2 n 2))))         ; Q: the quotient digit

; h := the t row less m when it reached m, else the row; top is the word
; holding the row's carry out of limb n-1 (0 or 1).
(def %mj-reduce-into
  (fn (_ n ps T D S C top)
    (list 'do
      (%mj-w! C 0)
      (%mj-seq n (fn (_ j)
                   (list 'do
                     (%mj-w! S (list '+ (list '- (%mj-w (+ T j)) (List ref j ps)) (%mj-w C)))
                     (%mj-w! (+ D j) (list '& (%mj-w S) %M))
                     (%mj-w! C (list '>> (%mj-w S) 26)))))
      ; the mask: -1 when the row is below m (keep it), 0 when not (take d)
      (%mj-w! C (list '+ (%mj-w C) top))
      (%mj-seq n (fn (_ j)
                   (%mj-set 'h j (list '^ (%mj-w (+ D j))
                                       (list '& (list '^ (%mj-w (+ D j)) (%mj-w (+ T j))) (%mj-w C)))))))))

(def %mj-mul-expr
  (fn (_ n ps inv T D S C Q)
    (list 'fn '(_ a h f g)
      (list 'do
        (%mj-seq (+ n 2) (fn (_ j) (%mj-w! (+ T j) 0)))
        (%mj-seq n (fn (_ i)
          (list 'do
            ; t += f_i g
            (%mj-w! C 0)
            (%mj-seq n (fn (_ j)
                         (list 'do
                           (%mj-w! S (list '+ (list '+ (%mj-w (+ T j)) (list '* (%mj-at 'f i) (%mj-at 'g j))) (%mj-w C)))
                           (%mj-w! (+ T j) (list '& (%mj-w S) %M))
                           (%mj-w! C (list '>> (%mj-w S) 26)))))
            (%mj-w! S (list '+ (%mj-w (+ T n)) (%mj-w C)))
            (%mj-w! (+ T n) (list '& (%mj-w S) %M))
            (%mj-w! (+ T n 1) (list '>> (%mj-w S) 26))
            ; t = (t + q m) / 2^26, q clearing the bottom limb
            (%mj-w! Q (list '& (list '* (%mj-w T) inv) %M))
            (%mj-w! C (list '>> (list '+ (%mj-w T) (list '* (%mj-w Q) (List ref 0 ps))) 26))
            (%mj-seq (- n 1) (fn (_ k)
                               (do (def j (+ k 1))
                                   (list 'do
                                     (%mj-w! S (list '+ (list '+ (%mj-w (+ T j)) (list '* (%mj-w Q) (List ref j ps))) (%mj-w C)))
                                     (%mj-w! (+ T (- j 1)) (list '& (%mj-w S) %M))
                                     (%mj-w! C (list '>> (%mj-w S) 26))))))
            (%mj-w! S (list '+ (%mj-w (+ T n)) (%mj-w C)))
            (%mj-w! (+ T (- n 1)) (list '& (%mj-w S) %M))
            (%mj-w! (+ T n) (list '+ (%mj-w (+ T n 1)) (list '>> (%mj-w S) 26))))))
        (%mj-reduce-into n ps T D S C (%mj-w (+ T n)))))))

(def %mj-add-expr
  (fn (_ n ps T D S C)
    (list 'fn '(_ a h f g)
      (list 'do
        (%mj-w! C 0)
        (%mj-seq n (fn (_ j)
                     (list 'do
                       (%mj-w! S (list '+ (list '+ (%mj-at 'f j) (%mj-at 'g j)) (%mj-w C)))
                       (%mj-w! (+ T j) (list '& (%mj-w S) %M))
                       (%mj-w! C (list '>> (%mj-w S) 26)))))
        (%mj-w! (+ T n) (%mj-w C))
        (%mj-reduce-into n ps T D S C (%mj-w (+ T n)))))))

; f - g, and m added back when that borrowed: the borrow's -1 masks m in.
(def %mj-sub-expr
  (fn (_ n ps T D S C)
    (list 'fn '(_ a h f g)
      (list 'do
        (%mj-w! C 0)
        (%mj-seq n (fn (_ j)
                     (list 'do
                       (%mj-w! S (list '+ (list '- (%mj-at 'f j) (%mj-at 'g j)) (%mj-w C)))
                       (%mj-w! (+ T j) (list '& (%mj-w S) %M))
                       (%mj-w! C (list '>> (%mj-w S) 26)))))
        (%mj-w! (+ T n) (%mj-w C))
        (%mj-w! C 0)
        (%mj-seq n (fn (_ j)
                     (list 'do
                       (%mj-w! S (list '+ (list '+ (%mj-w (+ T j)) (list '& (List ref j ps) (%mj-w (+ T n)))) (%mj-w C)))
                       (%mj-set 'h j (list '& (%mj-w S) %M))
                       (%mj-w! C (list '>> (%mj-w S) 26)))))))))

; h := f, word for word
(def %mj-copy-expr
  (fn (_ n) (list (lit fn) (lit (_ a h f)) (%mj-seq n (fn (_ i) (%mj-set (lit h) i (%mj-at (lit f) i)))))))

; The OR of f's limbs: zero exactly when f is
(def %mj-or-expr
  (fn (_ n)
    (list (lit fn) (lit (_ a f))
      ((fn (self i) (if (= i (- n 1)) (%mj-at (lit f) i) (list (lit |) (%mj-at (lit f) i) (self (+ i 1))))) 0))))

; The OR of the limbs' XORs: zero exactly when f = g
(def %mj-xor-or-expr
  (fn (_ n)
    (list (lit fn) (lit (_ a f g))
      ((fn (self i)
         (def x (list (lit ^) (%mj-at (lit f) i) (%mj-at (lit g) i)))
         (if (= i (- n 1)) x (list (lit |) x (self (+ i 1)))))
       0))))

; --- the engine -----------------------------------------------------------
;
; A vector of (STORE PTR ADDR N MUL ADD SUB KIND M).  A COMPILED engine's
; numbers are slots of n words in its scratch STORE, and MUL, ADD and SUB
; are the compiled functions; a PURE engine's are limb vectors in a vector
; STORE, and its operations mont.x's.  Callers name slots 0..%mj-free - 1;
; the slots above hold R^2, a plain one and R mod m for entering and
; leaving the form, and a power's working values.

(def %mj-slots 48)
(def mont-jit-free 42)
(def %mj-acc 42)
(def %mj-base 43)
(def %mj-r 44)
(def %mj-plain-one 45)
(def %mj-r2 46)

(def mont-jit-n (fn (_ e) (%mj-oref e 4)))
(def %mj-pure? (fn (_ e) (eq? (%mj-oref e 8) (lit pure))))
(def %mj-m (fn (_ e) (%mj-oref e 9)))

; Slot k's word offset, in a compiled engine.
(def %mj-off (fn (_ e k) (* k (mont-jit-n e))))

(def %mj-word-ref (fn (_ e k i) (%mj-pref (%mj-oref e 2) (* (+ (%mj-off e k) i) 8))))
(def %mj-word-set! (fn (_ e k i v) (%mj-pset (%mj-oref e 2) (* (+ (%mj-off e k) i) 8) v)))

(def mont-jit-load!
  (fn (_ e k v)
    (def n (mont-jit-n e))
    (if (%mj-pure? e)
      (%mj-oset! (%mj-oref e 1) (+ k 1) v)
      ((fn (self i) (unless (= i n) (do (%mj-word-set! e k i (%mj-oref v (+ i 1))) (self (+ i 1))))) 0))))

(def mont-jit-store
  (fn (_ e k)
    (def n (mont-jit-n e))
    (if (%mj-pure? e)
      (%mj-oref (%mj-oref e 1) (+ k 1))
      (do (def v (Vector make n 0))
          ((fn (self i) (unless (= i n) (do (%mj-oset! v (+ i 1) (%mj-word-ref e k i)) (self (+ i 1))))) 0)
          v))))

; Copy, the zero test and equality: compiled in a compiled engine, since a
; word at a time through x is thousands of objects a call where the
; compiled function is a few; vectors in a pure one.
(def mont-jit-copy!
  (fn (_ e to from)
    (if (%mj-pure? e)
      (mont-jit-load! e to (mont-jit-store e from))
      ((%mj-oref e 10) (%mj-oref e 3) (%mj-off e to) (%mj-off e from)))))

(def mont-jit-zero?
  (fn (_ e k)
    (if (%mj-pure? e)
      (do (def n (mont-jit-n e))
          (def v (mont-jit-store e k))
          ((fn (self i) (if (> i n) #t (if (= (%mj-oref v i) 0) (self (+ i 1)) #f))) 1))
      (= 0 ((%mj-oref e 11) (%mj-oref e 3) (%mj-off e k))))))

(def mont-jit-eq?
  (fn (_ e k l)
    (if (%mj-pure? e)
      (do (def n (mont-jit-n e))
          (def a (mont-jit-store e k))
          (def b (mont-jit-store e l))
          ((fn (self i) (if (> i n) #t (if (= (%mj-oref a i) (%mj-oref b i)) (self (+ i 1)) #f))) 1))
      (= 0 ((%mj-oref e 12) (%mj-oref e 3) (%mj-off e k) (%mj-off e l))))))

(def %mj-op
  (fn (_ e slot pure h f g)
    (if (%mj-pure? e)
      (mont-jit-load! e h (pure (%mj-m e) (mont-jit-store e f) (mont-jit-store e g)))
      ((%mj-oref e slot) (%mj-oref e 3) (%mj-off e h) (%mj-off e f) (%mj-off e g)))))

(def mont-jit-mul (fn (_ e h f g) (%mj-op e 5 mont-mul h f g)))
(def mont-jit-add (fn (_ e h f g) (%mj-op e 6 mont-add h f g)))
(def mont-jit-sub (fn (_ e h f g) (%mj-op e 7 mont-sub h f g)))

; Into the form (times R^2), out of it (times a plain one), and R mod m.
(def mont-jit-to! (fn (_ e h f) (mont-jit-mul e h f %mj-r2)))
(def mont-jit-from! (fn (_ e h f) (mont-jit-mul e h f %mj-plain-one)))
(def mont-jit-one! (fn (_ e h) (mont-jit-copy! e h %mj-r)))

; h = f^-1 in the form, m prime: f^(m-2), square and multiply from the top
; bit of the exponent down, on the engine's own working slots.
(def mont-jit-inv!
  (fn (_ e h f)
    (def m (%mj-m e))
    (def ex (mont-minus-two m))
    (def len (mont-bytes m))
    (mont-jit-copy! e %mj-base f)
    (mont-jit-copy! e %mj-acc %mj-r)
    ((fn (self j)
       (unless (= j len)
         (do ; a pure engine's multiplies leave thousands of objects each
             (when (and (%mj-pure? e) (= (& j 3) 0)) (Heap collect))
             (def b (%mj-char->int (%mj-byte-ref ex j)))
             ((fn (self k)
                (unless (< k 0)
                  (do (mont-jit-mul e %mj-acc %mj-acc %mj-acc)
                      (when (= (& (>> b k) 1) 1) (mont-jit-mul e %mj-acc %mj-acc %mj-base))
                      (self (- k 1)))))
              7)
             (self (+ j 1)))))
     0)
    (mont-jit-copy! e h %mj-acc)))

(def %mj-same?
  (fn (_ x y n) ((fn (self i) (if (> i n) #t (if (= (%mj-oref x i) (%mj-oref y i)) (self (+ i 1)) #f))) 1)))

; The differential check: each operation against mont.x's on numbers with
; every limb in use, and near the top of the range, where the final
; subtraction decides.
(def %mj-check
  (fn (_ e m)
    (def n (mont-n m))
    (def len (mont-bytes m))
    (def num
      (fn (_ byte)
        (def s (%mj-make-str len))
        (def p (%mj-str->ptr s))
        ((fn (self i) (unless (= i len) (do ((prim-ref (lit ptr) (lit set!)) p i (& (+ byte (* i 37)) 255) 1) (self (+ i 1))))) 0)
        (mont-to m (mont-number m s 0 len))))
    (def x (num 91))
    (def y (num 203))
    ; m - x: a number near the top of the range
    (def top (mont-sub m (mont-sub m x x) x))
    (def %try
      (fn (_ what op pure f g)
        (mont-jit-load! e 0 f) (mont-jit-load! e 1 g)
        (op e 2 0 1)
        (unless (%mj-same? (mont-jit-store e 2) (pure m f g) n)
          (Err raise 'state (Str8 append "mont-jit: " what " disagrees with the pure-x arithmetic") ()))))
    (%try "mul" mont-jit-mul mont-mul x y)
    (%try "mul" mont-jit-mul mont-mul top top)
    (%try "add" mont-jit-add mont-add x y)
    (%try "add" mont-jit-add mont-add top top)
    (%try "sub" mont-jit-sub mont-sub x y)
    (%try "sub" mont-jit-sub mont-sub y x)
    (%try "sub" mont-jit-sub mont-sub x x)))

(def %mj-reserve!
  (fn (_ e m)
    (def n (mont-n m))
    (def one (Vector make n 0))
    (%mj-oset! one 1 1)
    (mont-jit-load! e %mj-plain-one one)
    (mont-jit-load! e %mj-r2 (mont-r2 m))
    (mont-jit-load! e %mj-r (mont-to m one))))

; A pure engine: the same slots and calls, mont.x's arithmetic beneath.
(def mont-jit-pure
  (fn (_ m)
    (def e (Vector make 12 ()))
    (%mj-oset! e 1 (Vector make %mj-slots ()))
    (%mj-oset! e 4 (mont-n m))
    (%mj-oset! e 8 (lit pure))
    (%mj-oset! e 9 m)
    (%mj-reserve! e m)
    e))

; The compiled engine for modulus m: its scratch of %mj-slots numbers and
; the three compiled operations, built and checked against mont.x.  Raises
; when the lane cannot build them or they disagree.
(def mont-jit-make
  (fn (_ m)
    (def n (mont-n m))
    (def ps ((fn (self i acc) (if (< i 0) acc (self (- i 1) (pair (%mj-oref (%mj-oref m 2) (+ i 1)) acc)))) (- n 1) ()))
    (def inv (%mj-oref m 3))
    (def w (* %mj-slots n))
    (def lay (%mj-layout n w))
    (def T (List ref 0 lay)) (def D (List ref 1 lay)) (def S (List ref 2 lay)) (def C (List ref 3 lay)) (def Q (List ref 4 lay))
    (def buf (%mj-make-str (* (+ Q 1) 8)))
    (def ptr (%mj-str->ptr buf))
    (def e (Vector make 12 ()))
    (%mj-oset! e 1 buf)
    (%mj-oset! e 2 ptr)
    (%mj-oset! e 3 (%mj-ptr->int ptr))
    (%mj-oset! e 4 n)
    (%mj-oset! e 5 (compile-asm (%mj-mul-expr n ps inv T D S C Q)))
    (%mj-oset! e 6 (compile-asm (%mj-add-expr n ps T D S C)))
    (%mj-oset! e 7 (compile-asm (%mj-sub-expr n ps T D S C)))
    (%mj-oset! e 10 (compile-asm (%mj-copy-expr n)))
    (%mj-oset! e 11 (compile-asm (%mj-or-expr n)))
    (%mj-oset! e 12 (compile-asm (%mj-xor-or-expr n)))
    (%mj-oset! e 8 (lit compiled))
    (%mj-oset! e 9 m)
    (%mj-check e m)
    (%mj-reserve! e m)
    e))

; The compiled engine when the lane builds it and it proves out, the pure
; one when not: the same answers either way, the pure one slower.
(def mont-jit-engine
  (fn (_ m) (guard (err (mont-jit-pure m)) (mont-jit-make m))))

(def mont-jit-compiled? (fn (_ e) (not (%mj-pure? e))))

; --- programs: a run of operations resolved once ----------------------------
;
; A caller that repeats one sequence of operations thousands of times -- a
; point doubling, an addition -- pays x's cost of a call per operation each
; time.  A program resolves the sequence once: each step (OP H F G), OP the
; compiled function itself (or, in a pure engine, a closure over mont.x's)
; and H F G what it is handed (word offsets, or slots).  mont-jit-run! then
; makes the calls directly: a compiled step is the native call and little
; else.  Steps are (mul h f g), (add h f g), (sub h f g) and (copy h f).

(def %mj-step
  (fn (_ e op h f g)
    (if (%mj-pure? e)
      (list (match ((eq? op (lit mul)) (fn (_ a h f g) (mont-jit-mul e h f g)))
                   ((eq? op (lit add)) (fn (_ a h f g) (mont-jit-add e h f g)))
                   ((eq? op (lit sub)) (fn (_ a h f g) (mont-jit-sub e h f g)))
                   (#t (fn (_ a h f g) (mont-jit-copy! e h f))))
            h f g)
      (list (%mj-oref e (match ((eq? op (lit mul)) 5) ((eq? op (lit add)) 6) ((eq? op (lit sub)) 7) (#t 10)))
            (%mj-off e h) (%mj-off e f) (if (null? g) 0 (%mj-off e g))))))

(def mont-jit-program
  (fn (_ e steps)
    (List map (fn (_ s) (%mj-step e (first s) (first (rest s)) (first (rest (rest s)))
                                  (if (null? (rest (rest (rest s)))) () (first (rest (rest (rest s)))))))
              steps)))

(def mont-jit-run!
  (fn (self e prog)
    (def a (%mj-oref e 3))
    ((fn (loop p)
       (unless (null? p)
         (do (def s (first p))
             (def r (rest s))
             ((first s) a (first r) (first (rest r)) (first (rest (rest r))))
             (loop (rest p)))))
     prog)))

(doc (provide x/codec/mont-jit mont-jit-engine mont-jit-make mont-jit-pure mont-jit-compiled? mont-jit-free mont-jit-n
              mont-jit-load! mont-jit-store mont-jit-copy! mont-jit-zero? mont-jit-eq?
              mont-jit-mul mont-jit-add mont-jit-sub mont-jit-to! mont-jit-from! mont-jit-one! mont-jit-inv!
              mont-jit-program mont-jit-run!)
  "Montgomery arithmetic for one modulus over named slots: (mont-jit-engine m) builds multiply, add and subtract compiled (JIT, ARM64 and x86-64 backends), checked against x/codec/mont's pure-x operations, or falls back to those; slots 0..mont-jit-free - 1 are the caller's.")
