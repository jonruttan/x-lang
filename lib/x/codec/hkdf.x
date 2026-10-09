; hkdf.x -- Hkdf: the HMAC-based key derivation function (RFC 5869).
;
; TLS 1.3's key schedule (RFC 8446 7.1) is HKDF-Extract and HKDF-Expand
; over the cipher suite's hash; its Expand-Label is the TLS module's, on
; top of these two.  Inputs are binary, as x/codec/hmac's are: a region
; (STRING START LEN), or a STRING up to its first NUL -- except the
; pseudorandom key, which as a plain buffer is read as the hash's size of
; bytes, since that is what Extract answers.  Answers are fresh buffers
; of exactly the bytes asked for.
(module x/codec/hkdf)

(import x/codec/hmac)

(def %add (prim-ref 'int '+))
(def %sub (prim-ref 'int '-))
(def %byte-len (prim-ref (lit str) (lit byte-len)))
(def %byte-ref (prim-ref (lit str) (lit byte-ref)))
(def %char->int (prim-ref (lit char) (lit ->int)))
(def %make-str (prim-ref (lit str) (lit make)))
(def %str->ptr (prim-ref (lit str) (lit ->ptr)))
(def %pset1 (prim-ref (lit ptr) (lit set!)))

(def %byte (fn (_ s i) (%char->int (%byte-ref s i))))

(def %region
  (fn (_ x)
    (if (str? x) (list x 0 (%byte-len x)) x)))

; T(1) | T(2) | ... until len bytes are written: T(i) = HMAC(prk, T(i-1) |
; info | i), T(0) empty.
(def %expand
  (fn (_ hash prk info len)
    (def hl (Hmac size hash))
    (when (> len (* 255 hl))
      (Err raise (lit value) "Hkdf expand: more than 255 blocks asked for" len))
    (def key (if (str? prk) (list prk 0 hl) prk))
    (def out (%make-str len))
    (def p (%str->ptr out))
    (def ctr (%make-str 1))
    (def cp (%str->ptr ctr))
    ((fn (self i prev at)
       (unless (>= at len)
         (do (%pset1 cp 0 i 1)
             (def t (Hmac mac hash key (%join prev info ctr)))
             (def n (if (> hl (%sub len at)) (%sub len at) hl))
             ((fn (self j) (unless (= j n) (do (%pset1 p (%add at j) (%byte t j) 1) (self (%add j 1))))) 0)
             (self (%add i 1) (list t 0 hl) (%add at hl)))))
     1 () 0)
    out))

; T(i-1) | info | i as one region, for the HMAC's message.
(def %join
  (fn (_ prev info ctr)
    (def regions (if (null? prev) (list (%region info) (list ctr 0 1)) (list prev (%region info) (list ctr 0 1))))
    (def total ((fn (self rs n) (if (null? rs) n (self (rest rs) (%add n (first (rest (rest (first rs)))))))) regions 0))
    (def out (%make-str total))
    (def p (%str->ptr out))
    ((fn (self rs at)
       (unless (null? rs)
         (do (def r (first rs))
             (def l (first (rest (rest r))))
             ((fn (self i)
                (unless (= i l)
                  (do (%pset1 p (%add at i) (%byte (first r) (%add (first (rest r)) i)) 1) (self (%add i 1))))) 0)
             (self (rest rs) (%add at l))))) regions 0)
    (list out 0 total)))

(def-class Hkdf ()
  (static
    (method extract (self (param hash SYMBOL "The hash: sha256, sha384 or sha512")
                          (param salt ANY "The salt: a region (STRING START LEN), or a STRING up to its first NUL; empty means HashLen zeros, as the RFC says")
                          (param ikm ANY "The input keying material: a region, or a STRING up to its first NUL"))
      (doc "HKDF-Extract (RFC 5869 2.2): the pseudorandom key HMAC(salt, ikm), as a fresh buffer of (Hmac size hash) bytes. An empty salt and HashLen zero bytes give the same key, since HMAC pads its key with zeros."
        (returns STRING "The pseudorandom key's bytes")
        (example "(Hmac to-hex (Hkdf extract (lit sha256) \"salt\" \"secret\") 32)" "\"98e5340f0f4f96d2b80c2a90da0d03cf46c35e9492918cc7af73d9a39efa5981\""))
      (Hmac mac hash salt ikm))
    (method expand (self (param hash SYMBOL "The hash: sha256, sha384 or sha512")
                         (param prk ANY "The pseudorandom key: a buffer of the hash's size of bytes, as Extract answers, or a region")
                         (param info ANY "The context: a region, or a STRING up to its first NUL")
                         (param len INTEGER "How many bytes of output keying material, at most 255 times the hash's size"))
      (doc "HKDF-Expand (RFC 5869 2.3): len bytes of output keying material from prk and info, as a fresh buffer."
        (returns STRING "len bytes")
        (example "(Hmac to-hex (Hkdf expand (lit sha256) (Hkdf extract (lit sha256) \"salt\" \"secret\") \"info\" 8) 8)" "\"f6d2fcc47cb939de\""))
      (%expand hash prk info len))))

(doc (provide x/codec/hkdf Hkdf)
  "HKDF (RFC 5869) over SHA-256, SHA-384 and SHA-512: (Hkdf extract hash salt ikm) and (Hkdf expand hash prk info len), binary-safe.")
