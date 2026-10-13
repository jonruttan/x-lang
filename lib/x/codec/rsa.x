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
; long as the hash (RFC 8446 4.2.3).  Nothing here signs.
(module x/codec/rsa)

(import x/codec/bytes)
(import x/codec/hmac)
(import x/codec/mont mont-modulus)
(import x/codec/mont-jit mont-jit-engine mont-jit-load-bytes! mont-jit-store-bytes mont-jit-to! mont-jit-from! mont-jit-pow!)

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
    (if (or (= top 0) (= (& (Bytes ref nr (- len 1)) 1) 0)) ()
      (list nr len (- (* 8 len) ((fn (self b z) (if (= (& b 128) 128) z (self (& (<< b 1) 255) (+ z 1)))) top 0))))))

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

; --- PKCS#1 v1.5 ------------------------------------------------------------

; DigestInfo's DER before the digest: SEQUENCE { SEQUENCE { OID, NULL }, OCTET STRING }.
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
          (def pad (- (Bytes length em) 3 (Bytes length t)))
          (and (>= pad 8)
               (Bytes same? em (Bytes join (Bytes of-list (list 0 1)) (Bytes of-list (List repeat pad 255))
                                           (Bytes of-list (list 0)) t)))))))

; --- PSS ----------------------------------------------------------------------

; MGF1 (B.2.1): the hashes of seed and a counter, 0 up, cut to len bytes.
(def %mgf1
  (fn (_ hash seed len)
    (def h (Hmac size hash))
    ((fn (self c acc)
       (if (>= (Bytes length acc) len) (Bytes sub acc 0 len)
         (self (+ c 1)
               (Bytes join acc (list (Hmac digest hash seed (Bytes of-list (list (>> c 24) (& (>> c 16) 255) (& (>> c 8) 255) (& c 255)))) 0 h)))))
     0 (Bytes of-list ()))))

(def %zero-run?
  (fn (_ r start len)
    ((fn (self i) (if (= i len) #t (if (= (Bytes ref r (+ start i)) 0) (self (+ i 1)) #f))) 0)))

; EMSA-PSS-VERIFY (9.1.2) on the power's bytes, emBits = BITS - 1 and the
; salt as long as the hash: the last emLen bytes are EM, anything before
; them zero; EM ends in BC; its data block, unmasked, is zeros, 01 and
; the salt; and the hash it carries is that of eight zero bytes, the
; digest and the salt.
(def %pss-holds?
  (fn (_ full bits hash digest)
    (def h (Hmac size hash))
    (def em-bits (- bits 1))
    (def em-len (>> (+ em-bits 7) 3))
    (def k (Bytes length full))
    (if (or (> em-len k) (< em-len (+ h h 2)) (not (%zero-run? full 0 (- k em-len)))) #f
      (do (def em (Bytes sub full (- k em-len) em-len))
          (def db-len (- em-len h 1))
          (def masked (Bytes sub em 0 db-len))
          (def hh (Bytes sub em db-len h))
          (def keep (>> 255 (- (* 8 em-len) em-bits)))
          (if (or (not (= (Bytes ref em (- em-len 1)) 188)) (not (= (& (Bytes ref masked 0) (- 255 keep)) 0))) #f
            (do (def mask (%mgf1 hash hh db-len))
                (def db (Bytes of-list
                          ((fn (self i acc)
                             (if (< i 0) acc
                               (self (- i 1) (pair (& (^ (Bytes ref masked i) (Bytes ref mask i)) (if (= i 0) keep 255)) acc))))
                           (- db-len 1) ())))
                (def salt-at (- db-len h))
                (and (%zero-run? db 0 (- salt-at 1))
                     (= (Bytes ref db (- salt-at 1)) 1)
                     (Bytes same? hh (list (Hmac digest hash (Bytes of-list (List repeat 8 0)) digest (Bytes sub db salt-at h)) 0 h)))))))))

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
            (if (null? em) #f (%pss-holds? em (first (rest (rest mod))) hash (Bytes of digest))))))))

(doc (provide x/codec/rsa Rsa)
  "RSA signature verification (RFC 8017): (Rsa verify-pkcs1 n e hash digest sig) for PKCS#1 v1.5, as certificates are signed, and verify-pss for RSASSA-PSS with the salt as long as the hash, as TLS 1.3 signs; the power on x/codec/mont-jit's looping engine.")
