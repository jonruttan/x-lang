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

(def %byte (fn (_ s i) (%char->int (%byte-ref s i))))

(def %load3
  (fn (_ s i)
    (| (%byte s i) (| (<< (%byte s (%add i 1)) 8) (<< (%byte s (%add i 2)) 16)))))

(def %load4
  (fn (_ s i) (| (%load3 s i) (<< (%byte s (%add i 3)) 24))))

; A field element is a ten-slot vector, limb i in slot i+1 (the length
; rides slot 0).
(def fe-zero (fn (_) (Vector make 10 0)))
(def fe-ref (fn (_ f i) (%oref f (%add i 1))))
(def fe-set! (fn (_ f i v) (%oset! f (%add i 1) v)))

(def fe-limbs
  (fn (_ ls)
    (def f (fe-zero))
    ((fn (self i xs)
       (unless (null? xs) (do (fe-set! f i (first xs)) (self (%add i 1) (rest xs))))) 0 ls)
    f))

; A limb's width: 26 for even i, 25 for odd.
(def %width (fn (_ i) (if (= (& i 1) 0) 26 25)))

; The rounding carry from limb i into limb i+1 (limb 9's into limb 0,
; times 19), in place: what ref10's carry_i steps do.
(def %carry!
  (fn (_ h i)
    (def w (%width i))
    (def c (>> (%add (fe-ref h i) (<< 1 (%sub w 1))) w))
    (fe-set! h i (%sub (fe-ref h i) (<< c w)))
    (if (= i 9)
      (fe-set! h 0 (%add (fe-ref h 0) (%mul c 19)))
      (fe-set! h (%add i 1) (%add (fe-ref h (%add i 1)) c)))))

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
           (self (%add i 1) (>> (%add (fe-ref h i) c) (%width i)))))
       0 (>> (%add (%mul 19 (fe-ref h 9)) (<< 1 24)) 25)))
    (fe-set! h 0 (%add (fe-ref h 0) (%mul 19 q)))
    ; plain carries, the last one dropped: h is now in [0, p)
    ((fn (self i)
       (unless (= i 10)
         (do (def w (%width i))
             (def c (>> (fe-ref h i) w))
             (fe-set! h i (%sub (fe-ref h i) (<< c w)))
             (unless (= i 9) (fe-set! h (%add i 1) (%add (fe-ref h (%add i 1)) c)))
             (self (%add i 1))))) 0)
    (def out (%make-str 32))
    (def p (%str->ptr out))
    ; byte k is bits 8k..8k+7 of the 255-bit number: the limb that holds
    ; bit 8k, shifted, or'd with the next limb's low bits when the byte
    ; straddles them
    (def %start (fn (_ i) (>> (%add (%mul i 51) 1) 1)))
    ((fn (self k i)
       (unless (= k 32)
         (do (def i2 (if (>= (%mul k 8) (%start (%add i 1))) (%add i 1) i))
             (def lo (>> (fe-ref h i2) (%sub (%mul k 8) (%start i2))))
             (def v (if (if (< i2 9) (< (%start (%add i2 1)) (%add (%mul k 8) 8)) #f)
                      (| lo (<< (fe-ref h (%add i2 1)) (%sub (%start (%add i2 1)) (%mul k 8))))
                      lo))
             (%pset1 p k (& v 255) 1)
             (self (%add k 1) i2)))) 0 0)
    out))

(def fe-add
  (fn (_ f g)
    (fe-limbs (list (%add (%oref f 1) (%oref g 1)) (%add (%oref f 2) (%oref g 2)) (%add (%oref f 3) (%oref g 3)) (%add (%oref f 4) (%oref g 4)) (%add (%oref f 5) (%oref g 5)) (%add (%oref f 6) (%oref g 6)) (%add (%oref f 7) (%oref g 7)) (%add (%oref f 8) (%oref g 8)) (%add (%oref f 9) (%oref g 9)) (%add (%oref f 10) (%oref g 10))))))

(def fe-sub
  (fn (_ f g)
    (fe-limbs (list (%sub (%oref f 1) (%oref g 1)) (%sub (%oref f 2) (%oref g 2)) (%sub (%oref f 3) (%oref g 3)) (%sub (%oref f 4) (%oref g 4)) (%sub (%oref f 5) (%oref g 5)) (%sub (%oref f 6) (%oref g 6)) (%sub (%oref f 7) (%oref g 7)) (%sub (%oref f 8) (%oref g 8)) (%sub (%oref f 9) (%oref g 9)) (%sub (%oref f 10) (%oref g 10))))))

; The product (ref10 fe_mul), unrolled as ref10 writes it: row k collects
; f_i g_j for i + j = k and, folded back by 19 since 2^255 = 19 mod p,
; for i + j = k + 10; an odd-odd pair sits one bit low in the 25.5-bit
; radix, so its f is doubled.  Written out rather than looped because a
; loop's bookkeeping is most of an interpreted multiply's cost, and an
; exchange does three thousand of them.
(def fe-mul
  (fn (_ f g)
    (def f0 (%oref f 1)) (def f1 (%oref f 2)) (def f2 (%oref f 3)) (def f3 (%oref f 4))
    (def f4 (%oref f 5)) (def f5 (%oref f 6)) (def f6 (%oref f 7)) (def f7 (%oref f 8))
    (def f8 (%oref f 9)) (def f9 (%oref f 10))
    (def g0 (%oref g 1)) (def g1 (%oref g 2)) (def g2 (%oref g 3)) (def g3 (%oref g 4))
    (def g4 (%oref g 5)) (def g5 (%oref g 6)) (def g6 (%oref g 7)) (def g7 (%oref g 8))
    (def g8 (%oref g 9)) (def g9 (%oref g 10))
    (def f1-2 (%mul f1 2)) (def f3-2 (%mul f3 2)) (def f5-2 (%mul f5 2))
    (def f7-2 (%mul f7 2)) (def f9-2 (%mul f9 2))
    (def g1-19 (%mul g1 19)) (def g2-19 (%mul g2 19)) (def g3-19 (%mul g3 19))
    (def g4-19 (%mul g4 19)) (def g5-19 (%mul g5 19)) (def g6-19 (%mul g6 19))
    (def g7-19 (%mul g7 19)) (def g8-19 (%mul g8 19)) (def g9-19 (%mul g9 19))
    (def h0 (%add (%add (%add (%mul f0 g0) (%mul f1-2 g9-19)) (%add (%mul f2 g8-19) (%mul f3-2 g7-19))) (%add (%add (%add (%mul f4 g6-19) (%mul f5-2 g5-19)) (%add (%mul f6 g4-19) (%mul f7-2 g3-19))) (%add (%mul f8 g2-19) (%mul f9-2 g1-19)))))
    (def h1 (%add (%add (%add (%mul f0 g1) (%mul f1 g0)) (%add (%mul f2 g9-19) (%mul f3 g8-19))) (%add (%add (%add (%mul f4 g7-19) (%mul f5 g6-19)) (%add (%mul f6 g5-19) (%mul f7 g4-19))) (%add (%mul f8 g3-19) (%mul f9 g2-19)))))
    (def h2 (%add (%add (%add (%mul f0 g2) (%mul f1-2 g1)) (%add (%mul f2 g0) (%mul f3-2 g9-19))) (%add (%add (%add (%mul f4 g8-19) (%mul f5-2 g7-19)) (%add (%mul f6 g6-19) (%mul f7-2 g5-19))) (%add (%mul f8 g4-19) (%mul f9-2 g3-19)))))
    (def h3 (%add (%add (%add (%mul f0 g3) (%mul f1 g2)) (%add (%mul f2 g1) (%mul f3 g0))) (%add (%add (%add (%mul f4 g9-19) (%mul f5 g8-19)) (%add (%mul f6 g7-19) (%mul f7 g6-19))) (%add (%mul f8 g5-19) (%mul f9 g4-19)))))
    (def h4 (%add (%add (%add (%mul f0 g4) (%mul f1-2 g3)) (%add (%mul f2 g2) (%mul f3-2 g1))) (%add (%add (%add (%mul f4 g0) (%mul f5-2 g9-19)) (%add (%mul f6 g8-19) (%mul f7-2 g7-19))) (%add (%mul f8 g6-19) (%mul f9-2 g5-19)))))
    (def h5 (%add (%add (%add (%mul f0 g5) (%mul f1 g4)) (%add (%mul f2 g3) (%mul f3 g2))) (%add (%add (%add (%mul f4 g1) (%mul f5 g0)) (%add (%mul f6 g9-19) (%mul f7 g8-19))) (%add (%mul f8 g7-19) (%mul f9 g6-19)))))
    (def h6 (%add (%add (%add (%mul f0 g6) (%mul f1-2 g5)) (%add (%mul f2 g4) (%mul f3-2 g3))) (%add (%add (%add (%mul f4 g2) (%mul f5-2 g1)) (%add (%mul f6 g0) (%mul f7-2 g9-19))) (%add (%mul f8 g8-19) (%mul f9-2 g7-19)))))
    (def h7 (%add (%add (%add (%mul f0 g7) (%mul f1 g6)) (%add (%mul f2 g5) (%mul f3 g4))) (%add (%add (%add (%mul f4 g3) (%mul f5 g2)) (%add (%mul f6 g1) (%mul f7 g0))) (%add (%mul f8 g9-19) (%mul f9 g8-19)))))
    (def h8 (%add (%add (%add (%mul f0 g8) (%mul f1-2 g7)) (%add (%mul f2 g6) (%mul f3-2 g5))) (%add (%add (%add (%mul f4 g4) (%mul f5-2 g3)) (%add (%mul f6 g2) (%mul f7-2 g1))) (%add (%mul f8 g0) (%mul f9-2 g9-19)))))
    (def h9 (%add (%add (%add (%mul f0 g9) (%mul f1 g8)) (%add (%mul f2 g7) (%mul f3 g6))) (%add (%add (%add (%mul f4 g5) (%mul f5 g4)) (%add (%mul f6 g3) (%mul f7 g2))) (%add (%mul f8 g1) (%mul f9 g0)))))
    (def h (fe-limbs (list h0 h1 h2 h3 h4 h5 h6 h7 h8 h9)))
    (%carry-all! h %mul-order)
    h))

(def fe-sq (fn (_ f) (fe-mul f f)))

; Times (A - 2) / 4 = 121666, the ladder's constant (ref10 fe_mul121666).
(def fe-mul121666
  (fn (_ f)
    (def h (fe-limbs (list (%mul (%oref f 1) 121666) (%mul (%oref f 2) 121666) (%mul (%oref f 3) 121666) (%mul (%oref f 4) 121666) (%mul (%oref f 5) 121666) (%mul (%oref f 6) 121666) (%mul (%oref f 7) 121666) (%mul (%oref f 8) 121666) (%mul (%oref f 9) 121666) (%mul (%oref f 10) 121666))))
    (%carry-all! h %load-order)
    h))

; n squarings; every thirty-second returns the chain's garbage.
(def fe-sq-n
  (fn (self f n)
    (if (= n 0) f
      (do (when (= (& n 31) 0) (Heap collect))
          (self (fe-sq f) (%sub n 1))))))

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
    (fe-limbs (list (%sub 0 (fe-ref f 0)) (%sub 0 (fe-ref f 1)) (%sub 0 (fe-ref f 2))
                    (%sub 0 (fe-ref f 3)) (%sub 0 (fe-ref f 4)) (%sub 0 (fe-ref f 5))
                    (%sub 0 (fe-ref f 6)) (%sub 0 (fe-ref f 7)) (%sub 0 (fe-ref f 8))
                    (%sub 0 (fe-ref f 9))))))

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
    ((fn (self i) (if (= i 32) #f (if (= (%byte s i) 0) (self (%add i 1)) #t))) 0)))

(doc (provide x/codec/fe25519 fe-zero fe-limbs fe-ref fe-set! fe-frombytes fe-tobytes fe-add fe-sub fe-mul fe-sq fe-sq-n fe-mul121666 fe-invert fe-neg fe-pow22523 fe-negative? fe-nonzero?)
  "The field GF(2^255 - 19) on ref10's ten signed limbs: elements as ten-slot vectors, bytes in and out, add, subtract, negate, multiply, square, the ladder's times-121666, the inverse and the square root's power. Pure x-lang; what X25519 and Ed25519 compute in.")
