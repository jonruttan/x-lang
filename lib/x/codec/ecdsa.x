; ecdsa.x -- Ecdsa: ECDSA signature verification over P-256 and P-384.
;
; Every certificate in the chains TLS servers send today is signed with
; ECDSA over P-256 or P-384 (SEC 1 4.1.4, FIPS 186-5), and so is their
; CertificateVerify.  Verification is: e from the message's hash, w =
; s^-1 mod n, u1 = e w, u2 = r w, R = u1 G + u2 Q, and the signature holds
; when R's x is r mod n.
;
; The arithmetic is Montgomery's (x/codec/mont), modulo the curve's prime
; for points and its order for scalars, each on an engine of named slots
; (x/codec/mont-jit): compiled when the lane builds it and it agrees with
; the pure-x arithmetic, pure x when not -- the same answers, the pure one
; tens of seconds a signature.  Points are Jacobian, (X Y Z) in three
; slots with x = X/Z^2; the curves' a = -3 gives the doubling
; dbl-2001-b's shape, and the addition is add-2007-bl.  R's x is compared
; as X = r Z^2, so no inversion is needed.  The two multiplications are
; one pass (Shamir's trick) over the bits of u1 and u2 with G + Q made
; first.  Only public values are handled, so nothing here needs to run in
; constant time.
(module x/codec/ecdsa)

(import x/codec/bytes)
(import x/codec/mont mont-modulus mont-number mont-bytes-of mont-below?)
(import x/codec/mont-jit mont-jit-engine mont-jit-load! mont-jit-store mont-jit-copy! mont-jit-zero? mont-jit-eq?
        mont-jit-mul mont-jit-add mont-jit-sub mont-jit-to! mont-jit-from! mont-jit-one! mont-jit-inv!
        mont-jit-program mont-jit-run!)

; --- the curves -----------------------------------------------------------

(def %params
  (list
    (list (lit p256) 32
      "ffffffff00000001000000000000000000000000ffffffffffffffffffffffff"
      "ffffffff00000000ffffffffffffffffbce6faada7179e84f3b9cac2fc632551"
      "5ac635d8aa3a93e7b3ebbd55769886bc651d06b0cc53b0f63bce3c3e27d2604b"
      "6b17d1f2e12c4247f8bce6e563a440f277037d812deb33a0f4a13945d898c296"
      "4fe342e2fe1a7f9b8ee7eb4a7c0f9e162bce33576b315ececbb6406837bf51f5")
    (list (lit p384) 48
      "fffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffeffffffff0000000000000000ffffffff"
      "ffffffffffffffffffffffffffffffffffffffffffffffffc7634d81f4372ddf581a0db248b0a77aecec196accc52973"
      "b3312fa7e23ee7e4988e056be3f82d19181d9c6efe8141120314088f5013875ac656398d8a2ed19d2a85c8edd3ec2aef"
      "aa87ca22be8b05378eb1c71ef320ad746e1d3b628ba79b9859f741e082542a385502f25dbf55296c3a545e3872760ab7"
      "3617de4a96262c6f5d9e98bf9292dc29f8f41dbd289a147ce9da3113b5f0b8c00a60b1ce1d7e819d7a431d7c90ea0e5f")))

; The prime engine's slots.  A point is three slots (X Y Z); the
; accumulator, G, Q, G + Q, an addition's result and the temporaries.
(def %ACC 0)
(def %G 3)
(def %Q 6)
(def %GQ 9)
(def %OUT 12)
(def %B 15)
(def %T 16)                 ; 16 temporaries, 16..31
(def %RZ 32)                ; r Z^2 and its kin
(def %RP 33)
(def %X1 34)

; Scalar engine slots.
(def %SE 0)
(def %SS 1)
(def %SW 2)
(def %SR 3)
(def %SU 4)

; A curve, built once a process: (NAME LEN PM NM PE NE NB PROGS), PM and NM the
; prime and order moduli, PE and NE their engines with B and G loaded into
; PE in the form, NB the order's bytes, PROGS its point programs.
(def %built (pair () ()))

(def %load-hex!
  (fn (_ pe pm slot hex len)
    (def r (Bytes of-hex hex))
    (mont-jit-load! pe slot (mont-number pm (first r) 0 len))
    (mont-jit-to! pe slot slot)))

(def %build
  (fn (_ spec)
    (def len (first (rest spec)))
    (def hexes (rest (rest spec)))
    (def pr (Bytes of-hex (first hexes)))
    (def nr (Bytes of-hex (first (rest hexes))))
    (def pm (mont-modulus (first pr) 0 len))
    (def nm (mont-modulus (first nr) 0 len))
    (def pe (mont-jit-engine pm))
    (def ne (mont-jit-engine nm))
    (%load-hex! pe pm %B (List ref 2 hexes) len)
    (%load-hex! pe pm %G (List ref 3 hexes) len)
    (%load-hex! pe pm (+ %G 1) (List ref 4 hexes) len)
    (mont-jit-one! pe (+ %G 2))
    (list (first spec) len pm nm pe ne nr (%programs pe))))

(def %find (fn (self name l) (if (null? l) () (if (eq? (first (first l)) name) (first l) (self name (rest l))))))

(def %curve
  (fn (_ name)
    (def hit (%find name (first %built)))
    (if (not (null? hit)) hit
      (do (def spec (%find name %params))
          (when (null? spec) (Err raise (lit value) (Str8 append "Ecdsa: no curve named " (Str8 str name)) name))
          (def c (%build spec))
          (%set-first! %built (pair c (first %built)))
          c))))

(def %c-len (fn (_ c) (List ref 1 c)))
(def %c-pm (fn (_ c) (List ref 2 c)))
(def %c-nm (fn (_ c) (List ref 3 c)))
(def %c-pe (fn (_ c) (List ref 4 c)))
(def %c-ne (fn (_ c) (List ref 5 c)))
(def %c-nb (fn (_ c) (List ref 6 c)))
(def %c-progs (fn (_ c) (List ref 7 c)))

; --- points, in the prime engine's slots ---------------------------------
;
; A point is the slot of its X, nil standing for the point at infinity.
; The formulas are programs (x/codec/mont-jit): built once a curve, for the
; few places the ladder uses them, and run as a tight loop of native
; calls, since a call through x for each of a verification's ten thousand
; field operations costs more than the operations.

(def %t (fn (_ i) (+ %T i)))

; 2 src into dst (dbl-2001-b, a = -3), src's Y not zero.
(def %dbl-steps
  (fn (_ dst src)
    (def X (+ src 0)) (def Y (+ src 1)) (def Z (+ src 2))
    (def delta (%t 0)) (def gamma (%t 1)) (def beta (%t 2)) (def alpha (%t 3)) (def b4 (%t 4))
    (def x3 (%t 5)) (def y3 (%t 6)) (def z3 (%t 7)) (def u (%t 8)) (def v (%t 9))
    (list (list (lit mul) delta Z Z)
          (list (lit mul) gamma Y Y)
          (list (lit mul) beta X gamma)
          (list (lit sub) u X delta)
          (list (lit add) v X delta)
          (list (lit mul) u u v)
          (list (lit add) alpha u u)
          (list (lit add) alpha alpha u)
          (list (lit add) b4 beta beta)
          (list (lit add) b4 b4 b4)
          (list (lit mul) x3 alpha alpha)
          (list (lit add) u b4 b4)
          (list (lit sub) x3 x3 u)
          (list (lit add) z3 Y Z)
          (list (lit mul) z3 z3 z3)
          (list (lit sub) z3 z3 gamma)
          (list (lit sub) z3 z3 delta)
          (list (lit mul) v gamma gamma)
          (list (lit add) v v v)
          (list (lit add) v v v)
          (list (lit add) v v v)
          (list (lit sub) y3 b4 x3)
          (list (lit mul) y3 alpha y3)
          (list (lit sub) y3 y3 v)
          (list (lit copy) dst x3)
          (list (lit copy) (+ dst 1) y3)
          (list (lit copy) (+ dst 2) z3))))

; a + b (add-2007-bl) in two parts: the first leaves H and R, whose zero
; tests say whether the points are one (double instead) or opposite
; (infinity); the second finishes into dst.
(def %h (%t 6))
(def %r (%t 7))

(def %add1-steps
  (fn (_ a b)
    (def z1z1 (%t 0)) (def z2z2 (%t 1)) (def u1 (%t 2)) (def u2 (%t 3)) (def s1 (%t 4)) (def s2 (%t 5))
    (list (list (lit mul) z1z1 (+ a 2) (+ a 2))
          (list (lit mul) z2z2 (+ b 2) (+ b 2))
          (list (lit mul) u1 a z2z2)
          (list (lit mul) u2 b z1z1)
          (list (lit mul) s1 (+ b 2) z2z2)
          (list (lit mul) s1 (+ a 1) s1)
          (list (lit mul) s2 (+ a 2) z1z1)
          (list (lit mul) s2 (+ b 1) s2)
          (list (lit sub) %h u2 u1)
          (list (lit sub) %r s2 s1))))

(def %add2-steps
  (fn (_ dst a b)
    (def z1z1 (%t 0)) (def z2z2 (%t 1)) (def u1 (%t 2)) (def s1 (%t 4))
    (def i (%t 8)) (def j (%t 9)) (def v (%t 10)) (def x3 (%t 11)) (def y3 (%t 12)) (def z3 (%t 13)) (def w (%t 14))
    (list (list (lit add) i %h %h)
          (list (lit mul) i i i)
          (list (lit mul) j %h i)
          (list (lit add) %r %r %r)
          (list (lit mul) v u1 i)
          (list (lit mul) x3 %r %r)
          (list (lit sub) x3 x3 j)
          (list (lit add) w v v)
          (list (lit sub) x3 x3 w)
          (list (lit sub) y3 v x3)
          (list (lit mul) y3 %r y3)
          (list (lit mul) w s1 j)
          (list (lit add) w w w)
          (list (lit sub) y3 y3 w)
          (list (lit add) z3 (+ a 2) (+ b 2))
          (list (lit mul) z3 z3 z3)
          (list (lit sub) z3 z3 z1z1)
          (list (lit sub) z3 z3 z2z2)
          (list (lit mul) z3 z3 %h)
          (list (lit copy) dst x3)
          (list (lit copy) (+ dst 1) y3)
          (list (lit copy) (+ dst 2) z3))))

; A curve's programs: (DBL ADDS), DBL the accumulator doubled in place and
; ADDS an alist from each addend's slot -- G, Q, G + Q -- to its two parts
; into the accumulator, and G + Q's own for making it.
(def %programs
  (fn (_ e)
    (def adds
      (fn (_ dst a b)
        (list (mont-jit-program e (%add1-steps a b)) (mont-jit-program e (%add2-steps dst a b)))))
    (list (mont-jit-program e (%dbl-steps %ACC %ACC))
          (list (pair %G (adds %ACC %ACC %G))
                (pair %Q (adds %ACC %ACC %Q))
                (pair %GQ (adds %ACC %ACC %GQ)))
          (adds %GQ %G %Q))))

; The accumulator doubled; #f when it became infinity.
(def %double-acc!
  (fn (_ e progs)
    (if (mont-jit-zero? e (+ %ACC 1)) #f
      (do (mont-jit-run! e (first progs)) #t))))

; dst += b by its two programs (dst being a, as the ladder has it); #f when
; the sum is infinity.  One point twice is the doubling.
(def %add-into!
  (fn (_ e progs parts a)
    (mont-jit-run! e (first parts))
    (if (mont-jit-zero? e %h)
      (if (mont-jit-zero? e %r) (%double-acc! e progs) #f)
      (do (mont-jit-run! e (first (rest parts))) #t))))

(def %copy-point!
  (fn (_ e dst src)
    (mont-jit-copy! e dst src)
    (mont-jit-copy! e (+ dst 1) (+ src 1))
    (mont-jit-copy! e (+ dst 2) (+ src 2))))

; u1 G + u2 Q into the accumulator, u1 and u2 big-endian buffers of the
; curve's length: one pass from the top bit, adding G, Q or G + Q as the
; bit pair says.  Answers #f when the result is infinity.  The accumulator
; starts as infinity, so its first addend is copied in rather than added.
(def %shamir!
  (fn (_ e progs len u1 u2)
    (def adds (first (rest progs)))
    (def gq-parts (first (rest (rest progs))))
    ; G + Q into its slots (G = Q for a key equal to G is the doubling's case)
    (mont-jit-run! e (first gq-parts))
    (def gq-ok
      (if (mont-jit-zero? e %h)
        (if (mont-jit-zero? e %r)
          (do (%copy-point! e %ACC %G) (def ok (%double-acc! e progs)) (when ok (%copy-point! e %GQ %ACC)) ok)
          #f)
        (do (mont-jit-run! e (first (rest gq-parts))) #t)))
    ((fn (self j live)
       (if (= j len) live
         (do (def b1 (%byte-at u1 j))
             (def b2 (%byte-at u2 j))
             (self (+ j 1)
                   ((fn (self k live)
                      (if (< k 0) live
                        (do (def live2 (if live (%double-acc! e progs) #f))
                            (def bit1 (& (>> b1 k) 1))
                            (def bit2 (& (>> b2 k) 1))
                            (def slot (match ((and (= bit1 1) (= bit2 1)) (if gq-ok %GQ ())) ((= bit1 1) %G) ((= bit2 1) %Q) (#t ())))
                            (self (- k 1)
                                  (match ((null? slot) (if (and (= bit1 1) (= bit2 1)) live2 live2))
                                         ((not live2) (do (%copy-point! e %ACC slot) #t))
                                         (#t (%add-into! e progs (rest (%assq slot adds)) %ACC)))))))
                    7 live)))))
     0 #f)))

(def %byte-at (fn (_ s i) ((prim-ref (lit char) (lit ->int)) ((prim-ref (lit str) (lit byte-ref)) s i))))
(def %assq (fn (self k l) (if (null? l) () (if (= (first (first l)) k) (first l) (self k (rest l))))))

; Q into its slots from its SEC 1 uncompressed encoding, 04 X Y, checked to
; be on the curve: y^2 = x^3 - 3x + b.  #f when it is not a point.
(def %load-public!
  (fn (_ c pub)
    (def len (%c-len c))
    (def pm (%c-pm c))
    (def e (%c-pe c))
    (if (or (not (= (Bytes length pub) (+ 1 (* 2 len)))) (not (= (Bytes ref pub 0) 4))) #f
      (do (def xr (Bytes copy (Bytes sub pub 1 len)))
          (def yr (Bytes copy (Bytes sub pub (+ 1 len) len)))
          (if (or (not (mont-below? pm (first xr) 0 len)) (not (mont-below? pm (first yr) 0 len))) #f
            (do (mont-jit-load! e %Q (mont-number pm (first xr) 0 len))
                (mont-jit-to! e %Q %Q)
                (mont-jit-load! e (+ %Q 1) (mont-number pm (first yr) 0 len))
                (mont-jit-to! e (+ %Q 1) (+ %Q 1))
                (mont-jit-one! e (+ %Q 2))
                (def a (%t 0)) (def b (%t 1))
                (mont-jit-mul e a %Q %Q)
                (mont-jit-mul e a a %Q)
                (mont-jit-add e b %Q %Q)
                (mont-jit-add e b b %Q)
                (mont-jit-sub e a a b)
                (mont-jit-add e a a %B)
                (mont-jit-mul e b (+ %Q 1) (+ %Q 1))
                (mont-jit-eq? e a b)))))))

; A positive big-endian integer region, leading zeros dropped, as a
; buffer of exactly len bytes; nil when it does not fit.
(def %fixed
  (fn (_ r len)
    (def lead ((fn (self i) (if (and (< i (Bytes length r)) (= (Bytes ref r i) 0)) (self (+ i 1)) i)) 0))
    (def body (Bytes sub r lead (- (Bytes length r) lead)))
    (if (> (Bytes length body) len) ()
      (first (Bytes join (Bytes of-list (List repeat (- len (Bytes length body)) 0)) body)))))


; a < b, big-endian buffers of len bytes.
(def %below?
  (fn (_ a b len)
    ((fn (self i)
       (if (= i len) #f
         (do (def x (Bytes ref (list a 0 len) i))
             (def y (Bytes ref (list b 0 len) i))
             (match ((< x y) #t) ((> x y) #f) (#t (self (+ i 1)))))))
     0)))

(def %verify
  (fn (_ name pub hash r s)
    (def c (%curve name))
    (def len (%c-len c))
    (def pm (%c-pm c))
    (def nm (%c-nm c))
    (def pe (%c-pe c))
    (def ne (%c-ne c))
    (def rb (%fixed (Bytes of r) len))
    (def sb (%fixed (Bytes of s) len))
    (match
      ((or (null? rb) (null? sb)) #f)
      ((or (not (mont-below? nm rb 0 len)) (not (mont-below? nm sb 0 len))) #f)
      ((not (%load-public! c (Bytes of pub))) #f)
      (#t
        (do (mont-jit-load! ne %SR (mont-number nm rb 0 len))
            (mont-jit-load! ne %SS (mont-number nm sb 0 len))
            (if (or (mont-jit-zero? ne %SR) (mont-jit-zero? ne %SS)) #f
              (do ; e: the hash's leftmost bits, as many as n has (whole bytes here)
                  (def h (Bytes of hash))
                  (def hfix (%fixed (if (> (Bytes length h) len) (Bytes sub h 0 len) h) len))
                  (mont-jit-load! ne %SE (mont-number nm hfix 0 len))
                  (mont-jit-to! ne %SE %SE)
                  (mont-jit-to! ne %SS %SS)
                  (mont-jit-to! ne %SR %SR)
                  (mont-jit-inv! ne %SW %SS)
                  (mont-jit-mul ne %SU %SE %SW)
                  (mont-jit-from! ne %SU %SU)
                  (def u1 (mont-bytes-of nm (mont-jit-store ne %SU)))
                  (mont-jit-mul ne %SU %SR %SW)
                  (mont-jit-from! ne %SU %SU)
                  (def u2 (mont-bytes-of nm (mont-jit-store ne %SU)))
                  (def big-r (if (%shamir! pe (%c-progs c) len u1 u2) %ACC ()))
                  (if (null? big-r) #f
                    (do ; R's x is X / Z^2: compare X with r Z^2, and with (r + n) Z^2
                        ; when r + n is still below p
                        (def zz (%t 0))
                        (mont-jit-mul pe zz (+ big-r 2) (+ big-r 2))
                        (def r-plain (mont-number pm rb 0 len))
                        (mont-jit-load! pe %RP r-plain)
                        (mont-jit-to! pe %RP %RP)
                        (mont-jit-mul pe %RZ %RP zz)
                        (or (mont-jit-eq? pe big-r %RZ)
                            (do (mont-jit-load! pe %X1 (mont-number pm (first (%c-nb c)) 0 len))
                                (mont-jit-load! pe (%t 1) r-plain)
                                (mont-jit-add pe %X1 %X1 (%t 1))
                                (def sum (mont-jit-store pe %X1))
                                ; the sum wrapped past p exactly when it came out below r
                                (and (%below? (mont-bytes-of pm r-plain) (mont-bytes-of pm sum) len)
                                     (do (mont-jit-to! pe %X1 %X1)
                                         (mont-jit-mul pe %RZ %X1 zz)
                                         (mont-jit-eq? pe big-r %RZ)))))))))))))))

; A DER ECDSA-Sig-Value, SEQUENCE { INTEGER r, INTEGER s }, as (R S)
; regions; nil when it is not one.
(def %der-sig
  (fn (_ sig)
    (guard (e ())
      (do (def rd (Bytes reader sig))
          (unless (= (Bytes get-u8 rd) 48) (Err raise (lit value) "not a SEQUENCE" ()))
          (def seq-len (%der-len rd))
          (def body (Bytes reader (Bytes get rd seq-len)))
          (unless (= (Bytes left rd) 0) (Err raise (lit value) "bytes after the SEQUENCE" ()))
          (def r (%der-int body))
          (def s (%der-int body))
          (unless (= (Bytes left body) 0) (Err raise (lit value) "bytes after s" ()))
          (list r s)))))

(def %der-len
  (fn (_ rd)
    (def b (Bytes get-u8 rd))
    (match ((< b 128) b)
           ((= b 129) (Bytes get-u8 rd))
           ((= b 130) (Bytes get-u16 rd))
           (#t (Err raise (lit value) "a DER length too long" b)))))

(def %der-int
  (fn (_ rd)
    (unless (= (Bytes get-u8 rd) 2) (Err raise (lit value) "not an INTEGER" ()))
    (def len (%der-len rd))
    (when (= len 0) (Err raise (lit value) "an empty INTEGER" ()))
    (def v (Bytes get rd len))
    (when (>= (Bytes ref v 0) 128) (Err raise (lit value) "a negative INTEGER" ()))
    v))

(def-class Ecdsa ()
  (static
    (method verify (self (param curve SYMBOL "p256 or p384")
                         (param public ANY "The public key: SEC 1 uncompressed, 04 X Y, a region")
                         (param hash ANY "The message's hash, a region; cut to the curve's size when longer")
                         (param r ANY "r, a big-endian region")
                         (param s ANY "s, a big-endian region"))
      (doc "#t when (r, s) is a valid ECDSA signature by public over hash (SEC 1 4.1.4), #f otherwise: a key not on the curve, an r or s outside 1..n-1 and a wrong signature all answer #f."
        (returns BOOL "#t when the signature holds")
        (sample "(Ecdsa verify (lit p256) pub hash r s)" "#t"))
      (%verify curve public hash r s))
    (method verify-der (self (param curve SYMBOL "p256 or p384")
                             (param public ANY "The public key: SEC 1 uncompressed, 04 X Y, a region")
                             (param hash ANY "The message's hash, a region")
                             (param sig ANY "The DER ECDSA-Sig-Value, SEQUENCE { r, s }, a region"))
      (doc "verify, with the signature as X.509 and TLS carry it: DER SEQUENCE { INTEGER r, INTEGER s }. A malformed signature answers #f."
        (returns BOOL "#t when the signature holds")
        (sample "(Ecdsa verify-der (lit p256) pub hash der)" "#t"))
      (def rs (%der-sig (Bytes of sig)))
      (if (null? rs) #f (%verify curve public hash (first rs) (first (rest rs)))))))

(doc (provide x/codec/ecdsa Ecdsa)
  "ECDSA verification over P-256 and P-384 (SEC 1 4.1.4): (Ecdsa verify curve public hash r s), and verify-der for a DER signature, on x/codec/mont-jit's engines.")
