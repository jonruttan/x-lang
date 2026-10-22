; rsa.x -- RSA signature verification (RFC 8017): PKCS#1 v1.5 and PSS.
;
; A signature s under the public key (n, e) is checked by raising it:
; s^e mod n is the encoded message EM, n's length of bytes, which PKCS#1
; v1.5 (9.2) lays out as 00 01, FF bytes, 00 and the DER DigestInfo of
; the hash, and PSS (9.1) as a masked data block holding a salt, the
; hash of the salted message and a closing BC.  The power is
; x/codec/mont-jit's engine for n -- the looping one, an RSA modulus
; being far past unrolling -- with e's bits walked from the top: e is
; 65537 in practice, seventeen squarings and a multiply.  Certificates
; are signed with v1.5; TLS 1.3's CertificateVerify with PSS, its salt as
; long as the hash (RFC 8446 4.2.3).  A PSS signature is made the same
; way, EM raised to the private exponent d: thousands of steps where a
; verification takes eighteen, and variable time, which a server that
; signs a handshake with it accepts.
(module x/codec/rsa)

(import x/codec/bytes)
(import x/codec/hmac)
(import x/codec/mont mont-modulus)
(import x/codec/mont-jit mont-jit-engine mont-jit-load-bytes! mont-jit-store-bytes mont-jit-to! mont-jit-from! mont-jit-pow!)
; The bit operations through the int doors: the generic ones dispatch
; through the numeric tower, about a hundred objects a call, these none.
; There is no int xor: a ^ b is (a | b) - (a & b).
(def %and (prim-ref (lit int) (lit &)))
(def %or (prim-ref (lit int) (lit |)))
(def %shl (prim-ref (lit int) (lit <<)))
(def %shr (prim-ref (lit int) (lit >>)))
(def %isub (prim-ref 'int '-))
(def %xor (fn (_ a b) (%isub (%or a b) (%and a b))))


(def %find (fn (self k l) (if (null? l) () (if (eq? (first (first l)) k) (first l) (self k (rest l))))))

; A big-endian integer's region without its leading zero bytes, DER's
; sign byte among them; one byte stays of a zero.
(def %strip
  (fn (self r)
    (if (and (> (Bytes length r) 1) (= (Bytes ref r 0) 0)) (self (Bytes sub r 1 (- (Bytes length r) 1))) r)))

; The modulus as (REGION LEN BITS), or () when it is even or zero.
(def %modulus
  (fn (_ n)
    (def nr (%strip (Bytes of n)))
    (def len (Bytes length nr))
    (def top (Bytes ref nr 0))
    (if (or (= top 0) (= (%and (Bytes ref nr (- len 1)) 1) 0)) ()
      (list nr len (- (* 8 len) ((fn (self b z) (if (= (%and b 128) 128) z (self (%and (%shl b 1) 255) (+ z 1)))) top 0))))))

; Is big-endian a below b, the two of one length?  Byte by byte from the
; top: cheaper than a pass through limbs, which is most of a verification's
; x.
(def %below?
  (fn (_ a b len)
    ((fn (self i)
       (if (= i len) #f
         (do (def x (Bytes ref a i))
             (def y (Bytes ref b i))
             (if (< x y) #t (if (> x y) #f (self (+ i 1)))))))
     0)))

; s^e mod n as n's length of big-endian bytes, a region, or () when s is
; not n's length or not below n (8.2.2 steps 1 and 2a).
(def %power
  (fn (_ mod e s)
    (def nr (first mod))
    (def len (first (rest mod)))
    (def sr (Bytes of s))
    (def er (Bytes of e))
    (if (not (= (Bytes length sr) len)) ()
      (do (def m (mont-modulus (first nr) (first (rest nr)) len))
          (if (not (%below? sr nr len)) ()
            (do (def eng (mont-jit-engine m))
                (mont-jit-load-bytes! eng 0 (first sr) (first (rest sr)) len)
                (mont-jit-to! eng 0 0)
                (mont-jit-pow! eng 1 0 (first er) (first (rest er)) (Bytes length er))
                (mont-jit-from! eng 1 1)
                (list (mont-jit-store-bytes eng 1) 0 len)))))))

; --- byte access on the prims ------------------------------------------------
;
; The padding checks walk a modulus's length of bytes, 256 or 512: a Bytes
; class call a byte is a hundred objects where a prim is one.

(def %byte-ref (prim-ref (lit str) (lit byte-ref)))
(def %char->int (prim-ref (lit char) (lit ->int)))
(def %make-str (prim-ref (lit str) (lit make)))
(def %str->ptr (prim-ref (lit str) (lit ->ptr)))
(def %pset (prim-ref (lit ptr) (lit set!)))
(def %pref (prim-ref (lit ptr) (lit ref)))
(def %add (prim-ref 'int '+))
(def %sub (prim-ref 'int '-))
(def %len (fn (_ r) (first (rest (rest r)))))
(def %at (fn (_ r i) (%char->int (%byte-ref (first r) (%add (first (rest r)) i)))))

; Are the n bytes of r from i all v?
(def %run-of?
  (fn (_ r i n v)
    ((fn (self j) (if (= j n) #t (if (= (%at r (%add i j)) v) (self (%add j 1)) #f))) 0)))

; --- PKCS#1 v1.5 ------------------------------------------------------------

; DigestInfo's DER before the digest: SEQUENCE { SEQUENCE { OID, NULL }, OCTET STRING }.
; Held as hex and decoded a call at a time, never at load: a state image keeps
; a string's bytes up to its first zero, and these have zeros.
(def %digest-info
  (list (list (lit sha256) "3031300d060960864801650304020105000420")
        (list (lit sha384) "3041300d060960864801650304020205000430")
        (list (lit sha512) "3051300d060960864801650304020305000440")))

; EM is 00 01, at least eight FF bytes, 00, and DigestInfo of the digest.
(def %v15-holds?
  (fn (_ em hash digest)
    (def info (%find hash %digest-info))
    (if (null? info) #f
      (do (def t (Bytes join (Bytes of-hex (first (rest info))) digest))
          (def tl (%len t))
          (def pad (%sub (%sub (%len em) 3) tl))
          (and (>= pad 8)
               (= (%at em 0) 0)
               (= (%at em 1) 1)
               (%run-of? em 2 pad 255)
               (= (%at em (%add 2 pad)) 0)
               (Bytes same? (Bytes sub em (%add 3 pad) tl) t))))))

; EMSA-PKCS1-v1_5-ENCODE (9.2) at k bytes: 00 01, FF bytes, 00, DigestInfo
; of the digest; () when k leaves fewer than eight FF bytes.
(def %v15-encode
  (fn (_ k hash digest)
    (def info (%find hash %digest-info))
    (if (null? info) ()
      (do (def t (Bytes join (Bytes of-hex (first (rest info))) digest))
          (def pad (%sub (%sub k 3) (%len t)))
          (if (< pad 8) ()
            (Bytes join (Bytes of-list (list 0 1)) (Bytes of-list (List repeat pad 255)) (Bytes of-list (list 0)) t))))))

; --- PSS ----------------------------------------------------------------------

; Eight zero bytes, PSS's M' prefix, in a fresh buffer: made at load, an
; image would bring them back empty.
(def %zero8
  (fn (_)
    (def z (%make-str 8))
    (%pset (%str->ptr z) 0 0 4)
    (%pset (%str->ptr z) 4 0 4)
    (list z 0 8)))

; MGF1 (B.2.1): the hashes of seed and a counter, 0 up, cut to len bytes.
(def %mgf1
  (fn (_ hash seed len)
    (def h (Hmac size hash))
    (def ctr (%make-str 4))
    (def cp (%str->ptr ctr))
    ((fn (self c acc)
       (if (>= (%len acc) len) (Bytes sub acc 0 len)
         (do (%pset cp 0 (%shr c 24) 1) (%pset cp 1 (%and (%shr c 16) 255) 1)
             (%pset cp 2 (%and (%shr c 8) 255) 1) (%pset cp 3 (%and c 255) 1)
             (self (%add c 1) (Bytes join acc (list (Hmac digest hash seed (list ctr 0 4)) 0 h))))))
     0 (list ctr 0 0))))

; masked XOR mask into a fresh buffer, four bytes a step and the odd ones
; singly, the top byte then cut to keep's bits: PSS's data block.
(def %unmask
  (fn (_ masked mask keep)
    (def n (%len masked))
    (def out (Bytes copy masked))
    (def p (%str->ptr (first out)))
    (def mp (%str->ptr (first mask)))
    (def m0 (first (rest mask)))
    ((fn (self i)
       (if (<= (%add i 4) n)
         (do (%pset p i (%xor (%pref p i 4) (%pref mp (%add m0 i) 4)) 4) (self (%add i 4)))
         (unless (= i n)
           (do (%pset p i (%xor (%pref p i 1) (%pref mp (%add m0 i) 1)) 1) (self (%add i 1))))))
     0)
    (%pset p 0 (%and (%pref p 0 1) keep) 1)
    out))

; EMSA-PSS-VERIFY (9.1.2) on the power's bytes, emBits = BITS - 1 and the
; salt as long as the hash: the last emLen bytes are EM, anything before
; them zero; EM ends in BC; its data block, unmasked, is zeros, 01 and
; the salt; and the hash it carries is that of eight zero bytes, the
; digest and the salt.
(def %pss-holds?
  (fn (_ full bits hash digest)
    (def h (Hmac size hash))
    (def em-bits (- bits 1))
    (def em-len (%shr (+ em-bits 7) 3))
    (def k (%len full))
    (if (or (> em-len k) (< em-len (+ h h 2)) (not (%run-of? full 0 (- k em-len) 0))) #f
      (do (def em (Bytes sub full (- k em-len) em-len))
          (def db-len (- em-len h 1))
          (def masked (Bytes sub em 0 db-len))
          (def hh (Bytes sub em db-len h))
          (def keep (%shr 255 (- (* 8 em-len) em-bits)))
          (if (or (not (= (%at em (- em-len 1)) 188)) (not (= (%and (%at masked 0) (- 255 keep)) 0))) #f
            (do (def db (%unmask masked (%mgf1 hash hh db-len) keep))
                (def salt-at (- db-len h))
                (and (%run-of? db 0 (- salt-at 1) 0)
                     (= (%at db (- salt-at 1)) 1)
                     (Bytes same? hh (list (Hmac digest hash (%zero8) digest (Bytes sub db salt-at h)) 0 h)))))))))

; --- signing ------------------------------------------------------------------

; n zero bytes in a fresh buffer, four a step and the odd ones singly.
(def %zeros
  (fn (_ n)
    (def z (%make-str (if (> n 0) n 1)))
    (def p (%str->ptr z))
    ((fn (self i)
       (if (<= (%add i 4) n) (do (%pset p i 0 4) (self (%add i 4)))
         (unless (>= i n) (do (%pset p i 0 1) (self (%add i 1))))))
     0)
    (list z 0 n)))

; EMSA-PSS-ENCODE (9.1.1), emBits = BITS - 1 and a fresh salt as long as the
; hash, laid out at K bytes: EM, after a zero byte when emLen is one short
; of K.  The data block is zeros, 01 and the salt, masked by MGF1 of the
; hash of eight zero bytes, the digest and the salt; EM is it, that hash
; and BC.  () when the modulus is too short for the hash.
(def %pss-encode
  (fn (_ k bits hash digest)
    (def h (Hmac size hash))
    (def em-bits (- bits 1))
    (def em-len (%shr (+ em-bits 7) 3))
    (if (< em-len (+ h h 2)) ()
      (do (def salt (Bytes random h))
          (def hh (list (Hmac digest hash (%zeros 8) digest salt) 0 h))
          (def db-len (- em-len h 1))
          (def one (%zeros 1))
          (%pset (%str->ptr (first one)) 0 1 1)
          (def bc (%zeros 1))
          (%pset (%str->ptr (first bc)) 0 188 1)
          (def db (Bytes join (%zeros (- db-len h 1)) one salt))
          (def masked (%unmask db (%mgf1 hash hh db-len) (%shr 255 (- (* 8 em-len) em-bits))))
          (Bytes join (%zeros (- k em-len)) masked hh bc)))))

(def-class Rsa ()
  (static
    (method verify-pkcs1 (self (param n ANY "The modulus, big-endian bytes, a region; DER's leading zero byte may stay")
                               (param e ANY "The public exponent, big-endian bytes, a region")
                               (param hash SYMBOL "sha256, sha384 or sha512")
                               (param digest ANY "The message's digest under hash, a region")
                               (param sig ANY "The signature, n's length of bytes, a region"))
      (doc "RSASSA-PKCS1-v1_5 verification (RFC 8017 8.2.2), as certificates are signed. #t when sig is digest's signature under (n, e); a malformed key or signature answers #f."
        (returns BOOL "#t when the signature holds")
        (sample "(Rsa verify-pkcs1 n e (lit sha256) digest sig)" "#t"))
      (def mod (%modulus n))
      (if (null? mod) #f
        (do (def em (%power mod e sig))
            (if (null? em) #f (%v15-holds? em hash (Bytes of digest))))))
    (method verify-pss (self (param n ANY "The modulus, big-endian bytes, a region; DER's leading zero byte may stay")
                             (param e ANY "The public exponent, big-endian bytes, a region")
                             (param hash SYMBOL "sha256, sha384 or sha512: the digest's hash, and the mask's")
                             (param digest ANY "The message's digest under hash, a region")
                             (param sig ANY "The signature, n's length of bytes, a region"))
      (doc "RSASSA-PSS verification (RFC 8017 8.1.2) with the salt as long as the hash, as TLS 1.3's CertificateVerify is signed. #t when sig is digest's signature under (n, e); a malformed key or signature answers #f."
        (returns BOOL "#t when the signature holds")
        (sample "(Rsa verify-pss n e (lit sha256) digest sig)" "#t"))
      (def mod (%modulus n))
      (if (null? mod) #f
        (do (def em (%power mod e sig))
            (if (null? em) #f (%pss-holds? em (first (rest (rest mod))) hash (Bytes of digest))))))
    (method sign-pss (self (param n ANY "The modulus, big-endian bytes, a region; DER's leading zero byte may stay")
                           (param d ANY "The private exponent, big-endian bytes, a region")
                           (param hash SYMBOL "sha256, sha384 or sha512: the digest's hash, and the mask's")
                           (param digest ANY "The message's digest under hash, a region"))
      (doc "RSASSA-PSS signing (RFC 8017 8.1.1) with a fresh salt as long as the hash, as a TLS 1.3 server signs its CertificateVerify: EM raised to d. Variable time, as all of x's arithmetic is. Raises a label 'value for a modulus that is even, zero or too short for the hash."
        (returns LIST "The signature, n's length of bytes, a region")
        (sample "(Rsa sign-pss n d (lit sha256) digest)" "a signature verify-pss accepts"))
      (def mod (%modulus n))
      (def em (if (null? mod) () (%pss-encode (first (rest mod)) (first (rest (rest mod))) hash (Bytes of digest))))
      (when (null? em) (Err raise (lit value) "Rsa: no modulus a PSS signature fits" ()))
      (%power mod d em))
    (method sign-pkcs1 (self (param n ANY "The modulus, big-endian bytes, a region; DER's leading zero byte may stay")
                             (param d ANY "The private exponent, big-endian bytes, a region")
                             (param hash SYMBOL "sha256, sha384 or sha512")
                             (param digest ANY "The message's digest under hash, a region"))
      (doc "RSASSA-PKCS1-v1_5 signing (RFC 8017 8.2.1): DigestInfo of the digest, padded with FF bytes to n's length, raised to d -- as SSH's rsa-sha2-256 and rsa-sha2-512 sign, and certificates are signed. Deterministic: the same key and digest give the same signature, as OpenSSL's does. Variable time, as all of x's arithmetic is. Raises a label 'value for a modulus that is even, zero or too short for the hash."
        (returns LIST "The signature, n's length of bytes, a region")
        (sample "(Rsa sign-pkcs1 n d (lit sha256) digest)" "a signature verify-pkcs1 accepts"))
      (def mod (%modulus n))
      (def em (if (null? mod) () (%v15-encode (first (rest mod)) hash (Bytes of digest))))
      (when (null? em) (Err raise (lit value) "Rsa: no modulus a PKCS#1 v1.5 signature fits" ()))
      (%power mod d em))))

(doc (provide x/codec/rsa Rsa)
  "RSA signatures (RFC 8017): (Rsa verify-pkcs1 n e hash digest sig) and sign-pkcs1 for PKCS#1 v1.5, as certificates and SSH's rsa-sha2-* are signed, verify-pss for RSASSA-PSS with the salt as long as the hash, as TLS 1.3 signs, and sign-pss to make one; the power on x/codec/mont-jit's looping engine.")
