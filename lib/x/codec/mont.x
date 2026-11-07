; mont.x -- Montgomery arithmetic modulo an odd number, on limbs as wide
; as the word allows.
;
; ECDSA over P-256 and P-384 works modulo the curve's prime and its
; order, and RSA modulo its public modulus: all of it is multiplication
; mod m, and Montgomery's form makes that a multiply and shifts with no
; division.  A number is a vector of n limbs of B bits, least
; significant first, limb k in slot k+1 (the length rides slot 0, as
; fe25519's do).  A row's sum -- a limb, a product of two and a carry --
; is under 2^(2B+1), and must fit the engine's signed int, whose right
; shift is arithmetic: the lane has no high-half multiply, so a limb must
; be small enough that the low half is the whole product.  B is 26 on an
; 8-byte word and 14 on a 4-byte one, and x/codec/mont-jit's compiled
; engine works in the same limbs.
;
; A MODULUS is built once from its big-endian bytes: its limbs, n' =
; -m^-1 mod 2^B, and R^2 mod m (R = 2^(Bn)) for entering the form.
; Numbers in Montgomery form are a R mod m; mont-mul of two of them is
; their product's, and mont-from leaves the form.  Everything here is
; pure x on the int prims; a compiled multiplier can replace mont-mul
; once it agrees with this one.
(module x/codec/mont)

(import x/type/vector)
; Collection is explicit-trigger-only; mont-pow collects at fixed points.
(import x/sys/gc)

(import x/core/doors char->int int* int+ int- obj-ref obj-set! ptr-set! str->ptr str-byte-ref str-make)

; B, and the mask of a limb; a compiled engine works in the same limbs
(def mont-limb-bits ((fn (_ b) (if (< b 26) b 26)) (>> (int- (int* 8 %word-size) 3) 1)))
(def %B mont-limb-bits)
(def %M (int- (<< 1 %B) 1))

(def %byte (fn (_ s i) (char->int (str-byte-ref s i))))
(def %lr (fn (_ v i) (obj-ref v (int+ i 1))))
(def %ls! (fn (_ v i x) (obj-set! v (int+ i 1) x)))

(def %limbs (fn (_ n) (Vector make n 0)))

(def %copy
  (fn (_ v n)
    (def out (%limbs n))
    ((fn (self i) (unless (= i n) (do (%ls! out i (%lr v i)) (self (int+ i 1))))) 0)
    out))

; --- the modulus: a vector of (N LIMBS N' R2 ONE LEN BYTES) ---------------

(def mont-n (fn (_ m) (obj-ref m 1)))
; The limbs are made from the bytes when first asked for: a compiled
; engine reads the bytes itself and never asks.
(def %m-limbs
  (fn (_ m)
    (when (null? (obj-ref m 2))
      (do (def r (obj-ref m 7))
          (obj-set! m 2 (%from-be (first r) (first (rest r)) (first (rest (rest r))) (mont-n m)))))
    (obj-ref m 2)))
(def %m-inv (fn (_ m) (obj-ref m 3)))
; R^2 mod m and R mod m are made when first asked for: by pure x here --
; 2Bn doublings of a limb vector, 200 ms for P-256's prime -- or by a
; compiled engine's add through mont-set-r2!, which mont-jit does before
; anything asks, in milliseconds.
(def %m-r2
  (fn (_ m)
    (when (null? (obj-ref m 4)) (obj-set! m 4 (%r2 (%m-limbs m) (mont-n m))))
    (obj-ref m 4)))
(def mont-one
  (fn (_ m)
    (when (null? (obj-ref m 5))
      (do (def one (%limbs (mont-n m)))
          (%ls! one 0 1)
          (obj-set! m 5 (mont-mul m one (%m-r2 m)))))
    (obj-ref m 5)))
(def mont-r2-set? (fn (_ m) (not (null? (obj-ref m 4)))))
(def mont-set-r2! (fn (_ m v) (obj-set! m 4 v) m))
(def mont-bytes (fn (_ m) (obj-ref m 6)))
(def mont-region (fn (_ m) (obj-ref m 7)))
(def mont-limbs (fn (_ m) (%m-limbs m)))

; A big-endian region's bytes as n limbs: byte j from the end lands at bit
; 8j, in limb (8j)/B and, when it straddles, the next.
(def %from-be
  (fn (_ s start len n)
    (def v (%limbs n))
    ((fn (self j limb off)
       (unless (= j len)
         (do (def b (%byte s (int- (int+ start len) (int+ j 1))))
             (when (< limb n)
               (%ls! v limb (| (%lr v limb) (& (<< b off) %M))))
             (when (and (> off (int- %B 8)) (< (int+ limb 1) n))
               (%ls! v (int+ limb 1) (| (%lr v (int+ limb 1)) (>> b (int- %B off)))))
             (if (>= (int+ off 8) %B)
               (self (int+ j 1) (int+ limb 1) (int- (int+ off 8) %B))
               (self (int+ j 1) limb (int+ off 8))))))
     0 0 0)
    v))

; n limbs as len big-endian bytes, in a fresh buffer.
(def %to-be
  (fn (_ v n len)
    (def out (str-make (if (> len 0) len 1)))
    (def p (str->ptr out))
    ((fn (self j limb off)
       (unless (= j len)
         (do (def lo (if (< limb n) (>> (%lr v limb) off) 0))
             (def hi (if (and (> off (int- %B 8)) (< (int+ limb 1) n)) (<< (%lr v (int+ limb 1)) (int- %B off)) 0))
             (ptr-set! p (int- len (int+ j 1)) (& (| lo hi) 255) 1)
             (if (>= (int+ off 8) %B)
               (self (int+ j 1) (int+ limb 1) (int- (int+ off 8) %B))
               (self (int+ j 1) limb (int+ off 8))))))
     0 0 0)
    out))

; a >= b, limb by limb from the top.
(def %ge?
  (fn (_ a b n)
    ((fn (self i)
       (if (< i 0) #t
         (match ((> (%lr a i) (%lr b i)) #t)
                ((< (%lr a i) (%lr b i)) #f)
                (#t (self (int- i 1))))))
     (int- n 1))))

; a := a - b in place, the borrow carried by the arithmetic shift.
(def %sub-in!
  (fn (_ a b n)
    ((fn (self i c)
       (unless (= i n)
         (do (def s (int+ (int- (%lr a i) (%lr b i)) c))
             (%ls! a i (& s %M))
             (self (int+ i 1) (>> s %B)))))
     0 0)))

; a := a + b in place; the carry out of the top limb is answered.
(def %add-in!
  (fn (_ a b n)
    ((fn (self i c)
       (if (= i n) c
         (do (def s (int+ (int+ (%lr a i) (%lr b i)) c))
             (%ls! a i (& s %M))
             (self (int+ i 1) (>> s %B)))))
     0 0)))

; -m0^-1 mod 2^B by Newton's iteration: x <- x (2 - m0 x) doubles the
; bits right each time, from one right bit (m0 is odd).
(def %neg-inverse
  (fn (_ m0)
    (def x ((fn (self x k) (if (= k 0) x (self (& (int* x (int- 2 (& (int* m0 x) %M))) %M) (int- k 1)))) 1 5))
    (& (int- 0 x) %M)))

; 2^(2*26n) mod m, by doubling 1 that many times.
(def %r2
  (fn (_ m n)
    (def x (%limbs n))
    (%ls! x 0 1)
    ((fn (self k)
       (unless (= k 0)
         (do (def carry (%add-in! x x n))
             (when (or (> carry 0) (%ge? x m n)) (%sub-in! x m n))
             (self (int- k 1)))))
     (int* (int* 2 %B) n))
    x))

; --- the multiplier -----------------------------------------------------

; a b R^-1 mod m (CIOS: a row of a[i] b, then one row of m times the
; quotient digit that clears the bottom limb, shifted down a limb).
(def mont-mul
  (fn (_ m a b)
    (def n (mont-n m))
    (def p (%m-limbs m))
    (def inv (%m-inv m))
    (def t (%limbs (int+ n 2)))
    ((fn (self i)
       (unless (= i n)
         (do (def ai (%lr a i))
             (def c ((fn (self j c)
                       (if (= j n) c
                         (do (def s (int+ (int+ (%lr t j) (int* ai (%lr b j))) c))
                             (%ls! t j (& s %M))
                             (self (int+ j 1) (>> s %B)))))
                     0 0))
             (def s (int+ (%lr t n) c))
             (%ls! t n (& s %M))
             (%ls! t (int+ n 1) (>> s %B))
             (def q (& (int* (%lr t 0) inv) %M))
             (def c0 (>> (int+ (%lr t 0) (int* q (%lr p 0))) %B))
             (def c2 ((fn (self j c)
                        (if (= j n) c
                          (do (def s (int+ (int+ (%lr t j) (int* q (%lr p j))) c))
                              (%ls! t (int- j 1) (& s %M))
                              (self (int+ j 1) (>> s %B)))))
                      1 c0))
             (def s2 (int+ (%lr t n) c2))
             (%ls! t (int- n 1) (& s2 %M))
             (%ls! t n (int+ (%lr t (int+ n 1)) (>> s2 %B)))
             (self (int+ i 1)))))
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

(def mont-zero? (fn (_ m a) ((fn (self i) (if (= i (mont-n m)) #t (if (= (%lr a i) 0) (self (int+ i 1)) #f))) 0)))
(def mont-eq? (fn (_ m a b) ((fn (self i) (if (= i (mont-n m)) #t (if (= (%lr a i) (%lr b i)) (self (int+ i 1)) #f))) 0)))

; a^e in the form, e a big-endian byte region: square and multiply from
; the top bit down.  A pure-x multiply leaves thousands of objects behind
; and x sweeps only when asked, so the chain collects every four bytes of
; exponent, as the digests' block loops do.
(def mont-pow
  (fn (_ m a s start len)
    ((fn (self j acc)
       (if (= j len) acc
         (do (when (and (> j 0) (= (& j 3) 0)) (Heap collect))
             (def b (%byte s (int+ start j)))
             (self (int+ j 1)
                   ((fn (self k acc)
                      (if (< k 0) acc
                        (do (def sq (mont-mul m acc acc))
                            (self (int- k 1) (if (= (& (>> b k) 1) 1) (mont-mul m sq a) sq)))))
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

; The low limb of a big-endian region: its last four bytes' low B bits.
(def %low-limb
  (fn (_ s start len)
    (def b (fn (_ k) (if (< k len) (%byte s (int- (int+ start len) (int+ k 1))) 0)))
    (& (| (| (b 0) (<< (b 1) 8)) (| (<< (b 2) 16) (<< (b 3) 24))) %M)))

; The modulus from its big-endian bytes (odd, its top byte nonzero).  The
; region is kept, not copied: the caller's buffer must outlive the modulus
; unchanged.
(def mont-modulus
  (fn (_ s start len)
    ; the fewest limbs holding 8 len bits with one to spare
    (def n ((fn (self n) (if (> (int* %B n) (int* 8 len)) n (self (int+ n 1)))) 1))
    (def m (Vector make 7 ()))
    (obj-set! m 1 n)
    (obj-set! m 3 (%neg-inverse (%low-limb s start len)))
    (obj-set! m 6 len)
    (obj-set! m 7 (list s start len))
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

(doc (provide x/codec/mont mont-limb-bits mont-modulus mont-n mont-one mont-bytes mont-region mont-limbs mont-number mont-bytes-of mont-below?
  mont-mul mont-add mont-sub mont-to mont-from mont-pow mont-inv mont-minus-two mont-r2 mont-r2-set? mont-set-r2! mont-zero? mont-eq?)
  "Montgomery arithmetic modulo an odd number on limbs as wide as the word allows: a modulus from its big-endian bytes, mont-mul, add, sub, pow and inv in the form, and the doors in and out.")
