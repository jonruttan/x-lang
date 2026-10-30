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
(import x/codec/mont-jit mont-jit-engine mont-jit-load-bytes! mont-jit-store-bytes mont-jit-to! mont-jit-from! mont-jit-pow!
        mont-jit-one! mont-jit-eq? mont-jit-mul mont-jit-inv!)
(import x/type/vector)
(import x/sys/gc)
; The bit operations through the int doors: the generic ones dispatch
; through the numeric tower, about a hundred objects a call, these none.
; There is no int xor: a ^ b is (a | b) - (a & b).
(import x/core/doors char->int int% int& int* int+ int- int/ int<< int>> int| obj-ref obj-set! ptr-ref ptr-set! str->ptr str-byte-ref str-make)
(def %xor (fn (_ a b) (int- (int| a b) (int& a b))))


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
    (if (or (= top 0) (= (int& (Bytes ref nr (- len 1)) 1) 0)) ()
      (list nr len (- (* 8 len) ((fn (self b z) (if (= (int& b 128) 128) z (self (int& (int<< b 1) 255) (+ z 1)))) top 0))))))

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

(def %len (fn (_ r) (first (rest (rest r)))))
(def %at (fn (_ r i) (char->int (str-byte-ref (first r) (int+ (first (rest r)) i)))))

; Are the n bytes of r from i all v?
(def %run-of?
  (fn (_ r i n v)
    ((fn (self j) (if (= j n) #t (if (= (%at r (int+ i j)) v) (self (int+ j 1)) #f))) 0)))

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
          (def pad (int- (int- (%len em) 3) tl))
          (and (>= pad 8)
               (= (%at em 0) 0)
               (= (%at em 1) 1)
               (%run-of? em 2 pad 255)
               (= (%at em (int+ 2 pad)) 0)
               (Bytes same? (Bytes sub em (int+ 3 pad) tl) t))))))

; EMSA-PKCS1-v1_5-ENCODE (9.2) at k bytes: 00 01, FF bytes, 00, DigestInfo
; of the digest; () when k leaves fewer than eight FF bytes.
(def %v15-encode
  (fn (_ k hash digest)
    (def info (%find hash %digest-info))
    (if (null? info) ()
      (do (def t (Bytes join (Bytes of-hex (first (rest info))) digest))
          (def pad (int- (int- k 3) (%len t)))
          (if (< pad 8) ()
            (Bytes join (Bytes of-list (list 0 1)) (Bytes of-list (List repeat pad 255)) (Bytes of-list (list 0)) t))))))

; --- PSS ----------------------------------------------------------------------

; Eight zero bytes, PSS's M' prefix, in a fresh buffer: made at load, an
; image would bring them back empty.
(def %zero8
  (fn (_)
    (def z (str-make 8))
    (ptr-set! (str->ptr z) 0 0 4)
    (ptr-set! (str->ptr z) 4 0 4)
    (list z 0 8)))

; MGF1 (B.2.1): the hashes of seed and a counter, 0 up, cut to len bytes.
(def %mgf1
  (fn (_ hash seed len)
    (def h (Hmac size hash))
    (def ctr (str-make 4))
    (def cp (str->ptr ctr))
    ((fn (self c acc)
       (if (>= (%len acc) len) (Bytes sub acc 0 len)
         (do (ptr-set! cp 0 (int>> c 24) 1) (ptr-set! cp 1 (int& (int>> c 16) 255) 1)
             (ptr-set! cp 2 (int& (int>> c 8) 255) 1) (ptr-set! cp 3 (int& c 255) 1)
             (self (int+ c 1) (Bytes join acc (list (Hmac digest hash seed (list ctr 0 4)) 0 h))))))
     0 (list ctr 0 0))))

; masked XOR mask into a fresh buffer, four bytes a step and the odd ones
; singly, the top byte then cut to keep's bits: PSS's data block.
(def %unmask
  (fn (_ masked mask keep)
    (def n (%len masked))
    (def out (Bytes copy masked))
    (def p (str->ptr (first out)))
    (def mp (str->ptr (first mask)))
    (def m0 (first (rest mask)))
    ((fn (self i)
       (if (<= (int+ i 4) n)
         (do (ptr-set! p i (%xor (ptr-ref p i 4) (ptr-ref mp (int+ m0 i) 4)) 4) (self (int+ i 4)))
         (unless (= i n)
           (do (ptr-set! p i (%xor (ptr-ref p i 1) (ptr-ref mp (int+ m0 i) 1)) 1) (self (int+ i 1))))))
     0)
    (ptr-set! p 0 (int& (ptr-ref p 0 1) keep) 1)
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
    (def em-len (int>> (+ em-bits 7) 3))
    (def k (%len full))
    (if (or (> em-len k) (< em-len (+ h h 2)) (not (%run-of? full 0 (- k em-len) 0))) #f
      (do (def em (Bytes sub full (- k em-len) em-len))
          (def db-len (- em-len h 1))
          (def masked (Bytes sub em 0 db-len))
          (def hh (Bytes sub em db-len h))
          (def keep (int>> 255 (- (* 8 em-len) em-bits)))
          (if (or (not (= (%at em (- em-len 1)) 188)) (not (= (int& (%at masked 0) (- 255 keep)) 0))) #f
            (do (def db (%unmask masked (%mgf1 hash hh db-len) keep))
                (def salt-at (- db-len h))
                (and (%run-of? db 0 (- salt-at 1) 0)
                     (= (%at db (- salt-at 1)) 1)
                     (Bytes same? hh (list (Hmac digest hash (%zero8) digest (Bytes sub db salt-at h)) 0 h)))))))))

; --- signing ------------------------------------------------------------------

; n zero bytes in a fresh buffer, four a step and the odd ones singly.
(def %zeros
  (fn (_ n)
    (def z (str-make (if (> n 0) n 1)))
    (def p (str->ptr z))
    ((fn (self i)
       (if (<= (int+ i 4) n) (do (ptr-set! p i 0 4) (self (int+ i 4)))
         (unless (>= i n) (do (ptr-set! p i 0 1) (self (int+ i 1))))))
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
    (def em-len (int>> (+ em-bits 7) 3))
    (if (< em-len (+ h h 2)) ()
      (do (def salt (Bytes random h))
          (def hh (list (Hmac digest hash (%zeros 8) digest salt) 0 h))
          (def db-len (- em-len h 1))
          (def one (%zeros 1))
          (ptr-set! (str->ptr (first one)) 0 1 1)
          (def bc (%zeros 1))
          (ptr-set! (str->ptr (first bc)) 0 188 1)
          (def db (Bytes join (%zeros (- db-len h 1)) one salt))
          (def masked (%unmask db (%mgf1 hash hh db-len) (int>> 255 (- (* 8 em-len) em-bits))))
          (Bytes join (%zeros (- k em-len)) masked hh bc)))))

; --- key generation -----------------------------------------------------------
;
; A key of BITS bits is two primes, p of half the bits rounded up and q of
; the rest, each with its top two bits set so that n = p q has all of
; BITS, and neither one more than a multiple of e = 65537, so that e is
; invertible.  A prime is searched for from a random odd start, stepping
; by two: a step is passed over when the small primes' residues, kept
; from the start, say a small prime divides it, and the rest go to
; Miller-Rabin on the prime engine.  d is e^-1 mod (p-1)(q-1), found as
; (1 + k phi) / e with k = -phi^-1 mod e, e being small; iqmp is q^-1 mod
; p, by Fermat on p's engine.
;
; Numbers here are big-endian regions in fresh buffers, worked a byte at
; a time on the prims: a key is made once, and the time goes to the
; powers.

(def %pset1 (fn (_ r i v) (ptr-set! (str->ptr (first r)) (int+ (first (rest r)) i) v 1)))

; The odd primes below 2048, by a sieve, made the first time they are asked
; for, as a vector.
(def %smalls-cache (Vector make 1 ()))
(def %smalls
  (fn (_)
    (when (null? (obj-ref %smalls-cache 1))
      (do (def top 2048)
          (def composite (Vector make top #f))
          (def found
            ((fn (self i acc)
               (if (>= i top) (List reverse acc)
                 (if (obj-ref composite (int+ i 1)) (self (int+ i 2) acc)
                   (do ((fn (self j) (when (< j top) (do (obj-set! composite (int+ j 1) #t) (self (int+ j (int+ i i)))))) (int* i i))
                       (self (int+ i 2) (pair i acc))))))
             3 ()))
          (def v (Vector make (List length found) 0))
          ((fn (self i l) (unless (null? l) (do (obj-set! v (int+ i 1) (first l)) (self (int+ i 1) (rest l))))) 0 found)
          (obj-set! %smalls-cache 1 v)))
    (obj-ref %smalls-cache 1)))



; r mod a small m.
(def %mod-small
  (fn (_ r m)
    (def n (%len r))
    ((fn (self i acc) (if (= i n) acc (self (int+ i 1) (int% (int+ (int* acc 256) (%at r i)) m)))) 0 0)))

; r + v, r's length; () when it carries out of the top.
(def %add-small
  (fn (_ r v)
    (def n (%len r))
    (def out (%zeros n))
    (def carry
      ((fn (self i c)
         (if (< i 0) c
           (do (def s (int+ (%at r i) c))
               (%pset1 out i (int& s 255))
               (self (int- i 1) (int>> s 8)))))
       (int- n 1) v))
    (if (= carry 0) out ())))

; r - v, r's length, r at least v.
(def %sub-small
  (fn (_ r v)
    (def n (%len r))
    (def out (%zeros n))
    ((fn (self i b)
       (unless (< i 0)
         (do (def s (int- (%at r i) b))
             (%pset1 out i (int& s 255))
             (self (int- i 1) (if (< s 0) (int/ (int- 255 s) 256) 0)))))
     (int- n 1) v)
    out))

; a - b, both of a's length, a at least b.
(def %sub-big
  (fn (_ a b)
    (def n (%len a))
    (def out (%zeros n))
    ((fn (self i borrow)
       (unless (< i 0)
         (do (def s (int- (int- (%at a i) (%at b i)) borrow))
             (%pset1 out i (int& s 255))
             (self (int- i 1) (if (< s 0) 1 0)))))
     (int- n 1) 0)
    out))

; r widened to n bytes with leading zeros, or its last n bytes.
(def %width
  (fn (_ r n)
    (def k (%len r))
    (if (>= k n) (Bytes sub r (int- k n) n) (Bytes join (%zeros (int- n k)) r))))

; a b, the two lengths' sum of bytes: columns of byte products summed,
; then the carries.
(def %mul-big
  (fn (_ a b)
    (def an (%len a))
    (def bn (%len b))
    (def n (int+ an bn))
    (def col (Vector make n 0))
    ((fn (self i)
       (unless (= i an)
         (do (def x (%at a i))
             (unless (= x 0)
               ((fn (self j)
                  (unless (= j bn)
                    (do (def k (int+ (int+ i j) 2))
                        (obj-set! col k (int+ (obj-ref col k) (int* x (%at b j))))
                        (self (int+ j 1)))))
                0))
             (self (int+ i 1)))))
     0)
    (def out (%zeros n))
    ((fn (self k c)
       (unless (< k 0)
         (do (def s (int+ (obj-ref col (int+ k 1)) c))
             (%pset1 out k (int& s 255))
             (self (int- k 1) (int>> s 8)))))
     (int- n 1) 0)
    out))

; r v for a small v, three bytes longer than r.
(def %mul-small (fn (_ r v) (%mul-big r (Bytes of-list (list (int& (int>> v 16) 255) (int& (int>> v 8) 255) (int& v 255))))))

; r / m for a small m, r's length; the remainder dropped.
(def %div-small
  (fn (_ r m)
    (def n (%len r))
    (def out (%zeros n))
    ((fn (self i acc)
       (unless (= i n)
         (do (def cur (int+ (int* acc 256) (%at r i)))
             (%pset1 out i (int/ cur m))
             (self (int+ i 1) (int% cur m)))))
     0 0)
    out))

; r shifted right by s bits, r's length.
(def %shr-bits
  (fn (_ r s)
    (def n (%len r))
    (def bytes (int>> s 3))
    (def bits (int& s 7))
    (def out (%zeros n))
    ((fn (self i)
       (unless (< i bytes)
         (do (def lo (%at r (int- i bytes)))
             (def hi (if (> (int- i bytes) 0) (%at r (int- (int- i bytes) 1)) 0))
             (%pset1 out i (int& (int| (int>> lo bits) (int<< hi (int- 8 bits))) 255))
             (self (int- i 1)))))
     (int- n 1))
    out))

; How many low zero bits r has, r not zero.
(def %low-zeros
  (fn (_ r)
    ((fn (self i z)
       (def b (%at r i))
       (if (= b 0) (self (int- i 1) (int+ z 8))
         ((fn (self b z) (if (= (int& b 1) 1) z (self (int>> b 1) (int+ z 1)))) b z)))
     (int- (%len r) 1) 0)))

; How many bits r has, leading zeros not counted.
(def %bit-length
  (fn (_ r)
    (def n (%len r))
    ((fn (self i)
       (if (= i n) 0
         (do (def b (%at r i))
             (if (= b 0) (self (int+ i 1))
               (int+ (int* 8 (int- (int- n i) 1)) ((fn (self b k) (if (= b 0) k (self (int>> b 1) (int+ k 1)))) b 0))))))
     0)))

; Miller-Rabin, rounds bases from 2 up the primes: #t when odd n > 2048
; passes every one.
(def %probable?
  (fn (_ n rounds)
    (def len (%len n))
    (def e (mont-jit-engine (mont-modulus (first n) (first (rest n)) len)))
    (def n1 (%sub-small n 1))
    (def s (%low-zeros n1))
    (def t (%shr-bits n1 s))
    (mont-jit-one! e 1)
    (mont-jit-load-bytes! e 2 (first n1) (first (rest n1)) len)
    (mont-jit-to! e 2 2)
    (def bases (pair 2 ((fn (self i acc) (if (= i (int- rounds 1)) (List reverse acc) (self (int+ i 1) (pair (obj-ref (%smalls) (int+ i 1)) acc)))) 0 ())))
    ((fn (self l)
       (if (null? l) #t
         (do (def a (%add-small (%zeros len) (first l)))
             (mont-jit-load-bytes! e 0 (first a) 0 len)
             (mont-jit-to! e 0 0)
             (mont-jit-pow! e 3 0 (first t) (first (rest t)) len)
             (def holds
               (if (or (mont-jit-eq? e 3 1) (mont-jit-eq? e 3 2)) #t
                 ((fn (self j)
                    (if (= j s) #f
                      (do (mont-jit-mul e 3 3 3)
                          (match ((mont-jit-eq? e 3 2) #t) ((mont-jit-eq? e 3 1) #f) (#t (self (int+ j 1)))))))
                  1)))
             (if holds (self (rest l)) #f))))
     bases)))

; A random odd number of k bits, its top two bits set.
(def %candidate
  (fn (_ k)
    (def n (int>> (int+ k 7) 3))
    (def r (Bytes random n))
    (def top-bits (int- k (int* 8 (int- n 1))))
    (%pset1 r 0 (int& (%at r 0) (int- (int<< 1 top-bits) 1)))
    (def set-bit! (fn (_ b) (def i (int- (int- n 1) (int>> b 3))) (%pset1 r i (int| (%at r i) (int<< 1 (int& b 7))))))
    (set-bit! (int- k 1))
    (set-bit! (int- k 2))
    (set-bit! 0)
    r))

; A prime of k bits, its top two bits set and not 1 mod 65537.
(def %prime
  (fn (_ k)
    (def ps (%smalls))
    (def np (Vector length ps))
    (def rounds (if (>= k 512) 5 10))
    ((fn (self)
       (def c (%candidate k))
       (def rs (Vector make np 0))
       ((fn (self i) (unless (= i np) (do (obj-set! rs (int+ i 1) (%mod-small c (obj-ref ps (int+ i 1)))) (self (int+ i 1))))) 0)
       (def found
         ((fn (self d)
            (if (> d 65536) ()
              (if ((fn (self i) (if (= i np) #f (if (= (int% (int+ (obj-ref rs (int+ i 1)) d) (obj-ref ps (int+ i 1))) 0) #t (self (int+ i 1))))) 0)
                (self (int+ d 2))
                (do (def p (%add-small c d))
                    (if (and (not (null? p)) (= (%bit-length p) k) (not (= (%mod-small p 65537) 1)) (%probable? p rounds))
                      p
                      (do (Heap collect) (self (int+ d 2))))))))
          0))
       (if (null? found) (self) found)))))

; b^x mod m on ints, m small.
(def %pow-small
  (fn (_ b x m)
    ((fn (self b x acc) (if (= x 0) acc (self (int% (int* b b) m) (int>> x 1) (if (= (int& x 1) 1) (int% (int* acc b) m) acc)))) (int% b m) x 1)))

; A key of bits bits: (N E D IQMP P Q), big-endian regions, n and d n's
; length, iqmp p's.
(def %generate
  (fn (_ bits)
    (def kp (int>> (int+ bits 1) 1))
    (def p (%prime kp))
    (def q ((fn (self) ((fn (_ q) (if (and (= (%len q) (%len p)) (Bytes same? q p)) (self) q)) (%prime (int- bits kp))))))
    (def nlen (int>> (int+ bits 7) 3))
    (def n (%width (%mul-big p q) nlen))
    (def phi (%mul-big (%sub-small p 1) (%sub-small q 1)))
    (def m (%mod-small phi 65537))
    (def k (int% (int- 65537 (%pow-small m 65535 65537)) 65537))
    (def d (%width (%div-small (%add-small (%mul-small phi k) 1) 65537) nlen))
    (def plen (%len p))
    (def q1 (%width q plen))
    (def qm (if (%below? q1 p plen) q1 (%sub-big q1 p)))
    (def e (mont-jit-engine (mont-modulus (first p) (first (rest p)) plen)))
    (mont-jit-load-bytes! e 0 (first qm) (first (rest qm)) plen)
    (mont-jit-to! e 0 0)
    (mont-jit-inv! e 1 0)
    (mont-jit-from! e 1 1)
    (def iqmp (list (mont-jit-store-bytes e 1) 0 plen))
    (list n (Bytes of-list (list 1 0 1)) d iqmp p q)))

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
    (method generate (self (param bits INTEGER "The modulus's size in bits, 1024 to 16384"))
      (doc "A new RSA key of bits bits, e = 65537: two primes of half the bits each, their top two bits set, from the kernel's CSPRNG and Miller-Rabin, d = e^-1 mod (p-1)(q-1) and iqmp = q^-1 mod p, the parts an OpenSSH key file holds. Takes seconds: most of it the primes' powers. Raises a label 'value for a size outside 1024..16384."
        (returns LIST "(N E D IQMP P Q): big-endian regions, n and d n's length")
        (sample "(Rsa generate 2048)" "a key sign-pkcs1 signs with and verify-pkcs1 checks"))
      (when (or (< bits 1024) (> bits 16384)) (Err raise (lit value) "Rsa generate: a size outside 1024..16384" bits))
      (%generate bits))
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
