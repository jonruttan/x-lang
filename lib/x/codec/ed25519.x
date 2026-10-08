; ed25519.x -- Ed25519: signatures (RFC 8032) in pure x-lang.
;
; The host key and the user key of an SSH written in x: ssh-ed25519 is
; what Dropbear and OpenSSH offer first, and the server signs the
; exchange hash with it while the client signs its authentication with
; it.  (Ed25519 public seed), (Ed25519 sign seed msg) and (Ed25519
; verify pub sig msg) are the RFC's three functions.
;
; The field is x/codec/fe25519's; points are ref10's extended
; coordinates (X Y Z T, with the cached form a sum wants), doubled and
; added as ref10 does, and a scalar times a point is a plain
; double-and-add from the top bit -- variable time, like everything an
; interpreter does, and the doc says so.  Scalars mod L live on 16-bit
; limbs with a bit-by-bit reduction: slow and short, and done three times
; a signature.  SHA-512 is x/codec/sha512's.  A compiled engine in
; x/codec/ed25519-jit takes the field operations and is adopted only
; after it agrees with this module.
(module x/codec/ed25519)

(import x/type/vector)
; Collection is explicit-trigger-only; a scalar multiplication makes
; thousands of field elements, so it collects at fixed points.
(import x/sys/gc)
; The compiled engine is on Compiled's list.
(import x/tool/compiled)
(import x/codec/fe25519 fe-zero fe-limbs fe-frombytes fe-tobytes fe-add fe-sub fe-mul fe-sq fe-invert fe-neg fe-pow22523 fe-negative? fe-nonzero?)
(import x/codec/sha512)
(import x/codec/hex)

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

; --- bytes ------------------------------------------------------------

; The regions (s start len) ... joined into one fresh string: the
; strings may hold NULs, so a byte loop, never an append.
(def %total
  (fn (self rs)
    (if (null? rs) 0 (%add (first (rest (rest (first rs)))) (self (rest rs))))))

(def %join
  (fn (_ regions)
    (def n (%total regions))
    (def out (%make-str n))
    (def p (%str->ptr out))
    ((fn (self rs at)
       (unless (null? rs)
         (do (def s (first (first rs)))
             (def start (first (rest (first rs))))
             (def len (first (rest (rest (first rs)))))
             ((fn (self i) (unless (= i len) (do (%pset1 p (%add at i) (%byte s (%add start i)) 1) (self (%add i 1))))) 0)
             (self (rest rs) (%add at len))))) regions 0)
    out))

; A big-endian hex spelling as little-endian bytes: how the constants
; below are written, as numbers, and read, as encodings.
(def %le-of-hex
  (fn (_ hex)
    (def be (Hex decode hex))
    (def n (>> (Str8 length hex) 1))
    (def out (%make-str n))
    (def p (%str->ptr out))
    ((fn (self i) (unless (= i n) (do (%pset1 p i (%byte be (%sub (%sub n 1) i)) 1) (self (%add i 1))))) 0)
    out))

(def %same-bytes?
  (fn (self x y i n)
    (if (= i n) #t (if (= (%byte x i) (%byte y i)) (self x y (%add i 1) n) #f))))

; SHA-512 of joined regions, as 64 bytes.
(def %sha512
  (fn (_ regions)
    (def m (%join regions))
    (Hex decode (Sha512 hex-n m (%total regions)))))

; --- the curve --------------------------------------------------------

; d = -121665/121666 and sqrt(-1), as the RFC spells them.
(def %d (fe-frombytes (%le-of-hex "52036cee2b6ffe738cc740797779e89800700a4d4141d8ab75eb4dca135978a3")))
(def %d2 (fe-add %d %d))
(def %sqrtm1 (fe-frombytes (%le-of-hex "2b8324804fc1df0b2b4d00993dfbd7a72f431806ad2fe478c4ee1b274a0ea0b0")))

; A point is (X Y Z T): extended coordinates, x = X/Z, y = Y/Z, T = XY/Z.
(def %px (fn (_ p) (first p)))
(def %py (fn (_ p) (first (rest p))))
(def %pz (fn (_ p) (first (rest (rest p)))))
(def %pt (fn (_ p) (first (rest (rest (rest p))))))
(def %one (fe-limbs (list 1)))
(def %identity (list (fe-zero) %one %one (fe-zero)))

; The completed form (ref10 p1p1) made a point again: X·T, Y·Z, Z·T, X·Y.
(def %complete
  (fn (_ q)
    (list (fe-mul (%px q) (%pt q)) (fe-mul (%py q) (%pz q))
          (fe-mul (%pz q) (%pt q)) (fe-mul (%px q) (%py q)))))

; Doubling (ref10 ge_p2_dbl), the completed form.
(def %double
  (fn (_ p)
    (def xx (fe-sq (%px p)))
    (def yy (fe-sq (%py p)))
    (def zz2 (fe-add (fe-sq (%pz p)) (fe-sq (%pz p))))
    (def aa (fe-sq (fe-add (%px p) (%py p))))
    (def y (fe-add yy xx))
    (def z (fe-sub yy xx))
    (list (fe-sub aa y) y z (fe-sub zz2 z))))

; The cached form of a point (ref10 ge_p3_to_cached): Y+X, Y-X, Z, 2dT.
(def %cached
  (fn (_ p)
    (list (fe-add (%py p) (%px p)) (fe-sub (%py p) (%px p)) (%pz p) (fe-mul (%pt p) %d2))))

; p + q, q cached (ref10 ge_add), and p - q (ge_sub): the completed form.
(def %add-cached
  (fn (_ p q negate)
    (def a (fe-mul (fe-add (%py p) (%px p)) (if negate (first (rest q)) (first q))))
    (def b (fe-mul (fe-sub (%py p) (%px p)) (if negate (first q) (first (rest q)))))
    (def c (fe-mul (%pt q) (%pt p)))
    (def dd (fe-add (fe-mul (%pz p) (%pz q)) (fe-mul (%pz p) (%pz q))))
    (list (fe-sub a b) (fe-add a b)
          (if negate (fe-sub dd c) (fe-add dd c))
          (if negate (fe-add dd c) (fe-sub dd c)))))

(def %point-add (fn (_ p q) (%complete (%add-cached p (%cached q) #f))))
(def %point-sub (fn (_ p q) (%complete (%add-cached p (%cached q) #t))))

; k times p, k as 32 little-endian bytes: double-and-add from bit 255
; down, every sixteenth step returning the steps' garbage.
(def %scalarmult
  (fn (_ k p)
    (def cq (%cached p))
    ((fn (self acc bit)
       (if (< bit 0) acc
         (do (when (= (& bit 15) 0) (Heap collect))
             (def doubled (%complete (%double acc)))
             (self (if (= (& (>> (%byte k (>> bit 3)) (& bit 7)) 1) 1)
                     (%complete (%add-cached doubled cq #f))
                     doubled)
                   (%sub bit 1)))))
     %identity 255)))

; A point's encoding (ref10 ge_p3_tobytes): y, with x's sign in the top bit.
(def %encode
  (fn (_ p)
    (def recip (fe-invert (%pz p)))
    (def x (fe-mul (%px p) recip))
    (def y (fe-mul (%py p) recip))
    (def s (fe-tobytes y))
    (when (fe-negative? x)
      (%pset1 (%str->ptr s) 31 (| (%byte s 31) 128) 1))
    s))

; An encoding's point (ref10 ge_frombytes_negate_vartime, without the
; negation): x from y by the curve equation, the square root through
; the 2^252 - 3 power and sqrt(-1), the sign bit choosing the root; ()
; when the bytes are no point.
(def %decode
  (fn (_ s)
    (def y (fe-frombytes s))
    (def yy (fe-sq y))
    (def u (fe-sub yy %one))
    (def v (fe-add (fe-mul yy %d) %one))
    (def v3 (fe-mul (fe-sq v) v))
    (def x0 (fe-mul (fe-mul u v3) (fe-pow22523 (fe-mul (fe-mul (fe-sq v3) v) u))))
    (def vxx (fe-mul (fe-sq x0) v))
    (def x1 (if (fe-nonzero? (fe-sub vxx u))
              (if (fe-nonzero? (fe-add vxx u)) () (fe-mul x0 %sqrtm1))
              x0))
    (if (null? x1) ()
      (do (def x (if (= (if (fe-negative? x1) 1 0) (>> (%byte s 31) 7)) x1 (fe-neg x1)))
          (list x y %one (fe-mul x y))))))

(def %negate (fn (_ p) (list (fe-neg (%px p)) (%py p) (%pz p) (fe-neg (%pt p)))))

; The base point: y = 4/5, x positive.
(def %base (%decode (%le-of-hex "6666666666666666666666666666666666666666666666666666666666666658")))

; --- scalars mod L ------------------------------------------------------
;
; L = 2^252 + 27742317777372353535851937790883648493, on 16-bit limbs in
; vectors (limb i in slot i+1).  A reduction walks the value's bits from
; the top, doubling and subtracting L whenever the running remainder
; reaches it; a product is schoolbook.  Everything fits the int easily.

(def %L-bytes (%le-of-hex "1000000000000000000000000000000014def9dea2f79cd65812631a5cf5d3ed"))

(def %limbs
  (fn (_ s n)
    (def v (Vector make (>> n 1) 0))
    ((fn (self i) (unless (= i (>> n 1))
                    (do (%oset! v (%add i 1) (| (%byte s (%mul i 2)) (<< (%byte s (%add (%mul i 2) 1)) 8)))
                        (self (%add i 1))))) 0)
    v))

(def %L (%limbs %L-bytes 32))

; r >= L, r having 17 limbs (the top one the doubling's overflow).
(def %at-least-L?
  (fn (_ r)
    (if (> (%oref r 17) 0) #t
      ((fn (self i)
         (match ((< i 1) #t)
                ((> (%oref r i) (%oref %L i)) #t)
                ((< (%oref r i) (%oref %L i)) #f)
                (#t (self (%sub i 1)))))
       16))))

(def %sub-L!
  (fn (_ r)
    ((fn (self i borrow)
       (unless (= i 18)
         (do (def d (%sub (%sub (%oref r i) (if (< i 17) (%oref %L i) 0)) borrow))
             (%oset! r i (& d 65535))
             (self (%add i 1) (if (< d 0) 1 0)))))
     1 0)))

; r = 2r + bit, in place.
(def %double-in!
  (fn (_ r bit)
    ((fn (self i carry)
       (unless (= i 18)
         (do (def d (%add (%add (%oref r i) (%oref r i)) carry))
             (%oset! r i (& d 65535))
             (self (%add i 1) (>> d 16)))))
     1 bit)))

; v mod L, v having n limbs: a 16-limb vector.
(def %reduce
  (fn (_ v n)
    (def r (Vector make 17 0))
    ((fn (self bit)
       (unless (< bit 0)
         (do (%double-in! r (& (>> (%oref v (%add (>> bit 4) 1)) (& bit 15)) 1))
             (when (%at-least-L? r) (%sub-L! r))
             (self (%sub bit 1)))))
     (%sub (%mul n 16) 1))
    (def out (Vector make 16 0))
    ((fn (self i) (unless (= i 17) (do (%oset! out i (%oref r i)) (self (%add i 1))))) 1)
    out))

; a·b + c on 16-limb vectors, as 32 limbs.
(def %muladd
  (fn (_ a b c)
    (def p (Vector make 32 0))
    ((fn (self i) (unless (= i 17) (do (%oset! p i (%oref c i)) (self (%add i 1))))) 1)
    ; row i: a_i times every b_j into column i+j, the carry riding along
    ; and landing in column i+16
    ((fn (self i)
       (unless (= i 17)
         (do ((fn (self j carry)
                (if (= j 17)
                  (%oset! p (%add i 16) (%add (%oref p (%add i 16)) carry))
                  (do (def col (%sub (%add i j) 1))
                      (def t (%add (%add (%oref p col) (%mul (%oref a i) (%oref b j))) carry))
                      (%oset! p col (& t 65535))
                      (self (%add j 1) (>> t 16)))))
              1 0)
             (self (%add i 1))))) 1)
    ; a row's last carry may have pushed a column past 16 bits; settle once
    ((fn (self i carry)
       (unless (= i 33)
         (do (def t (%add (%oref p i) carry))
             (%oset! p i (& t 65535))
             (self (%add i 1) (>> t 16)))))
     1 0)
    p))

(def %sc-bytes
  (fn (_ v)
    (def out (%make-str 32))
    (def p (%str->ptr out))
    ((fn (self i)
       (unless (= i 16)
         (do (%pset1 p (%mul i 2) (& (%oref v (%add i 1)) 255) 1)
             (%pset1 p (%add (%mul i 2) 1) (>> (%oref v (%add i 1)) 8) 1)
             (self (%add i 1))))) 0)
    out))

; S < L, S as 32 bytes: a signature's scalar must be canonical.
(def %canonical?
  (fn (_ s)
    (def v (%limbs s 32))
    ((fn (self i)
       (match ((< i 1) #f)
              ((< (%oref v i) (%oref %L i)) #t)
              ((> (%oref v i) (%oref %L i)) #f)
              (#t (self (%sub i 1)))))
     16)))

; --- The compiled engine (JIT), adopted only when it proves out ------
;
; As x25519.x's: an entry of Compiled's, made the first time a build is
; asked for, interpreted by %scalarmult above, and built on (Ed25519
; jit!) -- never on its own, since one signature costs about what the
; build does.
(def %entry ())

(def %jit-try!
  (fn (_)
    (when (null? %entry)
      (set! %entry
        (Compiled make-on-demand (lit ed25519) %scalarmult
          (fn (_)
            (import x/codec/ed25519-jit)
            ((prim-ref (lit ed25519) (lit jit-make)) %scalarmult %d2 fe-tobytes %base))
          (fn (_ v) ()))))
    ((fn (_ entry)
       (when (eq? (entry state) (lit interpreted)) (entry compile!))
       (eq? (entry state) (lit compiled)))
     %entry)))

(def %run
  (fn (_ k p)
    ((fn (_ entry)
       (if (if (null? entry) #f (eq? (entry state) (lit compiled)))
         ((entry compiled) k p)
         (%scalarmult k p)))
     %entry)))

; --- the RFC's three functions (5.1.5, 5.1.6, 5.1.7) --------------------

; The secret scalar and the prefix from a seed: SHA-512 of it, the first
; half clamped.
(def %expand
  (fn (_ seed)
    (def h (%sha512 (list (list seed 0 32))))
    (def p (%str->ptr h))
    (%pset1 p 0 (& (%byte h 0) 248) 1)
    (%pset1 p 31 (| (& (%byte h 31) 63) 64) 1)
    h))

(def %public
  (fn (_ seed) (%encode (%run (%expand seed) %base))))

(def %sign
  (fn (_ seed m start len)
    (def h (%expand seed))
    (def a (%limbs h 32))
    (def pub (%encode (%run h %base)))
    (def r (%reduce (%limbs (%sha512 (list (list h 32 32) (list m start len))) 64) 32))
    (def rb (%sc-bytes r))
    (def R (%encode (%run rb %base)))
    (def k (%reduce (%limbs (%sha512 (list (list R 0 32) (list pub 0 32) (list m start len))) 64) 32))
    (def S (%sc-bytes (%reduce (%muladd k a r) 32)))
    (%join (list (list R 0 32) (list S 0 32)))))

(def %verify
  (fn (_ pub sig m start len)
    (def A (%decode pub))
    (if (null? A) #f
      (if (not (%canonical? (%join (list (list sig 32 32))))) #f
        (do (def k (%sc-bytes (%reduce (%limbs (%sha512 (list (list sig 0 32) (list pub 0 32) (list m start len))) 64) 32)))
            (def S (%join (list (list sig 32 32))))
            ; [S]B - [k]A must encode as R
            (def R (%encode (%point-sub (%run S %base) (%run k A))))
            (%same-bytes? R sig 0 32))))))

(def %region
  (fn (_ s r)
    (match ((null? r) (list 0 (Str8 length s)))
           (#t (list (first r) (first (rest r)))))))

(def-class Ed25519 ()
  (static
    (method public (self (param seed STRING "The private key: 32 bytes are read"))
      (doc "The public key for a seed (RFC 8032 5.1.5): the clamped first half of its SHA-512 times the base point, encoded as 32 bytes."
        (returns STRING "32 bytes"))
      (%public seed))
    (method sign (self (param seed STRING "The private key: 32 bytes are read")
                       (param m STRING "The message")
                       . (param span LIST "START, then LENGTH: which bytes of m; default all of m"))
      (doc "The signature of a message under a seed (RFC 8032 5.1.6): R then S, 64 bytes. Deterministic: the same seed and message always give the same signature. GIVE THE REGION FOR BINARY INPUT: m's own length is measured to its first NUL. Not constant time."
        (returns STRING "64 bytes"))
      (def r (%region m span))
      (%sign seed m (first r) (first (rest r))))
    (method verify (self (param pub STRING "The public key: 32 bytes are read")
                         (param sig STRING "The signature: 64 bytes are read")
                         (param m STRING "The message")
                         . (param span LIST "START, then LENGTH: which bytes of m; default all of m"))
      (doc "Whether sig is pub's signature of the message (RFC 8032 5.1.7): #f for a key that encodes no point, an S at or past the group order, or a signature that does not check. Not constant time."
        (returns BOOL "#t when the signature checks"))
      (def r (%region m span))
      (%verify pub sig m (first r) (first (rest r))))
    (method jit! (self)
      (doc "Build and adopt the compiled scalar multiplication (JIT; ARM64 and x86-64 backends) now, if it can prove itself against the pure-x function. Idempotent. Returns #t when the engine is active, #f when unavailable -- pure-x carries on and results are identical either way. sign and verify never build it on their own: one signature costs about what the build does, so a process that signs or checks more than once asks for it."
        (returns BOOL "#t when the compiled engine is active"))
      (%jit-try!))))

(doc (provide x/codec/ed25519 Ed25519)
  "Ed25519 (RFC 8032): (Ed25519 public seed), (Ed25519 sign seed m [start len]) and (Ed25519 verify pub sig m [start len]). Pure x-lang over x/codec/fe25519 and x/codec/sha512, with an optional differentially-verified JIT engine ((Ed25519 jit!)).")
