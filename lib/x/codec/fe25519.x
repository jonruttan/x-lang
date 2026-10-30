; fe25519.x -- the field GF(2^255 - 19), for X25519 and Ed25519.
;
; ref10's layout: ten limbs of 25.5 bits, limb i at bit ceil(25.5 i),
; even limbs 26 bits wide and odd ones 25 -- SIGNED, with ref10's
; rounding carries, so that a product of two limbs times the fold's 19
; and the odd-odd 2 is under 2^58 and a row of ten under 2^62: every
; value fits the engine's 64-bit int, whose right shift is arithmetic,
; and the arithmetic is tower-proof on the int prims.  The multiply is
; written out as ref10 writes it, since a loop's bookkeeping is most of
; an interpreted multiply's cost and an exchange does three thousand of
; them.  A field element is a ten-slot vector; the engines in
; x25519-jit and ed25519-jit keep theirs in scratch words and reach
; these only to load and pack bytes.
(module x/codec/fe25519)

(import x/type/vector)
; Collection is explicit-trigger-only; a long squaring chain collects at
; fixed points, as the ladder that calls it does.
(import x/sys/gc)

(import x/core/doors char->int int* int+ int- obj-ref obj-set! ptr-set! str->ptr str-byte-ref str-make)

(def %byte (fn (_ s i) (char->int (str-byte-ref s i))))

(def %load3
  (fn (_ s i)
    (| (%byte s i) (| (<< (%byte s (int+ i 1)) 8) (<< (%byte s (int+ i 2)) 16)))))

(def %load4
  (fn (_ s i) (| (%load3 s i) (<< (%byte s (int+ i 3)) 24))))

; A field element is a ten-slot vector, limb i in slot i+1 (the length
; rides slot 0).
(def fe-zero (fn (_) (Vector make 10 0)))
(def fe-ref (fn (_ f i) (obj-ref f (int+ i 1))))
(def fe-set! (fn (_ f i v) (obj-set! f (int+ i 1) v)))

(def fe-limbs
  (fn (_ ls)
    (def f (fe-zero))
    ((fn (self i xs)
       (unless (null? xs) (do (fe-set! f i (first xs)) (self (int+ i 1) (rest xs))))) 0 ls)
    f))

; A limb's width: 26 for even i, 25 for odd.
(def %width (fn (_ i) (if (= (& i 1) 0) 26 25)))

; The rounding carry from limb i into limb i+1 (limb 9's into limb 0,
; times 19), in place: what ref10's carry_i steps do.
(def %carry!
  (fn (_ h i)
    (def w (%width i))
    (def c (>> (int+ (fe-ref h i) (<< 1 (int- w 1))) w))
    (fe-set! h i (int- (fe-ref h i) (<< c w)))
    (if (= i 9)
      (fe-set! h 0 (int+ (fe-ref h 0) (int* c 19)))
      (fe-set! h (int+ i 1) (int+ (fe-ref h (int+ i 1)) c)))))

(def %carry-all!
  (fn (self h order)
    (unless (null? order)
      (do (%carry! h (first order)) (self h (rest order))))))

; ref10's two carry orders: the one its multiply uses, and the one its
; byte loader and its small-constant multiply use.
(def %mul-order (list 0 4 1 5 2 6 3 7 4 8 9 0))
(def %load-order (list 9 1 3 5 7 0 2 4 6 8))

; 32 little-endian bytes to a field element (ref10 fe_frombytes), the top
; bit masked as the RFC's decodeUCoordinate says.
(def fe-frombytes
  (fn (_ s)
    (def h (fe-limbs (list (%load4 s 0)
                         (<< (%load3 s 4) 6)
                         (<< (%load3 s 7) 5)
                         (<< (%load3 s 10) 3)
                         (<< (%load3 s 13) 2)
                         (%load4 s 16)
                         (<< (%load3 s 20) 7)
                         (<< (%load3 s 23) 5)
                         (<< (%load3 s 26) 4)
                         (<< (& (%load3 s 29) 8388607) 2))))
    (%carry-all! h %load-order)
    h))

; A field element to 32 bytes (ref10 fe_tobytes): reduced fully mod p --
; q is whether h is at or over p, found by carrying 19 times the top limb
; through -- then the limbs packed at their bit positions.
(def fe-tobytes
  (fn (_ f)
    (def h (fe-limbs (List map (fn (_ i) (fe-ref f i)) (list 0 1 2 3 4 5 6 7 8 9))))
    (def q
      ((fn (self i c)
         (if (= i 10) c
           (self (int+ i 1) (>> (int+ (fe-ref h i) c) (%width i)))))
       0 (>> (int+ (int* 19 (fe-ref h 9)) (<< 1 24)) 25)))
    (fe-set! h 0 (int+ (fe-ref h 0) (int* 19 q)))
    ; plain carries, the last one dropped: h is now in [0, p)
    ((fn (self i)
       (unless (= i 10)
         (do (def w (%width i))
             (def c (>> (fe-ref h i) w))
             (fe-set! h i (int- (fe-ref h i) (<< c w)))
             (unless (= i 9) (fe-set! h (int+ i 1) (int+ (fe-ref h (int+ i 1)) c)))
             (self (int+ i 1))))) 0)
    (def out (str-make 32))
    (def p (str->ptr out))
    ; byte k is bits 8k..8k+7 of the 255-bit number: the limb that holds
    ; bit 8k, shifted, or'd with the next limb's low bits when the byte
    ; straddles them
    (def %start (fn (_ i) (>> (int+ (int* i 51) 1) 1)))
    ((fn (self k i)
       (unless (= k 32)
         (do (def i2 (if (>= (int* k 8) (%start (int+ i 1))) (int+ i 1) i))
             (def lo (>> (fe-ref h i2) (int- (int* k 8) (%start i2))))
             (def v (if (if (< i2 9) (< (%start (int+ i2 1)) (int+ (int* k 8) 8)) #f)
                      (| lo (<< (fe-ref h (int+ i2 1)) (int- (%start (int+ i2 1)) (int* k 8))))
                      lo))
             (ptr-set! p k (& v 255) 1)
             (self (int+ k 1) i2)))) 0 0)
    out))

(def fe-add
  (fn (_ f g)
    (fe-limbs (list (int+ (obj-ref f 1) (obj-ref g 1)) (int+ (obj-ref f 2) (obj-ref g 2)) (int+ (obj-ref f 3) (obj-ref g 3)) (int+ (obj-ref f 4) (obj-ref g 4)) (int+ (obj-ref f 5) (obj-ref g 5)) (int+ (obj-ref f 6) (obj-ref g 6)) (int+ (obj-ref f 7) (obj-ref g 7)) (int+ (obj-ref f 8) (obj-ref g 8)) (int+ (obj-ref f 9) (obj-ref g 9)) (int+ (obj-ref f 10) (obj-ref g 10))))))

(def fe-sub
  (fn (_ f g)
    (fe-limbs (list (int- (obj-ref f 1) (obj-ref g 1)) (int- (obj-ref f 2) (obj-ref g 2)) (int- (obj-ref f 3) (obj-ref g 3)) (int- (obj-ref f 4) (obj-ref g 4)) (int- (obj-ref f 5) (obj-ref g 5)) (int- (obj-ref f 6) (obj-ref g 6)) (int- (obj-ref f 7) (obj-ref g 7)) (int- (obj-ref f 8) (obj-ref g 8)) (int- (obj-ref f 9) (obj-ref g 9)) (int- (obj-ref f 10) (obj-ref g 10))))))

; The product (ref10 fe_mul), unrolled as ref10 writes it: row k collects
; f_i g_j for i + j = k and, folded back by 19 since 2^255 = 19 mod p,
; for i + j = k + 10; an odd-odd pair sits one bit low in the 25.5-bit
; radix, so its f is doubled.  Written out rather than looped because a
; loop's bookkeeping is most of an interpreted multiply's cost, and an
; exchange does three thousand of them.
(def fe-mul
  (fn (_ f g)
    (def f0 (obj-ref f 1)) (def f1 (obj-ref f 2)) (def f2 (obj-ref f 3)) (def f3 (obj-ref f 4))
    (def f4 (obj-ref f 5)) (def f5 (obj-ref f 6)) (def f6 (obj-ref f 7)) (def f7 (obj-ref f 8))
    (def f8 (obj-ref f 9)) (def f9 (obj-ref f 10))
    (def g0 (obj-ref g 1)) (def g1 (obj-ref g 2)) (def g2 (obj-ref g 3)) (def g3 (obj-ref g 4))
    (def g4 (obj-ref g 5)) (def g5 (obj-ref g 6)) (def g6 (obj-ref g 7)) (def g7 (obj-ref g 8))
    (def g8 (obj-ref g 9)) (def g9 (obj-ref g 10))
    (def f1-2 (int* f1 2)) (def f3-2 (int* f3 2)) (def f5-2 (int* f5 2))
    (def f7-2 (int* f7 2)) (def f9-2 (int* f9 2))
    (def g1-19 (int* g1 19)) (def g2-19 (int* g2 19)) (def g3-19 (int* g3 19))
    (def g4-19 (int* g4 19)) (def g5-19 (int* g5 19)) (def g6-19 (int* g6 19))
    (def g7-19 (int* g7 19)) (def g8-19 (int* g8 19)) (def g9-19 (int* g9 19))
    (def h0 (int+ (int+ (int+ (int* f0 g0) (int* f1-2 g9-19)) (int+ (int* f2 g8-19) (int* f3-2 g7-19))) (int+ (int+ (int+ (int* f4 g6-19) (int* f5-2 g5-19)) (int+ (int* f6 g4-19) (int* f7-2 g3-19))) (int+ (int* f8 g2-19) (int* f9-2 g1-19)))))
    (def h1 (int+ (int+ (int+ (int* f0 g1) (int* f1 g0)) (int+ (int* f2 g9-19) (int* f3 g8-19))) (int+ (int+ (int+ (int* f4 g7-19) (int* f5 g6-19)) (int+ (int* f6 g5-19) (int* f7 g4-19))) (int+ (int* f8 g3-19) (int* f9 g2-19)))))
    (def h2 (int+ (int+ (int+ (int* f0 g2) (int* f1-2 g1)) (int+ (int* f2 g0) (int* f3-2 g9-19))) (int+ (int+ (int+ (int* f4 g8-19) (int* f5-2 g7-19)) (int+ (int* f6 g6-19) (int* f7-2 g5-19))) (int+ (int* f8 g4-19) (int* f9-2 g3-19)))))
    (def h3 (int+ (int+ (int+ (int* f0 g3) (int* f1 g2)) (int+ (int* f2 g1) (int* f3 g0))) (int+ (int+ (int+ (int* f4 g9-19) (int* f5 g8-19)) (int+ (int* f6 g7-19) (int* f7 g6-19))) (int+ (int* f8 g5-19) (int* f9 g4-19)))))
    (def h4 (int+ (int+ (int+ (int* f0 g4) (int* f1-2 g3)) (int+ (int* f2 g2) (int* f3-2 g1))) (int+ (int+ (int+ (int* f4 g0) (int* f5-2 g9-19)) (int+ (int* f6 g8-19) (int* f7-2 g7-19))) (int+ (int* f8 g6-19) (int* f9-2 g5-19)))))
    (def h5 (int+ (int+ (int+ (int* f0 g5) (int* f1 g4)) (int+ (int* f2 g3) (int* f3 g2))) (int+ (int+ (int+ (int* f4 g1) (int* f5 g0)) (int+ (int* f6 g9-19) (int* f7 g8-19))) (int+ (int* f8 g7-19) (int* f9 g6-19)))))
    (def h6 (int+ (int+ (int+ (int* f0 g6) (int* f1-2 g5)) (int+ (int* f2 g4) (int* f3-2 g3))) (int+ (int+ (int+ (int* f4 g2) (int* f5-2 g1)) (int+ (int* f6 g0) (int* f7-2 g9-19))) (int+ (int* f8 g8-19) (int* f9-2 g7-19)))))
    (def h7 (int+ (int+ (int+ (int* f0 g7) (int* f1 g6)) (int+ (int* f2 g5) (int* f3 g4))) (int+ (int+ (int+ (int* f4 g3) (int* f5 g2)) (int+ (int* f6 g1) (int* f7 g0))) (int+ (int* f8 g9-19) (int* f9 g8-19)))))
    (def h8 (int+ (int+ (int+ (int* f0 g8) (int* f1-2 g7)) (int+ (int* f2 g6) (int* f3-2 g5))) (int+ (int+ (int+ (int* f4 g4) (int* f5-2 g3)) (int+ (int* f6 g2) (int* f7-2 g1))) (int+ (int* f8 g0) (int* f9-2 g9-19)))))
    (def h9 (int+ (int+ (int+ (int* f0 g9) (int* f1 g8)) (int+ (int* f2 g7) (int* f3 g6))) (int+ (int+ (int+ (int* f4 g5) (int* f5 g4)) (int+ (int* f6 g3) (int* f7 g2))) (int+ (int* f8 g1) (int* f9 g0)))))
    (def h (fe-limbs (list h0 h1 h2 h3 h4 h5 h6 h7 h8 h9)))
    (%carry-all! h %mul-order)
    h))

(def fe-sq (fn (_ f) (fe-mul f f)))

; Times (A - 2) / 4 = 121666, the ladder's constant (ref10 fe_mul121666).
(def fe-mul121666
  (fn (_ f)
    (def h (fe-limbs (list (int* (obj-ref f 1) 121666) (int* (obj-ref f 2) 121666) (int* (obj-ref f 3) 121666) (int* (obj-ref f 4) 121666) (int* (obj-ref f 5) 121666) (int* (obj-ref f 6) 121666) (int* (obj-ref f 7) 121666) (int* (obj-ref f 8) 121666) (int* (obj-ref f 9) 121666) (int* (obj-ref f 10) 121666))))
    (%carry-all! h %load-order)
    h))

; n squarings; every thirty-second returns the chain's garbage.
(def fe-sq-n
  (fn (self f n)
    (if (= n 0) f
      (do (when (= (& n 31) 0) (Heap collect))
          (self (fe-sq f) (int- n 1))))))

; z^(p - 2) = z^(2^255 - 21), ref10's chain.
(def fe-invert
  (fn (_ z)
    (def t0 (fe-sq z))
    (def t1 (fe-mul z (fe-sq-n t0 2)))
    (def t0b (fe-mul t0 t1))
    (def t1b (fe-mul t1 (fe-sq t0b)))
    (def t1c (fe-mul (fe-sq-n t1b 5) t1b))
    (def t2 (fe-mul (fe-sq-n t1c 10) t1c))
    (def t2b (fe-mul (fe-sq-n t2 20) t2))
    (def t1d (fe-mul (fe-sq-n t2b 10) t1c))
    (def t2c (fe-mul (fe-sq-n t1d 50) t1d))
    (def t2d (fe-mul (fe-sq-n t2c 100) t2c))
    (def t1e (fe-mul (fe-sq-n (fe-mul (fe-sq-n t2d 50) t1d) 5) t0b))
    t1e))


; --- what Ed25519 needs beyond the ladder ------------------------------

(def fe-neg
  (fn (_ f)
    (fe-limbs (list (int- 0 (fe-ref f 0)) (int- 0 (fe-ref f 1)) (int- 0 (fe-ref f 2))
                    (int- 0 (fe-ref f 3)) (int- 0 (fe-ref f 4)) (int- 0 (fe-ref f 5))
                    (int- 0 (fe-ref f 6)) (int- 0 (fe-ref f 7)) (int- 0 (fe-ref f 8))
                    (int- 0 (fe-ref f 9))))))

; z^((p - 5) / 8) = z^(2^252 - 3), ref10's chain: the square root's
; helper in a point's decompression.
(def fe-pow22523
  (fn (_ z)
    (def t0 (fe-sq z))
    (def t1 (fe-mul z (fe-sq-n t0 2)))
    (def t0b (fe-mul t1 (fe-sq (fe-mul t0 t1))))
    (def t0c (fe-mul (fe-sq-n t0b 5) t0b))
    (def t1b (fe-mul (fe-sq-n t0c 10) t0c))
    (def t1c (fe-mul (fe-sq-n t1b 20) t1b))
    (def t0d (fe-mul (fe-sq-n t1c 10) t0c))
    (def t1d (fe-mul (fe-sq-n t0d 50) t0d))
    (def t1e (fe-mul (fe-sq-n t1d 100) t1d))
    (def t0e (fe-mul (fe-sq-n t1e 50) t0d))
    (fe-mul (fe-sq-n t0e 2) z)))

; The sign bit of the canonical encoding: the low bit of its first byte.
(def fe-negative?
  (fn (_ f) (= (& (%byte (fe-tobytes f) 0) 1) 1)))

; Whether the element is anything but zero mod p.
(def fe-nonzero?
  (fn (_ f)
    (def s (fe-tobytes f))
    ((fn (self i) (if (= i 32) #f (if (= (%byte s i) 0) (self (int+ i 1)) #t))) 0)))

(doc (provide x/codec/fe25519 fe-zero fe-limbs fe-ref fe-set! fe-frombytes fe-tobytes fe-add fe-sub fe-mul fe-sq fe-sq-n fe-mul121666 fe-invert fe-neg fe-pow22523 fe-negative? fe-nonzero?)
  "The field GF(2^255 - 19) on ref10's ten signed limbs: elements as ten-slot vectors, bytes in and out, add, subtract, negate, multiply, square, the ladder's times-121666, the inverse and the square root's power. Pure x-lang; what X25519 and Ed25519 compute in.")
