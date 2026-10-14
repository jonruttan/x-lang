; mont-jit.x -- Montgomery arithmetic compiled, for any odd modulus.
;
; Loaded lazily, as the other engines are: this module pulls the JIT
; toolchain.  For a modulus x/codec/mont built, the engine is a scratch of
; 64-bit words -- a header, SLOTS numbers of n limbs each, the row and the
; difference a multiply works in, the modulus's limbs, and a table of
; PROGRAMS -- and five compiled functions generic over the modulus, built
; once a machine and poured by every process after: the RUNNER, which
; executes a program of multiplies, adds, subtracts and copies mod m from
; the table in one call; the byte conversions in and out; and the zero
; and equality tests.  Every step of a loop is a tail self-call, which the
; lane makes a jump, and the state rides the parameters.  The multiply is
; mont.x's CIOS: a row of f_i g, then a row of q m with q clearing the
; bottom limb, shifted down a limb; the last step of multiply and add,
; subtracting m when the value reached it, is branch-free: the borrow of
; the trial subtraction, 0 or -1 by the lane's arithmetic shift, masks
; which of the two results is written.  The engine is adopted only after
; it agrees with mont.x's pure-x operations, limb for limb.
;
; A single operation is a one-step program; a caller that repeats a
; sequence thousands of times -- a point doubling -- writes it to the
; table once (mont-jit-program) and runs it in one call (mont-jit-run!),
; where a call an operation was fifteen microseconds of x each.
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

; --- the scratch's shape ---------------------------------------------------
;
; Words 0-7 are the header: n; the offsets of the row t (n + 2 words), the
; trial difference d (n words), the modulus's limbs p (n words) and the
; program table; n'; and two work words, a sum and the quotient digit --
; the lane has no locals.  The slots follow the header, the work areas
; the slots, the table last.

(def %mj-hdr 8)
(def %mj-slots 48)
(def %mj-table 1024)
(def mont-jit-free 42)
(def %mj-acc 42)
(def %mj-base 43)
(def %mj-r 44)
(def %mj-plain-one 45)
(def %mj-r2 46)

; Program table entries are four words, op h f g; op 0 ends a program.
(def %op-mul 1)
(def %op-add 2)
(def %op-sub 3)
(def %op-copy 4)

; --- expression builders (generation time) ---------------------------------

(def %ml-N (list (lit %mem-ref) (lit a) 0))
(def %ml-T (list (lit %mem-ref) (lit a) 1))
(def %ml-D (list (lit %mem-ref) (lit a) 2))
(def %ml-P (list (lit %mem-ref) (lit a) 3))
(def %ml-INV (list (lit %mem-ref) (lit a) 4))
(def %ml-S 5)
(def %ml-Q 6)
(def %ml-TBL (list (lit %mem-ref) (lit a) 7))
(def %ml-at (fn (_ base i) (list (lit %mem-ref-at) (lit a) (list (lit +) base i))))
(def %ml-set (fn (_ base i v) (list (lit %mem-set-at!) (lit a) (list (lit +) base i) v)))
(def %ml-sum (list (lit %mem-ref) (lit a) %ml-S))
(def %ml-sum! (fn (_ v) (list (lit %mem-set!) (lit a) %ml-S v)))
(def %ml-low (list (lit &) %ml-sum %M))
(def %ml-carry (list (lit >>) %ml-sum 26))

; The runner's state: pc the step, ph the phase, i the row, j the limb,
; c the carry, q the quotient digit, h f g the step's offsets.
(def %ml-self (fn (_ ph i j c q) (list (lit self) (lit a) (lit pc) ph i j c q (lit h) (lit f) (lit g))))
; word k of the step at pc
(def %ml-step (fn (_ k) (list (lit %mem-ref-at) (lit a) (list (lit +) %ml-TBL (list (lit +) (list (lit <<) (lit pc) 2) k)))))
; on to the next step, and into phase ph of this one with its offsets
(def %ml-next (list (lit self) (lit a) (list (lit +) (lit pc) 1) 9 0 0 0 0 0 0 0))
(def %ml-begin (fn (_ ph) (list (lit self) (lit a) (lit pc) ph 0 0 0 0 (%ml-step 1) (%ml-step 2) (%ml-step 3))))

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
      %ml-next)))

; The multiply's phases: 0 clears the row; 1 adds f_i g; 2 adds q m and
; shifts the row down a limb, then the next row or the reduction.
(def %ml-mul
  (list (lit if) (list (lit =) (lit ph) 1)
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
  (list (lit if) (list (lit =) (lit ph) 0)
    (list (lit if) (list (lit <) (lit j) (list (lit +) %ml-N 2))
      (list (lit do) (%ml-set %ml-T (lit j) 0) (%ml-self 0 0 (list (lit +) (lit j) 1) 0 0))
      (%ml-self 1 0 0 0 0))
    %ml-reduce))))

; Phase 10: f + g into the row, its carry in t[n], then the reduction.
(def %ml-add
  (list (lit if) (list (lit <) (lit j) %ml-N)
    (list (lit do)
      (%ml-sum! (list (lit +) (list (lit +) (%ml-at (lit f) (lit j)) (%ml-at (lit g) (lit j))) (lit c)))
      (%ml-set %ml-T (lit j) %ml-low)
      (%ml-self 10 0 (list (lit +) (lit j) 1) %ml-carry 0))
    (list (lit do) (%ml-set %ml-T %ml-N (lit c)) (%ml-self 3 0 0 0 0))))

; Phases 11 and 12: f - g into the row, and m added back when that
; borrowed: the borrow, 0 or -1, rides i through phase 12 and masks m in.
(def %ml-sub
  (list (lit if) (list (lit =) (lit ph) 11)
    (list (lit if) (list (lit <) (lit j) %ml-N)
      (list (lit do)
        (%ml-sum! (list (lit +) (list (lit -) (%ml-at (lit f) (lit j)) (%ml-at (lit g) (lit j))) (lit c)))
        (%ml-set %ml-T (lit j) %ml-low)
        (%ml-self 11 0 (list (lit +) (lit j) 1) %ml-carry 0))
      (%ml-self 12 (lit c) 0 0 0))
    (list (lit if) (list (lit <) (lit j) %ml-N)
      (list (lit do)
        (%ml-sum! (list (lit +) (list (lit +) (%ml-at %ml-T (lit j)) (list (lit &) (%ml-at %ml-P (lit j)) (lit i))) (lit c)))
        (%ml-set (lit h) (lit j) %ml-low)
        (%ml-self 12 (lit i) (list (lit +) (lit j) 1) %ml-carry 0))
      %ml-next)))

; Phase 13: h := f, word for word.
(def %ml-copy
  (list (lit if) (list (lit <) (lit j) %ml-N)
    (list (lit do) (%ml-set (lit h) (lit j) (%ml-at (lit f) (lit j))) (%ml-self 13 0 (list (lit +) (lit j) 1) 0 0))
    %ml-next))

; Phase 9: the step at pc, dispatched by its op; op 0 ends the program.
(def %ml-fetch
  (list (lit if) (list (lit =) (%ml-step 0) 0) 0
    (list (lit if) (list (lit =) (%ml-step 0) %op-mul) (%ml-begin 0)
      (list (lit if) (list (lit =) (%ml-step 0) %op-add) (%ml-begin 10)
        (list (lit if) (list (lit =) (%ml-step 0) %op-sub) (%ml-begin 11)
          (%ml-begin 13))))))

; The runner: (run a pc 9 0 0 0 0 0 0 0) executes the program at step pc.
; The multiply's inner phases are tested first: they are where the time
; goes.
(def %ml-run-expr
  (list (lit fn) (lit (self a pc ph i j c q h f g))
    (list (lit if) (list (lit <) (lit ph) 5) %ml-mul
      (list (lit if) (list (lit =) (lit ph) 9) %ml-fetch
        (list (lit if) (list (lit =) (lit ph) 10) %ml-add
          (list (lit if) (list (lit <) (lit ph) 13) %ml-sub
            %ml-copy))))))

; The OR of f's limbs: zero exactly when f is.
(def %ml-or-expr
  (list (lit fn) (lit (self a f i acc))
    (list (lit if) (list (lit <) (lit i) %ml-N)
      (list (lit self) (lit a) (lit f) (list (lit +) (lit i) 1) (list (lit |) (lit acc) (%ml-at (lit f) (lit i))))
      (lit acc))))

; The OR of the limbs' XORs: zero exactly when f = g.
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

; The five, compiled once a process and poured from the cache after the
; first machine that built them: (FNS . REPLAYED?), or () until asked.
; The key counts them: a poured group is whatever was stored under its
; key, so a group that changes must change its name.
(def %ml-fns (pair () ()))
(def %ml-compiled
  (fn (_)
    (when (null? (first %ml-fns))
      (jit-group "mont-jit-run:5"
        (fn (_) (list %ml-run-expr %ml-or-expr %ml-xor-or-expr %ml-from-be-expr %ml-to-be-expr))
        (fn (_ fns replayed?) (%set-first! %ml-fns (pair fns replayed?)))))
    (first %ml-fns)))

; The address of byte start of string s.
(def %ml-address (fn (_ s start) (+ (%mj-ptr->int (%mj-str->ptr s)) start)))

; --- the engine -----------------------------------------------------------
;
; A vector of (STORE PTR ADDR N RUN OR XOR-OR KIND M FROM-BE TO-BE CURSOR
; BASE TABLE END).  A COMPILED engine's numbers are slots of n words in
; its scratch STORE from word BASE, RUN the runner and the rest the other
; four functions, TABLE the program table's first word and CURSOR the
; next free one; a PURE engine's numbers are limb vectors in a vector
; STORE, and its operations mont.x's.  Callers name slots
; 0..mont-jit-free - 1; the slots above hold R^2, a plain one and R mod m
; for entering and leaving the form, and a power's working values.

(def mont-jit-n (fn (_ e) (%mj-oref e 4)))
(def %mj-pure? (fn (_ e) (eq? (%mj-oref e 8) (lit pure))))
(def %mj-m (fn (_ e) (%mj-oref e 9)))

; Slot k's word offset, in a compiled engine.
(def %mj-off (fn (_ e k) (+ (%mj-oref e 13) (* k (mont-jit-n e)))))

(def %mj-word-ref (fn (_ e k i) (%mj-pref (%mj-oref e 2) (* (+ (%mj-off e k) i) 8))))
(def %mj-word-set! (fn (_ e k i v) (%mj-pset (%mj-oref e 2) (* (+ (%mj-off e k) i) 8) v)))
(def %mj-word! (fn (_ e w v) (%mj-pset (%mj-oref e 2) (* w 8) v)))

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
; slot as the modulus's length of big-endian bytes: compiled in a compiled
; engine, where a limb vector in between is tens of thousands of objects;
; through mont.x's conversions in a pure one.
(def mont-jit-load-bytes!
  (fn (_ e k s start len)
    (if (%mj-pure? e)
      (mont-jit-load! e k (mont-number (%mj-m e) s start len))
      ((%mj-oref e 10) (%mj-oref e 3) (%mj-off e k) (%ml-address s start) len 0 0 0 0))))

(def mont-jit-store-bytes
  (fn (_ e k)
    (def m (%mj-m e))
    (if (%mj-pure? e)
      (mont-bytes-of m (mont-jit-store e k))
      (do (def len (mont-bytes m))
          (def out (%mj-make-str (if (> len 0) len 1)))
          ((%mj-oref e 11) (%mj-oref e 3) (%mj-off e k) (%ml-address out 0) len 0 0 0)
          out))))

; One operation: a one-step program at the table's first entry, run.
(def %mj-step!
  (fn (_ e op h f g)
    (def t (%mj-oref e 14))
    (%mj-word! e t op)
    (%mj-word! e (+ t 1) (%mj-off e h))
    (%mj-word! e (+ t 2) (%mj-off e f))
    (%mj-word! e (+ t 3) (%mj-off e g))
    ((%mj-oref e 5) (%mj-oref e 3) 0 9 0 0 0 0 0 0 0)))

(def %mj-op
  (fn (_ e op pure h f g)
    (if (%mj-pure? e)
      (mont-jit-load! e h (pure (%mj-m e) (mont-jit-store e f) (mont-jit-store e g)))
      (%mj-step! e op h f g))))

(def mont-jit-mul (fn (_ e h f g) (%mj-op e %op-mul mont-mul h f g)))
(def mont-jit-add (fn (_ e h f g) (%mj-op e %op-add mont-add h f g)))
(def mont-jit-sub (fn (_ e h f g) (%mj-op e %op-sub mont-sub h f g)))

(def mont-jit-copy!
  (fn (_ e to from)
    (if (%mj-pure? e)
      (mont-jit-load! e to (mont-jit-store e from))
      (%mj-step! e %op-copy to from from))))

; The zero test and equality: compiled in a compiled engine, since a word
; at a time through x is thousands of objects a call; vectors in a pure one.
(def mont-jit-zero?
  (fn (_ e k)
    (if (%mj-pure? e)
      (do (def n (mont-jit-n e))
          (def v (mont-jit-store e k))
          ((fn (self i) (if (> i n) #t (if (= (%mj-oref v i) 0) (self (+ i 1)) #f))) 1))
      (= 0 ((%mj-oref e 6) (%mj-oref e 3) (%mj-off e k) 0 0)))))

(def mont-jit-eq?
  (fn (_ e k l)
    (if (%mj-pure? e)
      (do (def n (mont-jit-n e))
          (def a (mont-jit-store e k))
          (def b (mont-jit-store e l))
          ((fn (self i) (if (> i n) #t (if (= (%mj-oref a i) (%mj-oref b i)) (self (+ i 1)) #f))) 1))
      (= 0 ((%mj-oref e 7) (%mj-oref e 3) (%mj-off e k) (%mj-off e l) 0 0)))))

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

(def %mj-same-bytes?
  (fn (_ a b len)
    ((fn (self i) (if (= i len) #t (if (= (%mj-char->int (%mj-byte-ref a i)) (%mj-char->int (%mj-byte-ref b i))) (self (+ i 1)) #f))) 0)))

; The differential check: each operation against mont.x's on numbers with
; every limb in use, and near the top of the range, where the final
; subtraction decides; then a program of them, and the byte doors.
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
    ; a program: (x y - x) x + y, against the same by single steps
    (mont-jit-load! e 0 x) (mont-jit-load! e 1 y)
    (mont-jit-run! e (mont-jit-program e (list (list (lit mul) 2 0 1) (list (lit sub) 2 2 0) (list (lit mul) 2 2 0) (list (lit add) 2 2 1) (list (lit copy) 3 2))))
    (unless (%mj-same? (mont-jit-store e 3) (mont-add m (mont-mul m (mont-sub m (mont-mul m x y) x) x) y) n)
      (Err raise 'state "mont-jit: a program disagrees with its steps" ()))
    (unless (%mj-pure? e)
      (do (def bytes (mont-bytes-of m x))
          (mont-jit-load-bytes! e 0 bytes 0 len)
          (unless (%mj-same? (mont-jit-store e 0) x n)
            (Err raise 'state "mont-jit: the byte reader disagrees with the pure-x conversion" ()))
          (mont-jit-load! e 1 top)
          (unless (%mj-same-bytes? (mont-jit-store-bytes e 1) (mont-bytes-of m top) len)
            (Err raise 'state "mont-jit: the byte writer disagrees with the pure-x conversion" ()))))))

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

; The compiled engine for modulus m: its scratch, the header written, the
; modulus's limbs read into it by the engine itself, and the five
; functions wired.  The check runs once a process, on the first modulus
; that builds the functions rather than pouring them.  Raises when the
; lane cannot build them or they disagree.
(def mont-jit-make
  (fn (_ m)
    (def n (mont-n m))
    (def e (%mj-engine m))
    (%mj-oset! e 13 %mj-hdr)
    (def T (+ %mj-hdr (* %mj-slots n)))
    (def D (+ T n 2))
    (def P (+ D n))
    (def TBL (+ P n))
    (def words (+ TBL %mj-table))
    (def buf (%mj-make-str (* words 8)))
    (def ptr (%mj-str->ptr buf))
    (%mj-oset! e 1 buf)
    (%mj-oset! e 2 ptr)
    (%mj-oset! e 3 (%mj-ptr->int ptr))
    (%mj-word! e 0 n) (%mj-word! e 1 T) (%mj-word! e 2 D) (%mj-word! e 3 P) (%mj-word! e 4 (%mj-oref m 3)) (%mj-word! e 7 TBL)
    (%mj-word! e (+ TBL 4) 0)
    (%mj-oset! e 14 TBL)
    (%mj-oset! e 12 (+ TBL 8))
    (%mj-oset! e 15 words)
    (def fresh (null? (first %ml-fns)))
    (def built (%ml-compiled))
    (def fns (first built))
    (%mj-oset! e 5 (List ref 0 fns))
    (%mj-oset! e 6 (List ref 1 fns))
    (%mj-oset! e 7 (List ref 2 fns))
    (%mj-oset! e 10 (List ref 3 fns))
    (%mj-oset! e 11 (List ref 4 fns))
    (%mj-oset! e 8 (lit compiled))
    ; the modulus's limbs, read from its bytes by the engine itself
    (def r (mont-region m))
    ((%mj-oref e 10) (%mj-oref e 3) P (%ml-address (first r) (first (rest r))) (first (rest (rest r))) 0 0 0 0)
    (%mj-reserve! e m)
    (when (and fresh (not (rest built))) (%mj-check e m))
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
; time.  In a compiled engine a program is written to the table once, as
; (OP H F G) words with H F G word offsets, and the runner executes it in
; one call; in a pure engine it is a list of closures over mont.x's
; operations, called in turn.  Steps are (mul h f g), (add h f g),
; (sub h f g) and (copy h f).

(def %mj-opcode
  (fn (_ op)
    (match ((eq? op (lit mul)) %op-mul) ((eq? op (lit add)) %op-add) ((eq? op (lit sub)) %op-sub) (#t %op-copy))))

(def %mj-step
  (fn (_ e op h f g)
    (list (match ((eq? op (lit mul)) (fn (_ a h f g) (mont-jit-mul e h f g)))
                 ((eq? op (lit add)) (fn (_ a h f g) (mont-jit-add e h f g)))
                 ((eq? op (lit sub)) (fn (_ a h f g) (mont-jit-sub e h f g)))
                 (#t (fn (_ a h f g) (mont-jit-copy! e h f))))
          h f g)))

(def mont-jit-program
  (fn (_ e steps)
    (def parts (fn (_ s) (list (first s) (first (rest s)) (first (rest (rest s)))
                               (if (null? (rest (rest (rest s)))) (first (rest (rest s))) (first (rest (rest (rest s))))))))
    (if (%mj-pure? e)
      (List map (fn (_ s) (do (def p (parts s)) (%mj-step e (first p) (List ref 1 p) (List ref 2 p) (List ref 3 p)))) steps)
      (do (def at (%mj-oref e 12))
          (def end (+ at (* 4 (+ (List length steps) 1))))
          (when (> end (%mj-oref e 15))
            (Err raise (lit state) "mont-jit: the engine's program table is full" (List length steps)))
          ((fn (self ss w)
             (if (null? ss) (%mj-word! e w 0)
               (do (def p (parts (first ss)))
                   (%mj-word! e w (%mj-opcode (first p)))
                   (%mj-word! e (+ w 1) (%mj-off e (List ref 1 p)))
                   (%mj-word! e (+ w 2) (%mj-off e (List ref 2 p)))
                   (%mj-word! e (+ w 3) (%mj-off e (List ref 3 p)))
                   (self (rest ss) (+ w 4)))))
           steps at)
          (%mj-oset! e 12 end)
          (>> (- at (%mj-oref e 14)) 2)))))

(def mont-jit-run!
  (fn (self e prog)
    (if (%mj-pure? e)
      ((fn (loop p)
         (unless (null? p)
           (do (def s (first p))
               (def r (rest s))
               ((first s) () (first r) (first (rest r)) (first (rest (rest r))))
               (loop (rest p)))))
       prog)
      ((%mj-oref e 5) (%mj-oref e 3) prog 9 0 0 0 0 0 0 0))))

(doc (provide x/codec/mont-jit mont-jit-engine mont-jit-make mont-jit-pure mont-jit-compiled? mont-jit-free mont-jit-n
              mont-jit-load! mont-jit-store mont-jit-copy! mont-jit-zero? mont-jit-eq?
              mont-jit-load-bytes! mont-jit-store-bytes
              mont-jit-mul mont-jit-add mont-jit-sub mont-jit-to! mont-jit-from! mont-jit-one! mont-jit-pow! mont-jit-inv!
              mont-jit-program mont-jit-run!)
  "Montgomery arithmetic for one modulus over named slots: (mont-jit-engine m) builds a compiled engine (JIT, ARM64 and x86-64 backends) generic over the modulus, checked against x/codec/mont's pure-x operations, or falls back to those; a program of operations runs in one call; slots 0..mont-jit-free - 1 are the caller's.")
