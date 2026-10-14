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
;
; A modulus too long to unroll -- an RSA modulus is 79 or 158 limbs, and
; a row of its multiply alone is thousands of forms -- gets the LOOPING
; engine instead: eight functions generic over the modulus -- the six
; operations and the byte conversions in and out -- whose steps are tail
; self-calls, which the lane makes jumps.  The same eight serve every
; such modulus, so they are built once a machine.
(module x/codec/mont-jit)

(import x/tool/jit-group jit-group)
(import x/type/vector)
; A pure engine's inverse collects at fixed points, as mont-pow does.
(import x/sys/gc)
(import x/codec/mont mont-n mont-mul mont-add mont-sub mont-to mont-number mont-bytes mont-bytes-of mont-region mont-limbs mont-minus-two mont-r2 mont-r2-set? mont-set-r2!)

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

; --- the looping engine's functions ---------------------------------------
;
; Above %mj-unroll limbs the operations are loops, generic over the
; modulus.  The scratch opens with a HEADER of eight words -- n, the
; offsets of the row t, the trial difference d and the modulus's limbs p,
; then n', and two work words, a sum and the quotient digit -- and the
; slots follow it.  A loop's state rides its parameters: ph the phase, i
; the row, j the limb, c the carry and q the quotient digit; every step
; is a tail self-call.  The multiply is mont.x's CIOS in five phases:
; clear the row, add f_i g, add q m and shift, the trial subtraction, and
; the masked choice between the row and the difference, the last two
; shared with the add.  The lane has no locals, so a row's sum goes
; through the header's sum word on its way to the carry.

(def %mj-unroll 24)
(def %mj-hdr 8)
(def %ml-N (list (lit %mem-ref) (lit a) 0))
(def %ml-T (list (lit %mem-ref) (lit a) 1))
(def %ml-D (list (lit %mem-ref) (lit a) 2))
(def %ml-P (list (lit %mem-ref) (lit a) 3))
(def %ml-INV (list (lit %mem-ref) (lit a) 4))
(def %ml-S 5)
(def %ml-Q 6)
(def %ml-at (fn (_ base i) (list (lit %mem-ref-at) (lit a) (list (lit +) base i))))
(def %ml-set (fn (_ base i v) (list (lit %mem-set-at!) (lit a) (list (lit +) base i) v)))
(def %ml-sum (list (lit %mem-ref) (lit a) %ml-S))
(def %ml-sum! (fn (_ v) (list (lit %mem-set!) (lit a) %ml-S v)))
(def %ml-low (list (lit &) %ml-sum %M))
(def %ml-carry (list (lit >>) %ml-sum 26))
(def %ml-self (fn (_ ph i j c q) (list (lit self) (lit a) (lit h) (lit f) (lit g) ph i j c q)))

; Phases 3 and 4, from a row whose carry out of limb n-1 is in t[n]: d :=
; t - m, then h := t when that borrowed and t[n] is clear, else d.  The
; mask is the borrow, 0 or -1, plus t[n], carried in c through phase 4.
(def %ml-reduce
  (list (lit if) (list (lit =) (lit ph) 3)
    (list (lit if) (list (lit <) (lit j) %ml-N)
      (list (lit do)
        (%ml-sum! (list (lit +) (list (lit -) (%ml-at %ml-T (lit j)) (%ml-at %ml-P (lit j))) (lit c)))
        (%ml-set %ml-D (lit j) %ml-low)
        (%ml-self 3 0 (list (lit +) (lit j) 1) %ml-carry 0))
      (%ml-self 4 0 0 (list (lit +) (lit c) (%ml-at %ml-T %ml-N)) 0))
    (list (lit if) (list (lit <) (lit j) %ml-N)
      (list (lit do)
        (%ml-set (lit h) (lit j)
                 (list (lit ^) (%ml-at %ml-D (lit j))
                       (list (lit &) (list (lit ^) (%ml-at %ml-D (lit j)) (%ml-at %ml-T (lit j))) (lit c))))
        (%ml-self 4 0 (list (lit +) (lit j) 1) (lit c) 0))
      0)))

(def %ml-mul-expr
  (list (lit fn) (lit (self a h f g ph i j c q))
    (list (lit if) (list (lit =) (lit ph) 0)
      (list (lit if) (list (lit <) (lit j) (list (lit +) %ml-N 2))
        (list (lit do) (%ml-set %ml-T (lit j) 0) (%ml-self 0 0 (list (lit +) (lit j) 1) 0 0))
        (%ml-self 1 0 0 0 0))
    (list (lit if) (list (lit =) (lit ph) 1)
      ; t += f_i g
      (list (lit if) (list (lit <) (lit j) %ml-N)
        (list (lit do)
          (%ml-sum! (list (lit +) (list (lit +) (%ml-at %ml-T (lit j)) (list (lit *) (%ml-at (lit f) (lit i)) (%ml-at (lit g) (lit j)))) (lit c)))
          (%ml-set %ml-T (lit j) %ml-low)
          (%ml-self 1 (lit i) (list (lit +) (lit j) 1) %ml-carry 0))
        (list (lit do)
          (%ml-sum! (list (lit +) (%ml-at %ml-T %ml-N) (lit c)))
          (%ml-set %ml-T %ml-N %ml-low)
          (%ml-set %ml-T (list (lit +) %ml-N 1) %ml-carry)
          ; q clears the bottom limb
          (list (lit %mem-set!) (lit a) %ml-Q (list (lit &) (list (lit *) (%ml-at %ml-T 0) %ml-INV) %M))
          (%ml-self 2 (lit i) 1
                    (list (lit >>) (list (lit +) (%ml-at %ml-T 0) (list (lit *) (list (lit %mem-ref) (lit a) %ml-Q) (%ml-at %ml-P 0))) 26)
                    (list (lit %mem-ref) (lit a) %ml-Q))))
    (list (lit if) (list (lit =) (lit ph) 2)
      ; t = (t + q m) / 2^26
      (list (lit if) (list (lit <) (lit j) %ml-N)
        (list (lit do)
          (%ml-sum! (list (lit +) (list (lit +) (%ml-at %ml-T (lit j)) (list (lit *) (lit q) (%ml-at %ml-P (lit j)))) (lit c)))
          (%ml-set %ml-T (list (lit -) (lit j) 1) %ml-low)
          (%ml-self 2 (lit i) (list (lit +) (lit j) 1) %ml-carry (lit q)))
        (list (lit do)
          (%ml-sum! (list (lit +) (%ml-at %ml-T %ml-N) (lit c)))
          (%ml-set %ml-T (list (lit -) %ml-N 1) %ml-low)
          (%ml-set %ml-T %ml-N (list (lit +) (%ml-at %ml-T (list (lit +) %ml-N 1)) %ml-carry))
          (list (lit if) (list (lit <) (list (lit +) (lit i) 1) %ml-N)
            (%ml-self 1 (list (lit +) (lit i) 1) 0 0 0)
            (%ml-self 3 0 0 0 0))))
    %ml-reduce)))))

(def %ml-add-expr
  (list (lit fn) (lit (self a h f g ph i j c q))
    (list (lit if) (list (lit =) (lit ph) 0)
      (list (lit if) (list (lit <) (lit j) %ml-N)
        (list (lit do)
          (%ml-sum! (list (lit +) (list (lit +) (%ml-at (lit f) (lit j)) (%ml-at (lit g) (lit j))) (lit c)))
          (%ml-set %ml-T (lit j) %ml-low)
          (%ml-self 0 0 (list (lit +) (lit j) 1) %ml-carry 0))
        (list (lit do) (%ml-set %ml-T %ml-N (lit c)) (%ml-self 3 0 0 0 0)))
    %ml-reduce)))

; f - g, and m added back when that borrowed: the borrow, 0 or -1, rides
; i through the second phase and masks m in.
(def %ml-sub-expr
  (list (lit fn) (lit (self a h f g ph i j c q))
    (list (lit if) (list (lit =) (lit ph) 0)
      (list (lit if) (list (lit <) (lit j) %ml-N)
        (list (lit do)
          (%ml-sum! (list (lit +) (list (lit -) (%ml-at (lit f) (lit j)) (%ml-at (lit g) (lit j))) (lit c)))
          (%ml-set %ml-T (lit j) %ml-low)
          (%ml-self 0 0 (list (lit +) (lit j) 1) %ml-carry 0))
        (%ml-self 1 (lit c) 0 0 0))
      (list (lit if) (list (lit <) (lit j) %ml-N)
        (list (lit do)
          (%ml-sum! (list (lit +) (list (lit +) (%ml-at %ml-T (lit j)) (list (lit &) (%ml-at %ml-P (lit j)) (lit i))) (lit c)))
          (%ml-set (lit h) (lit j) %ml-low)
          (%ml-self 1 (lit i) (list (lit +) (lit j) 1) %ml-carry 0))
        0))))

(def %ml-copy-expr
  (list (lit fn) (lit (self a h f i))
    (list (lit if) (list (lit <) (lit i) %ml-N)
      (list (lit do) (%ml-set (lit h) (lit i) (%ml-at (lit f) (lit i)))
                     (list (lit self) (lit a) (lit h) (lit f) (list (lit +) (lit i) 1)))
      0)))

(def %ml-or-expr
  (list (lit fn) (lit (self a f i acc))
    (list (lit if) (list (lit <) (lit i) %ml-N)
      (list (lit self) (lit a) (lit f) (list (lit +) (lit i) 1) (list (lit |) (lit acc) (%ml-at (lit f) (lit i))))
      (lit acc))))

(def %ml-xor-or-expr
  (list (lit fn) (lit (self a f g i acc))
    (list (lit if) (list (lit <) (lit i) %ml-N)
      (list (lit self) (lit a) (lit f) (lit g) (list (lit +) (lit i) 1)
            (list (lit |) (lit acc) (list (lit ^) (%ml-at (lit f) (lit i)) (%ml-at (lit g) (lit i)))))
      (lit acc))))

; Big-endian bytes at address src, len of them, into the n limbs at h:
; mont.x's %from-be as a loop.  Phase 0 clears the limbs; then byte j
; from the end lands at bit 8j, in limb limb at bit off and, when it
; straddles, the next.  The byte rides the header's sum word.
(def %ml-byte (list (lit %mem-ref) (lit a) %ml-S))
(def %ml-from-be-expr
  (list (lit fn) (lit (self a h src len ph j limb off))
    (list (lit if) (list (lit =) (lit ph) 0)
      (list (lit if) (list (lit <) (lit j) %ml-N)
        (list (lit do) (%ml-set (lit h) (lit j) 0) (list (lit self) (lit a) (lit h) (lit src) (lit len) 0 (list (lit +) (lit j) 1) 0 0))
        (list (lit self) (lit a) (lit h) (lit src) (lit len) 1 0 0 0))
      (list (lit if) (list (lit <) (lit j) (lit len))
        (list (lit do)
          (%ml-sum! (list (lit %mem-byte-ref-at) (lit src) (list (lit -) (list (lit -) (lit len) 1) (lit j))))
          (list (lit if) (list (lit <) (lit limb) %ml-N)
            (%ml-set (lit h) (lit limb) (list (lit |) (%ml-at (lit h) (lit limb)) (list (lit &) (list (lit <<) %ml-byte (lit off)) %M)))
            0)
          (list (lit if) (list (lit if) (list (lit >) (lit off) 18) (list (lit <) (list (lit +) (lit limb) 1) %ml-N) 0)
            (%ml-set (lit h) (list (lit +) (lit limb) 1)
                     (list (lit |) (%ml-at (lit h) (list (lit +) (lit limb) 1)) (list (lit >>) %ml-byte (list (lit -) 26 (lit off)))))
            0)
          (list (lit if) (list (lit >=) (list (lit +) (lit off) 8) 26)
            (list (lit self) (lit a) (lit h) (lit src) (lit len) 1 (list (lit +) (lit j) 1) (list (lit +) (lit limb) 1) (list (lit -) (list (lit +) (lit off) 8) 26))
            (list (lit self) (lit a) (lit h) (lit src) (lit len) 1 (list (lit +) (lit j) 1) (lit limb) (list (lit +) (lit off) 8))))
        0))))

; The n limbs at f as len big-endian bytes at address dst: mont.x's %to-be
; as a loop.  Each byte gathers from the limb holding its low bit and,
; when it straddles, the next.
(def %ml-to-be-expr
  (list (lit fn) (lit (self a f dst len j limb off))
    (list (lit if) (list (lit <) (lit j) (lit len))
      (list (lit do)
        (list (lit %mem-byte-set-at!) (lit dst) (list (lit -) (list (lit -) (lit len) 1) (lit j))
          (list (lit &)
            (list (lit |)
              (list (lit if) (list (lit <) (lit limb) %ml-N) (list (lit >>) (%ml-at (lit f) (lit limb)) (lit off)) 0)
              (list (lit if) (list (lit if) (list (lit >) (lit off) 18) (list (lit <) (list (lit +) (lit limb) 1) %ml-N) 0)
                (list (lit <<) (%ml-at (lit f) (list (lit +) (lit limb) 1)) (list (lit -) 26 (lit off)))
                0))
            255))
        (list (lit if) (list (lit >=) (list (lit +) (lit off) 8) 26)
          (list (lit self) (lit a) (lit f) (lit dst) (lit len) (list (lit +) (lit j) 1) (list (lit +) (lit limb) 1) (list (lit -) (list (lit +) (lit off) 8) 26))
          (list (lit self) (lit a) (lit f) (lit dst) (lit len) (list (lit +) (lit j) 1) (lit limb) (list (lit +) (lit off) 8))))
      0)))

; The eight, compiled once a process and poured from the cache after the
; first machine that built them: (FNS . REPLAYED?), or () until asked.
; The key counts them: a poured group is whatever was stored under its
; key, so a group that grows must change its name.
(def %ml-fns (pair () ()))
(def %ml-compiled
  (fn (_)
    (when (null? (first %ml-fns))
      (jit-group "mont-jit-loop:8"
        (fn (_) (list %ml-mul-expr %ml-add-expr %ml-sub-expr %ml-copy-expr %ml-or-expr %ml-xor-or-expr %ml-from-be-expr %ml-to-be-expr))
        (fn (_ fns replayed?) (%set-first! %ml-fns (pair fns replayed?)))))
    (first %ml-fns)))

; The address of byte start of string s.
(def %ml-address (fn (_ s start) (+ (%mj-ptr->int (%mj-str->ptr s)) start)))

; --- the engine -----------------------------------------------------------
;
; A vector of (STORE PTR ADDR N MUL ADD SUB KIND M COPY OR XOR-OR BASE
; FROM-BE TO-BE).  A COMPILED engine's numbers are slots of n words in
; its scratch STORE from word BASE, and MUL, ADD and SUB are the compiled
; functions -- or, in a looping engine, closures handing them their
; state's first values, with FROM-BE and TO-BE the byte conversions,
; which only it has; a PURE engine's are limb vectors in a vector STORE,
; and its operations mont.x's.  Callers name slots 0..%mj-free - 1; the
; slots above hold R^2, a plain one and R mod m for entering and leaving
; the form, and a power's working values.

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
(def %mj-off (fn (_ e k) (+ (%mj-oref e 13) (* k (mont-jit-n e)))))

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

; Slot k from big-endian bytes, a number below m out of the form, and a
; slot as the modulus's length of big-endian bytes: compiled in a looping
; engine, where a limb vector in between is tens of thousands of objects;
; through mont.x's conversions elsewhere.
(def mont-jit-load-bytes!
  (fn (_ e k s start len)
    (if (null? (%mj-oref e 14))
      (mont-jit-load! e k (mont-number (%mj-m e) s start len))
      ((%mj-oref e 14) (%mj-oref e 3) (%mj-off e k) (%ml-address s start) len))))

(def mont-jit-store-bytes
  (fn (_ e k)
    (def m (%mj-m e))
    (if (null? (%mj-oref e 15))
      (mont-bytes-of m (mont-jit-store e k))
      (do (def len (mont-bytes m))
          (def out (%mj-make-str (if (> len 0) len 1)))
          ((%mj-oref e 15) (%mj-oref e 3) (%mj-off e k) (%ml-address out 0) len)
          out))))

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

; h = f^x in the form, x the big-endian bytes at s[start, start + len):
; square and multiply from the top bit down, on the engine's own working
; slots.
(def mont-jit-pow!
  (fn (_ e h f s start len)
    (mont-jit-copy! e %mj-base f)
    (mont-jit-copy! e %mj-acc %mj-r)
    ((fn (self j)
       (unless (= j len)
         (do ; a pure engine's multiplies leave thousands of objects each
             (when (and (%mj-pure? e) (= (& j 3) 0)) (Heap collect))
             (def b (%mj-char->int (%mj-byte-ref s (+ start j))))
             ((fn (self k)
                (unless (< k 0)
                  (do (mont-jit-mul e %mj-acc %mj-acc %mj-acc)
                      (when (= (& (>> b k) 1) 1) (mont-jit-mul e %mj-acc %mj-acc %mj-base))
                      (self (- k 1)))))
              7)
             (self (+ j 1)))))
     0)
    (mont-jit-copy! e h %mj-acc)))

; h = f^-1 in the form, m prime: f^(m-2) (Fermat).
(def mont-jit-inv!
  (fn (_ e h f)
    (def m (%mj-m e))
    (mont-jit-pow! e h f (mont-minus-two m) 0 (mont-bytes m))))

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
    (%try "sub" mont-jit-sub mont-sub x x)
    ; the byte conversions, where the engine has them: in from the bytes
    ; of a number below m, out to the modulus's length of bytes
    (unless (null? (%mj-oref e 14))
      (do (def bytes (mont-bytes-of m x))
          (mont-jit-load-bytes! e 0 bytes 0 len)
          (unless (%mj-same? (mont-jit-store e 0) x n)
            (Err raise 'state "mont-jit: the byte reader disagrees with the pure-x conversion" ()))
          (mont-jit-load! e 1 top)
          (unless (%mj-same-bytes? (mont-jit-store-bytes e 1) (mont-bytes-of m top) len)
            (Err raise 'state "mont-jit: the byte writer disagrees with the pure-x conversion" ()))))))

(def %mj-same-bytes?
  (fn (_ a b len)
    ((fn (self i) (if (= i len) #t (if (= (%mj-char->int (%mj-byte-ref a i)) (%mj-char->int (%mj-byte-ref b i))) (self (+ i 1)) #f))) 0)))

; The slots for entering and leaving the form: a plain one, R^2 mod m,
; and R mod m, which is the one times R^2 through the engine's own
; multiply.  A compiled engine makes R^2 itself (%mj-r2!) and its one by
; clearing a slot (a number less itself) and setting a word; a pure one
; loads limb vectors, R^2 mont.x's.
(def %mj-reserve!
  (fn (_ e m)
    (if (%mj-pure? e)
      (do (def one (Vector make (mont-n m) 0))
          (%mj-oset! one 1 1)
          (mont-jit-load! e %mj-plain-one one)
          (mont-jit-load! e %mj-r2 (mont-r2 m)))
      (do (mont-jit-sub e %mj-plain-one %mj-plain-one %mj-plain-one)
          (%mj-word-set! e %mj-plain-one 0 1)
          (%mj-r2! e m)
          ; mont.x's side takes the engine's R^2 rather than doubling its
          ; way there: the check needs it, and a pure engine on an RSA
          ; modulus would be minutes without it
          (unless (mont-r2-set? m) (mont-set-r2! m (mont-jit-store e %mj-r2)))))
    (mont-jit-mul e %mj-r %mj-plain-one %mj-r2)))

(def %mj-engine
  (fn (_ m)
    (def e (Vector make 16 ()))
    (%mj-oset! e 4 (mont-n m))
    (%mj-oset! e 9 m)
    (%mj-oset! e 13 0)
    e))

; A pure engine: the same slots and calls, mont.x's arithmetic beneath.
(def mont-jit-pure
  (fn (_ m)
    (def e (%mj-engine m))
    (%mj-oset! e 1 (Vector make %mj-slots ()))
    (%mj-oset! e 8 (lit pure))
    (%mj-reserve! e m)
    e))

; The scratch of WORDS 64-bit words, the engine pointed at it.
(def %mj-scratch!
  (fn (_ e words)
    (def buf (%mj-make-str (* words 8)))
    (def ptr (%mj-str->ptr buf))
    (%mj-oset! e 1 buf)
    (%mj-oset! e 2 ptr)
    (%mj-oset! e 3 (%mj-ptr->int ptr))))

(def %mj-wire!
  (fn (_ e mul add sub copy any differ)
    (%mj-oset! e 5 mul)
    (%mj-oset! e 6 add)
    (%mj-oset! e 7 sub)
    (%mj-oset! e 10 copy)
    (%mj-oset! e 11 any)
    (%mj-oset! e 12 differ)
    (%mj-oset! e 8 (lit compiled))))

; The compiled engine for modulus m: its scratch of %mj-slots numbers and
; the three compiled operations, built and checked against mont.x.  Raises
; when the lane cannot build them or they disagree.
(def mont-jit-make
  (fn (_ m)
    (if (> (mont-n m) %mj-unroll) (%mj-make-looping m) (%mj-make-unrolled m))))

(def %mj-make-unrolled
  (fn (_ m)
    (def n (mont-n m))
    (def limbs (mont-limbs m))
    (def ps ((fn (self i acc) (if (< i 0) acc (self (- i 1) (pair (%mj-oref limbs (+ i 1)) acc)))) (- n 1) ()))
    (def inv (%mj-oref m 3))
    (def w (* %mj-slots n))
    (def lay (%mj-layout n w))
    (def T (List ref 0 lay)) (def D (List ref 1 lay)) (def S (List ref 2 lay)) (def C (List ref 3 lay)) (def Q (List ref 4 lay))
    (def e (%mj-engine m))
    (%mj-scratch! e (+ Q 1))
    ; the six functions as one cache group, keyed by the modulus's limbs:
    ; a later process pours them with no expression generated or printed,
    ; and skips the check, which passed on these bytes when they were stored
    (jit-group (Str8 append "mont-jit:" (Str8 join "." (List map (fn (_ p) (Str8 str p)) ps)))
      (fn (_)
        (list (%mj-mul-expr n ps inv T D S C Q) (%mj-add-expr n ps T D S C) (%mj-sub-expr n ps T D S C)
              (%mj-copy-expr n) (%mj-or-expr n) (%mj-xor-or-expr n)))
      (fn (_ fns replayed?)
        (%mj-wire! e (List ref 0 fns) (List ref 1 fns) (List ref 2 fns) (List ref 3 fns) (List ref 4 fns) (List ref 5 fns))
        (%mj-reserve! e m)
        (unless replayed? (%mj-check e m))
        e))))

; The looping engine: the header, then the slots, the row, the difference
; and the modulus's limbs, and the eight generic functions behind closures
; that start each loop's state.  The check runs once a process, on the
; first modulus that builds the functions rather than pouring them.
(def %mj-make-looping
  (fn (_ m)
    (def n (mont-n m))
    (def e (%mj-engine m))
    (%mj-oset! e 13 %mj-hdr)
    (def T (+ %mj-hdr (* %mj-slots n)))
    (def D (+ T n 2))
    (def P (+ D n))
    (%mj-scratch! e (+ P n))
    (def ptr (%mj-oref e 2))
    (def word! (fn (_ i v) (%mj-pset ptr (* i 8) v)))
    (word! 0 n) (word! 1 T) (word! 2 D) (word! 3 P) (word! 4 (%mj-oref m 3))
    (def fresh (null? (first %ml-fns)))
    (def built (%ml-compiled))
    (def fns (first built))
    (def mul (List ref 0 fns)) (def add (List ref 1 fns)) (def sub (List ref 2 fns))
    (def copy (List ref 3 fns)) (def any (List ref 4 fns)) (def differ (List ref 5 fns))
    (def from-be (List ref 6 fns)) (def to-be (List ref 7 fns))
    (%mj-wire! e
      (fn (_ a h f g) (mul a h f g 0 0 0 0 0))
      (fn (_ a h f g) (add a h f g 0 0 0 0 0))
      (fn (_ a h f g) (sub a h f g 0 0 0 0 0))
      (fn (_ a h f) (copy a h f 0))
      (fn (_ a f) (any a f 0 0))
      (fn (_ a f g) (differ a f g 0 0)))
    (%mj-oset! e 14 (fn (_ a h src len) (from-be a h src len 0 0 0 0)))
    (%mj-oset! e 15 (fn (_ a f dst len) (to-be a f dst len 0 0 0)))
    ; the modulus's limbs, read from its bytes by the engine itself
    (def r (mont-region m))
    ((%mj-oref e 14) (%mj-oref e 3) P (%ml-address (first r) (first (rest r))) (first (rest (rest r))))
    (%mj-reserve! e m)
    (when (and fresh (not (rest built))) (%mj-check e m))
    e))

; R^2 mod m into its slot, by the engine.  2^(26(n-2)) is below m (m's
; top byte is nonzero, and 26n is within 26 of its bit length), so 52
; doublings of it reach R mod m, the form's one; then with t_k = 2^(26n +
; k) mod m, the engine's multiply takes t_a and t_b to t_(a+b), and a
; square-and-multiply ladder over 26n itself climbs from t_0 and t_1 to
; t_26n = R^2 in some fifty multiplies.  mont.x's own pure-x doubling
; loop is two hundred milliseconds for P-256's prime and minutes for an
; RSA modulus.  The slot is cleared as a number less itself.
(def %mj-r2!
  (fn (_ e m)
    (def n (mont-n m))
    (def k0 (if (> n 2) (- n 2) 0))
    (mont-jit-sub e %mj-r2 %mj-r2 %mj-r2)
    (%mj-word-set! e %mj-r2 k0 1)
    ((fn (self k)
       (unless (= k 0)
         (do (mont-jit-add e %mj-r2 %mj-r2 %mj-r2) (self (- k 1)))))
     (* 26 (- n k0)))
    (mont-jit-add e %mj-base %mj-r2 %mj-r2)
    (def s (* 26 n))
    ((fn (self k)
       (unless (< k 0)
         (do (mont-jit-mul e %mj-r2 %mj-r2 %mj-r2)
             (when (= (& (>> s k) 1) 1) (mont-jit-mul e %mj-r2 %mj-r2 %mj-base))
             (self (- k 1)))))
     ((fn (self k) (if (= (>> s (+ k 1)) 0) k (self (+ k 1)))) 0))))

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
              mont-jit-load-bytes! mont-jit-store-bytes
              mont-jit-mul mont-jit-add mont-jit-sub mont-jit-to! mont-jit-from! mont-jit-one! mont-jit-pow! mont-jit-inv!
              mont-jit-program mont-jit-run!)
  "Montgomery arithmetic for one modulus over named slots: (mont-jit-engine m) builds multiply, add and subtract compiled (JIT, ARM64 and x86-64 backends), unrolled for a curve's modulus and as loops generic over the modulus for RSA's, checked against x/codec/mont's pure-x operations, or falls back to those; slots 0..mont-jit-free - 1 are the caller's.")
