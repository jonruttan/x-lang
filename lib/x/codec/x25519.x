; x25519.x -- X25519: Diffie-Hellman on Curve25519 (RFC 7748) in pure x-lang.
;
; The key exchange of curve25519-sha256, the first an SSH written in x
; offers and the one Dropbear and OpenSSH prefer; it needs the function
; where no C library is present.  (X25519 scalarmult k u) is the RFC's
; function, (X25519 base k) its public key, both 32 bytes.
;
; The field is GF(2^255 - 19) on ten limbs of 25.5 bits -- ref10's
; layout, limb i at bit ceil(25.5 i), even limbs 26 bits wide and odd
; ones 25 -- SIGNED, with ref10's rounding carries, so that a product of
; two limbs times the fold's 19 and the odd-odd 2 is under 2^58 and a row
; of ten under 2^62: every value fits the engine's 64-bit int, whose
; right shift is arithmetic, and the exchange is tower-proof on the int
; prims.  The ladder is the RFC's Montgomery ladder, bit by bit from the
; top, and the inverse its 2^255 - 21 power chain.  A compiled engine in
; x/codec/x25519-jit takes the field operations and is adopted only after
; it agrees with this one.  This is not constant time: an interpreter
; branches on the data it handles, and the swap here is a branch.
(module x/codec/x25519)

(import x/type/vector)
; Collection is explicit-trigger-only; an exchange makes three thousand
; field elements and their arithmetic's integers, so the ladder and the
; inverse collect at fixed points, as sha1.x's block loop does.
(import x/sys/gc)
; The compiled engine is on Compiled's list.
(import x/tool/compiled)

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
(def %fe (fn (_) (Vector make 10 0)))
(def %fe-ref (fn (_ f i) (%oref f (%add i 1))))
(def %fe-set! (fn (_ f i v) (%oset! f (%add i 1) v)))

(def %fe-of
  (fn (_ ls)
    (def f (%fe))
    ((fn (self i xs)
       (unless (null? xs) (do (%fe-set! f i (first xs)) (self (%add i 1) (rest xs))))) 0 ls)
    f))

; A limb's width: 26 for even i, 25 for odd.
(def %width (fn (_ i) (if (= (& i 1) 0) 26 25)))

; The rounding carry from limb i into limb i+1 (limb 9's into limb 0,
; times 19), in place: what ref10's carry_i steps do.
(def %carry!
  (fn (_ h i)
    (def w (%width i))
    (def c (>> (%add (%fe-ref h i) (<< 1 (%sub w 1))) w))
    (%fe-set! h i (%sub (%fe-ref h i) (<< c w)))
    (if (= i 9)
      (%fe-set! h 0 (%add (%fe-ref h 0) (%mul c 19)))
      (%fe-set! h (%add i 1) (%add (%fe-ref h (%add i 1)) c)))))

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
(def %fe-frombytes
  (fn (_ s)
    (def h (%fe-of (list (%load4 s 0)
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
(def %fe-tobytes
  (fn (_ f)
    (def h (%fe-of (List map (fn (_ i) (%fe-ref f i)) (list 0 1 2 3 4 5 6 7 8 9))))
    (def q
      ((fn (self i c)
         (if (= i 10) c
           (self (%add i 1) (>> (%add (%fe-ref h i) c) (%width i)))))
       0 (>> (%add (%mul 19 (%fe-ref h 9)) (<< 1 24)) 25)))
    (%fe-set! h 0 (%add (%fe-ref h 0) (%mul 19 q)))
    ; plain carries, the last one dropped: h is now in [0, p)
    ((fn (self i)
       (unless (= i 10)
         (do (def w (%width i))
             (def c (>> (%fe-ref h i) w))
             (%fe-set! h i (%sub (%fe-ref h i) (<< c w)))
             (unless (= i 9) (%fe-set! h (%add i 1) (%add (%fe-ref h (%add i 1)) c)))
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
             (def lo (>> (%fe-ref h i2) (%sub (%mul k 8) (%start i2))))
             (def v (if (if (< i2 9) (< (%start (%add i2 1)) (%add (%mul k 8) 8)) #f)
                      (| lo (<< (%fe-ref h (%add i2 1)) (%sub (%start (%add i2 1)) (%mul k 8))))
                      lo))
             (%pset1 p k (& v 255) 1)
             (self (%add k 1) i2)))) 0 0)
    out))

(def %fe-add
  (fn (_ f g)
    (%fe-of (list (%add (%oref f 1) (%oref g 1)) (%add (%oref f 2) (%oref g 2)) (%add (%oref f 3) (%oref g 3)) (%add (%oref f 4) (%oref g 4)) (%add (%oref f 5) (%oref g 5)) (%add (%oref f 6) (%oref g 6)) (%add (%oref f 7) (%oref g 7)) (%add (%oref f 8) (%oref g 8)) (%add (%oref f 9) (%oref g 9)) (%add (%oref f 10) (%oref g 10))))))

(def %fe-sub
  (fn (_ f g)
    (%fe-of (list (%sub (%oref f 1) (%oref g 1)) (%sub (%oref f 2) (%oref g 2)) (%sub (%oref f 3) (%oref g 3)) (%sub (%oref f 4) (%oref g 4)) (%sub (%oref f 5) (%oref g 5)) (%sub (%oref f 6) (%oref g 6)) (%sub (%oref f 7) (%oref g 7)) (%sub (%oref f 8) (%oref g 8)) (%sub (%oref f 9) (%oref g 9)) (%sub (%oref f 10) (%oref g 10))))))

; The product (ref10 fe_mul), unrolled as ref10 writes it: row k collects
; f_i g_j for i + j = k and, folded back by 19 since 2^255 = 19 mod p,
; for i + j = k + 10; an odd-odd pair sits one bit low in the 25.5-bit
; radix, so its f is doubled.  Written out rather than looped because a
; loop's bookkeeping is most of an interpreted multiply's cost, and an
; exchange does three thousand of them.
(def %fe-mul
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
    (def h (%fe-of (list h0 h1 h2 h3 h4 h5 h6 h7 h8 h9)))
    (%carry-all! h %mul-order)
    h))

(def %fe-sq (fn (_ f) (%fe-mul f f)))

; Times (A - 2) / 4 = 121666, the ladder's constant (ref10 fe_mul121666).
(def %fe-mul121666
  (fn (_ f)
    (def h (%fe-of (list (%mul (%oref f 1) 121666) (%mul (%oref f 2) 121666) (%mul (%oref f 3) 121666) (%mul (%oref f 4) 121666) (%mul (%oref f 5) 121666) (%mul (%oref f 6) 121666) (%mul (%oref f 7) 121666) (%mul (%oref f 8) 121666) (%mul (%oref f 9) 121666) (%mul (%oref f 10) 121666))))
    (%carry-all! h %load-order)
    h))

; n squarings; every thirty-second returns the chain's garbage.
(def %fe-sq-n
  (fn (self f n)
    (if (= n 0) f
      (do (when (= (& n 31) 0) (Heap collect))
          (self (%fe-sq f) (%sub n 1))))))

; z^(p - 2) = z^(2^255 - 21), ref10's chain.
(def %fe-invert
  (fn (_ z)
    (def t0 (%fe-sq z))
    (def t1 (%fe-mul z (%fe-sq-n t0 2)))
    (def t0b (%fe-mul t0 t1))
    (def t1b (%fe-mul t1 (%fe-sq t0b)))
    (def t1c (%fe-mul (%fe-sq-n t1b 5) t1b))
    (def t2 (%fe-mul (%fe-sq-n t1c 10) t1c))
    (def t2b (%fe-mul (%fe-sq-n t2 20) t2))
    (def t1d (%fe-mul (%fe-sq-n t2b 10) t1c))
    (def t2c (%fe-mul (%fe-sq-n t1d 50) t1d))
    (def t2d (%fe-mul (%fe-sq-n t2c 100) t2c))
    (def t1e (%fe-mul (%fe-sq-n (%fe-mul (%fe-sq-n t2d 50) t1d) 5) t0b))
    t1e))

; The clamped scalar's bit at position pos.
(def %bit
  (fn (_ k pos)
    (def b (%byte k (>> pos 3)))
    (def c (match ((< pos 8) (& b 248))
                  ((>= pos 248) (| (& b 127) 64))
                  (#t b)))
    (& (>> c (& pos 7)) 1)))

; The ladder (RFC 7748 5): from the top bit down, one differential
; addition and doubling a step, the pair swapped when the bit changes.
(def %ladder
  (fn (self k x1 x2 z2 x3 z3 swap pos)
    ; every sixteenth step returns the steps' garbage: the live set is the
    ; five elements in hand, and a collect marks the whole session
    (when (= (& pos 15) 0) (Heap collect))
    (def b (%bit k pos))
    (def sw (^ swap b))
    (def a2 (if (= sw 1) x3 x2)) (def c2 (if (= sw 1) z3 z2))
    (def a3 (if (= sw 1) x2 x3)) (def c3 (if (= sw 1) z2 z3))
    (def tmp0 (%fe-sub a3 c3))
    (def tmp1 (%fe-sub a2 c2))
    (def xx2 (%fe-add a2 c2))
    (def zz2 (%fe-add a3 c3))
    (def zz3 (%fe-mul tmp0 xx2))
    (def zz2b (%fe-mul zz2 tmp1))
    (def tmp0b (%fe-sq tmp1))
    (def tmp1b (%fe-sq xx2))
    (def xx3 (%fe-add zz3 zz2b))
    (def zz2c (%fe-sub zz3 zz2b))
    (def xx2b (%fe-mul tmp1b tmp0b))
    (def tmp1c (%fe-sub tmp1b tmp0b))
    (def zz2d (%fe-sq zz2c))
    (def zz3b (%fe-mul121666 tmp1c))
    (def xx3b (%fe-sq xx3))
    (def tmp0c (%fe-add tmp0b zz3b))
    (def zz3c (%fe-mul x1 zz2d))
    (def zz2e (%fe-mul tmp1c tmp0c))
    (if (= pos 0)
      (if (= b 1) (list xx3b zz3c) (list xx2b zz2e))
      (self k x1 xx2b zz2e xx3b zz3c b (%sub pos 1)))))

; The pure-x function: k and u as 32-byte strings -> 32 bytes.  The
; compiled engine answers the same bytes, so it is a drop-in.
(def %scalarmult
  (fn (_ k u)
    (def x1 (%fe-frombytes u))
    (def r (%ladder k x1 (%fe-of (list 1)) (%fe) x1 (%fe-of (list 1)) 0 254))
    (%fe-tobytes (%fe-mul (first r) (%fe-invert (first (rest r)))))))

(def %nine
  (fn (_)
    (def s (%make-str 32))
    (def p (%str->ptr s))
    ((fn (self i) (unless (= i 32) (do (%pset1 p i (if (= i 0) 9 0) 1) (self (%add i 1))))) 0)
    s))

; --- The compiled engine (JIT), adopted only when it proves out ------
;
; As chacha20.x's: an entry of Compiled's, made the first time a build is
; asked for, interpreted by %scalarmult above, and built on (X25519 jit!)
; -- never on its own, since one exchange costs about what the build does.
(def %entry ())

(def %jit-try!
  (fn (_)
    (when (null? %entry)
      (set! %entry
        (Compiled make-on-demand (lit x25519) %scalarmult
          (fn (_)
            (import x/codec/x25519-jit)
            ((prim-ref (lit x25519) (lit jit-make)) %scalarmult %fe-frombytes %fe-tobytes))
          (fn (_ v) ()))))
    ((fn (_ entry)
       (when (eq? (entry state) (lit interpreted)) (entry compile!))
       (eq? (entry state) (lit compiled)))
     %entry)))

(def %run
  (fn (_ k u)
    ((fn (_ entry)
       (if (if (null? entry) #f (eq? (entry state) (lit compiled)))
         ((entry compiled) k u)
         (%scalarmult k u)))
     %entry)))

(def-class X25519 ()
  (static
    (method scalarmult (self (param k STRING "The scalar: 32 bytes are read, clamped as the RFC says")
                             (param u STRING "The u-coordinate: 32 bytes are read, little-endian, the top bit ignored"))
      (doc "X25519 (RFC 7748 5): the u-coordinate of k times the point at u, as 32 little-endian bytes. With a peer's public key as u this is the shared secret; the caller checks it against all zeros if its protocol says to. Computed pure-x, or by the differentially-verified compiled engine once (jit!) has built it -- identical output either way. Not constant time."
        (returns STRING "32 bytes"))
      (%run k u))
    (method base (self (param k STRING "The private key: 32 bytes are read"))
      (doc "The public key for k: k times the base point, u = 9."
        (returns STRING "32 bytes"))
      (%run k (%nine)))
    (method jit! (self)
      (doc "Build and adopt the compiled field engine (JIT; ARM64 and x86-64 backends) now, if it can prove itself against the pure-x function. Idempotent. Returns #t when the engine is active, #f when unavailable -- pure-x carries on and results are identical either way. scalarmult never builds it on its own: one exchange costs about what the build does, so a process that exchanges keys more than once asks for it."
        (returns BOOL "#t when the compiled engine is active"))
      (%jit-try!))))

(doc (provide x/codec/x25519 X25519)
  "X25519 (RFC 7748): (X25519 scalarmult k u) and (X25519 base k), 32 bytes each. Pure x-lang on ref10's ten-limb field, with an optional differentially-verified JIT engine ((X25519 jit!)).")
