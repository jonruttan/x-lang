; mont.x -- Montgomery arithmetic modulo an odd number, on 26-bit limbs.
;
; ECDSA over P-256 and P-384 works modulo the curve's prime and its
; order, and RSA modulo its public modulus: all of it is multiplication
; mod m, and Montgomery's form makes that a multiply and shifts with no
; division.  A number is a vector of n limbs of 26 bits, least
; significant first, limb k in slot k+1 (the length rides slot 0, as
; fe25519's do).  26 bits keep every product of two limbs under 2^52 and
; a row's sum with its carry under 2^54, inside the engine's 64-bit int,
; whose right shift is arithmetic -- the lane has no high-half multiply,
; so a limb must be small enough that the low half is the whole product.
;
; A MODULUS is built once from its big-endian bytes: its limbs, n' =
; -m^-1 mod 2^26, and R^2 mod m (R = 2^(26n)) for entering the form.
; Numbers in Montgomery form are a R mod m; mont-mul of two of them is
; their product's, and mont-from leaves the form.  Everything here is
; pure x on the int prims; a compiled multiplier can replace mont-mul
; once it agrees with this one.
(module x/codec/mont)

(import x/type/vector)
; Collection is explicit-trigger-only; mont-pow collects at fixed points.
(import x/sys/gc)

(def %add (prim-ref 'int '+))
(def %sub (prim-ref 'int '-))
(def %mul (prim-ref 'int '*))
(def %oref (prim-ref (lit obj) (lit ref)))
(def %oset! (prim-ref (lit obj) (lit set!)))
(def %byte-ref (prim-ref (lit str) (lit byte-ref)))
(def %char->int (prim-ref (lit char) (lit ->int)))
(def %make-str (prim-ref (lit str) (lit make)))
(def %str->ptr (prim-ref (lit str) (lit ->ptr)))
(def %pset1 (prim-ref (lit ptr) (lit set!)))

(def %M 67108863)

(def %byte (fn (_ s i) (%char->int (%byte-ref s i))))
(def %lr (fn (_ v i) (%oref v (%add i 1))))
(def %ls! (fn (_ v i x) (%oset! v (%add i 1) x)))

(def %limbs (fn (_ n) (Vector make n 0)))

(def %copy
  (fn (_ v n)
    (def out (%limbs n))
    ((fn (self i) (unless (= i n) (do (%ls! out i (%lr v i)) (self (%add i 1))))) 0)
    out))

; --- the modulus: a vector of (N LIMBS N' R2 ONE LEN) ---------------------

(def mont-n (fn (_ m) (%oref m 1)))
(def %m-limbs (fn (_ m) (%oref m 2)))
(def %m-inv (fn (_ m) (%oref m 3)))
(def %m-r2 (fn (_ m) (%oref m 4)))
(def mont-one (fn (_ m) (%oref m 5)))
(def mont-bytes (fn (_ m) (%oref m 6)))

; A big-endian region's bytes as n limbs: byte j from the end lands at bit
; 8j, in limb (8j)/26 and, when it straddles, the next.
(def %from-be
  (fn (_ s start len n)
    (def v (%limbs n))
    ((fn (self j limb off)
       (unless (= j len)
         (do (def b (%byte s (%sub (%add start len) (%add j 1))))
             (when (< limb n)
               (%ls! v limb (| (%lr v limb) (& (<< b off) %M))))
             (when (and (> off 18) (< (%add limb 1) n))
               (%ls! v (%add limb 1) (| (%lr v (%add limb 1)) (>> b (%sub 26 off)))))
             (if (>= (%add off 8) 26)
               (self (%add j 1) (%add limb 1) (%sub (%add off 8) 26))
               (self (%add j 1) limb (%add off 8))))))
     0 0 0)
    v))

; n limbs as len big-endian bytes, in a fresh buffer.
(def %to-be
  (fn (_ v n len)
    (def out (%make-str (if (> len 0) len 1)))
    (def p (%str->ptr out))
    ((fn (self j limb off)
       (unless (= j len)
         (do (def lo (if (< limb n) (>> (%lr v limb) off) 0))
             (def hi (if (and (> off 18) (< (%add limb 1) n)) (<< (%lr v (%add limb 1)) (%sub 26 off)) 0))
             (%pset1 p (%sub len (%add j 1)) (& (| lo hi) 255) 1)
             (if (>= (%add off 8) 26)
               (self (%add j 1) (%add limb 1) (%sub (%add off 8) 26))
               (self (%add j 1) limb (%add off 8))))))
     0 0 0)
    out))

; a >= b, limb by limb from the top.
(def %ge?
  (fn (_ a b n)
    ((fn (self i)
       (if (< i 0) #t
         (match ((> (%lr a i) (%lr b i)) #t)
                ((< (%lr a i) (%lr b i)) #f)
                (#t (self (%sub i 1))))))
     (%sub n 1))))

; a := a - b in place, the borrow carried by the arithmetic shift.
(def %sub-in!
  (fn (_ a b n)
    ((fn (self i c)
       (unless (= i n)
         (do (def s (%add (%sub (%lr a i) (%lr b i)) c))
             (%ls! a i (& s %M))
             (self (%add i 1) (>> s 26)))))
     0 0)))

; a := a + b in place; the carry out of the top limb is answered.
(def %add-in!
  (fn (_ a b n)
    ((fn (self i c)
       (if (= i n) c
         (do (def s (%add (%add (%lr a i) (%lr b i)) c))
             (%ls! a i (& s %M))
             (self (%add i 1) (>> s 26)))))
     0 0)))

; -m0^-1 mod 2^26 by Newton's iteration: x <- x (2 - m0 x) doubles the
; bits right each time, from one right bit (m0 is odd).
(def %neg-inverse
  (fn (_ m0)
    (def x ((fn (self x k) (if (= k 0) x (self (& (%mul x (%sub 2 (& (%mul m0 x) %M))) %M) (%sub k 1)))) 1 5))
    (& (%sub 0 x) %M)))

; 2^(2*26n) mod m, by doubling 1 that many times.
(def %r2
  (fn (_ m n)
    (def x (%limbs n))
    (%ls! x 0 1)
    ((fn (self k)
       (unless (= k 0)
         (do (def carry (%add-in! x x n))
             (when (or (> carry 0) (%ge? x m n)) (%sub-in! x m n))
             (self (%sub k 1)))))
     (* 52 n))
    x))

; --- the multiplier -----------------------------------------------------

; a b R^-1 mod m (CIOS: a row of a[i] b, then one row of m times the
; quotient digit that clears the bottom limb, shifted down a limb).
(def mont-mul
  (fn (_ m a b)
    (def n (mont-n m))
    (def p (%m-limbs m))
    (def inv (%m-inv m))
    (def t (%limbs (%add n 2)))
    ((fn (self i)
       (unless (= i n)
         (do (def ai (%lr a i))
             (def c ((fn (self j c)
                       (if (= j n) c
                         (do (def s (%add (%add (%lr t j) (%mul ai (%lr b j))) c))
                             (%ls! t j (& s %M))
                             (self (%add j 1) (>> s 26)))))
                     0 0))
             (def s (%add (%lr t n) c))
             (%ls! t n (& s %M))
             (%ls! t (%add n 1) (>> s 26))
             (def q (& (%mul (%lr t 0) inv) %M))
             (def c0 (>> (%add (%lr t 0) (%mul q (%lr p 0))) 26))
             (def c2 ((fn (self j c)
                        (if (= j n) c
                          (do (def s (%add (%add (%lr t j) (%mul q (%lr p j))) c))
                              (%ls! t (%sub j 1) (& s %M))
                              (self (%add j 1) (>> s 26)))))
                      1 c0))
             (def s2 (%add (%lr t n) c2))
             (%ls! t (%sub n 1) (& s2 %M))
             (%ls! t n (%add (%lr t (%add n 1)) (>> s2 26)))
             (self (%add i 1)))))
     0)
    (def out (%copy t n))
    (when (or (> (%lr t n) 0) (%ge? out p n)) (%sub-in! out p n))
    out))

(def mont-add
  (fn (_ m a b)
    (def n (mont-n m))
    (def out (%copy a n))
    (def carry (%add-in! out b n))
    (when (or (> carry 0) (%ge? out (%m-limbs m) n)) (%sub-in! out (%m-limbs m) n))
    out))

(def mont-sub
  (fn (_ m a b)
    (def n (mont-n m))
    (def out (%copy a n))
    (if (%ge? a b n)
      (do (%sub-in! out b n) out)
      (do (%add-in! out (%m-limbs m) n) (%sub-in! out b n) out))))

; Into and out of the form.
(def mont-to (fn (_ m a) (mont-mul m a (%m-r2 m))))
(def mont-from
  (fn (_ m a)
    (def one (%limbs (mont-n m)))
    (%ls! one 0 1)
    (mont-mul m a one)))

(def mont-zero? (fn (_ m a) ((fn (self i) (if (= i (mont-n m)) #t (if (= (%lr a i) 0) (self (%add i 1)) #f))) 0)))
(def mont-eq? (fn (_ m a b) ((fn (self i) (if (= i (mont-n m)) #t (if (= (%lr a i) (%lr b i)) (self (%add i 1)) #f))) 0)))

; a^e in the form, e a big-endian byte region: square and multiply from
; the top bit down.  A pure-x multiply leaves thousands of objects behind
; and x sweeps only when asked, so the chain collects every four bytes of
; exponent, as the digests' block loops do.
(def mont-pow
  (fn (_ m a s start len)
    ((fn (self j acc)
       (if (= j len) acc
         (do (when (and (> j 0) (= (& j 3) 0)) (Heap collect))
             (def b (%byte s (%add start j)))
             (self (%add j 1)
                   ((fn (self k acc)
                      (if (< k 0) acc
                        (do (def sq (mont-mul m acc acc))
                            (self (%sub k 1) (if (= (& (>> b k) 1) 1) (mont-mul m sq a) sq)))))
                    7 acc)))))
     0 (mont-one m))))

; a^-1 in the form, for m prime: a^(m-2) (Fermat).
(def mont-inv
  (fn (_ m a)
    (mont-pow m a (mont-minus-two m) 0 (mont-bytes m))))

; m - 2 as the modulus's length of big-endian bytes: the exponent Fermat's
; inverse raises to.
(def mont-minus-two
  (fn (_ m)
    (def n (mont-n m))
    (def two (%limbs n))
    (%ls! two 0 2)
    (def e (%copy (%m-limbs m) n))
    (%sub-in! e two n)
    (%to-be e n (mont-bytes m))))

; The modulus's R^2 mod m, out of the form, for an engine entering it.
(def mont-r2 (fn (_ m) (%m-r2 m)))

; The modulus from its big-endian bytes (odd, its top byte nonzero).
(def mont-modulus
  (fn (_ s start len)
    ; the fewest limbs holding 8 len bits with one to spare
    (def n ((fn (self n) (if (> (%mul 26 n) (%mul 8 len)) n (self (%add n 1)))) 1))
    (def limbs (%from-be s start len n))
    (def m (Vector make 6 0))
    (%oset! m 1 n)
    (%oset! m 2 limbs)
    (%oset! m 3 (%neg-inverse (%lr limbs 0)))
    (%oset! m 4 (%r2 limbs n))
    (%oset! m 6 len)
    (def one (%limbs n))
    (%ls! one 0 1)
    (%oset! m 5 (mont-mul m one (%m-r2 m)))
    m))

; A big-endian region as a number below m, out of the form, reduced
; once (an input below 2m, as a hash or a coordinate is).
(def mont-number
  (fn (_ m s start len)
    (def n (mont-n m))
    (def v (%from-be s start len n))
    (when (%ge? v (%m-limbs m) n) (%sub-in! v (%m-limbs m) n))
    v))

; A number as the modulus's byte length of big-endian bytes.
(def mont-bytes-of (fn (_ m v) (%to-be v (mont-n m) (mont-bytes m))))

; Is the big-endian region below m?  (A signature's r and s must be.)
(def mont-below?
  (fn (_ m s start len)
    (def n (mont-n m))
    (not (%ge? (%from-be s start len n) (%m-limbs m) n))))

(doc (provide x/codec/mont mont-modulus mont-n mont-one mont-bytes mont-number mont-bytes-of mont-below?
  mont-mul mont-add mont-sub mont-to mont-from mont-pow mont-inv mont-minus-two mont-r2 mont-zero? mont-eq?)
  "Montgomery arithmetic modulo an odd number on 26-bit limbs: a modulus from its big-endian bytes, mont-mul, add, sub, pow and inv in the form, and the doors in and out.")
