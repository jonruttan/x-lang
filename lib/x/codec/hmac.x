; hmac.x -- Hmac: keyed message authentication (RFC 2104) over SHA-2.
;
; TLS 1.3's key schedule is HKDF (x/codec/hkdf), and HKDF is HMAC; its
; Finished messages are an HMAC each.  Everything here is binary -- keys
; and transcripts have NULs inside -- and a string has no length of its
; own past its first NUL, so a binary input is a region (STRING START
; LEN); a plain STRING is its bytes up to that first NUL.  An answer is a
; fresh buffer of exactly the digest's bytes, (Hmac size hash) of them,
; and every step in between carries its length.  The digests are the
; codecs' own, so their compiled engines serve here unchanged.
(module x/codec/hmac)

(import x/codec/sha256)
(import x/codec/sha384)
(import x/codec/sha512)
(import x/codec/hex)

(def %add (prim-ref 'int '+))
(def %sub (prim-ref 'int '-))
(def %byte-len (prim-ref (lit str) (lit byte-len)))
(def %byte-ref (prim-ref (lit str) (lit byte-ref)))
(def %char->int (prim-ref (lit char) (lit ->int)))
(def %make-str (prim-ref (lit str) (lit make)))
(def %str->ptr (prim-ref (lit str) (lit ->ptr)))
(def %pset1 (prim-ref (lit ptr) (lit set!)))

(def %byte (fn (_ s i) (%char->int (%byte-ref s i))))

; A hash: its block size, its output size, and its digest of a byte
; region as hex.
(def %hashes
  (list (list (lit sha256) 64 32 (fn (_ s n) (Sha256 hex-n s n)))
        (list (lit sha384) 128 48 (fn (_ s n) (Sha384 hex-n s n)))
        (list (lit sha512) 128 64 (fn (_ s n) (Sha512 hex-n s n)))))

(def %hash
  (fn (self name l)
    (match ((null? l) (Err raise (lit value) (Str8 append "Hmac: no hash named " (Str8 str name)) name))
           ((eq? (first (first l)) name) (first l))
           (#t (self name (rest l))))))

(def %block-size (fn (_ h) (first (rest h))))
(def %out-size (fn (_ h) (first (rest (rest h)))))
(def %digest-hex (fn (_ h) (first (rest (rest (rest h))))))

; An argument as a region: a STRING is its bytes to the first NUL.
(def %region
  (fn (_ x)
    (if (str? x) (list x 0 (%byte-len x)) x)))

(def %region-len (fn (_ r) (first (rest (rest r)))))

; Regions copied end to end into one fresh buffer: the region of it.
(def %join
  (fn (_ regions)
    (def total ((fn (self rs n) (if (null? rs) n (self (rest rs) (%add n (%region-len (first rs)))))) regions 0))
    (def out (%make-str (if (= total 0) 1 total)))
    (def p (%str->ptr out))
    ((fn (self rs at)
       (unless (null? rs)
         (do (def s (first (first rs)))
             (def start (first (rest (first rs))))
             (def len (%region-len (first rs)))
             ((fn (self i)
                (unless (= i len)
                  (do (%pset1 p (%add at i) (%byte s (%add start i)) 1) (self (%add i 1))))) 0)
             (self (rest rs) (%add at len))))) regions 0)
    (list out 0 total)))

; The digest of joined regions: a fresh buffer of its bytes.
(def %digest
  (fn (_ h regions)
    (def m (%join regions))
    (def bytes (Hex decode-bytes ((%digest-hex h) (first m) (%region-len m))))
    (def out (%make-str (%out-size h)))
    (def p (%str->ptr out))
    ((fn (self i bs) (unless (null? bs) (do (%pset1 p i (first bs) 1) (self (%add i 1) (rest bs))))) 0 bytes)
    out))

; The key padded to the block with zeros (hashed first when longer), each
; byte XORed with pad: the region of a fresh buffer.
(def %pad-key
  (fn (_ h key pad)
    (def k (if (> (%region-len key) (%block-size h)) (list (%digest h (list key)) 0 (%out-size h)) key))
    (def b (%block-size h))
    (def out (%make-str b))
    (def p (%str->ptr out))
    (def s (first k))
    (def start (first (rest k)))
    (def klen (%region-len k))
    ((fn (self i)
       (unless (= i b)
         (do (%pset1 p i (^ pad (if (< i klen) (%byte s (%add start i)) 0)) 1)
             (self (%add i 1))))) 0)
    (list out 0 b)))

(def %mac
  (fn (_ name key msg)
    (def h (%hash name %hashes))
    (def k (%region key))
    (def inner (%digest h (list (%pad-key h k 54) (%region msg))))
    (%digest h (list (%pad-key h k 92) (list inner 0 (%out-size h))))))

(def %hex-of
  (fn (_ s n)
    (Hex encode-bytes ((fn (self i acc) (if (< i 0) acc (self (%sub i 1) (pair (%byte s i) acc)))) (%sub n 1) ()))))

(def-class Hmac ()
  (static
    (method mac (self (param hash SYMBOL "The hash: sha256, sha384 or sha512")
                      (param key ANY "The key: a region (STRING START LEN), or a STRING up to its first NUL")
                      (param msg ANY "The message: a region (STRING START LEN), or a STRING up to its first NUL"))
      (doc "HMAC (RFC 2104) of msg under key with the named SHA-2 hash, as a fresh buffer of exactly the tag's bytes: 32 for sha256, 48 for sha384, 64 for sha512. Binary throughout: give a region for bytes with NULs inside, and read the answer by its size, since a buffer has no length past a NUL."
        (returns STRING "The tag's bytes, (Hmac size hash) of them")
        (example "(Hmac to-hex (Hmac mac (lit sha256) \"key\" \"The quick brown fox jumps over the lazy dog\") 32)" "\"f7bc83f430538424b13298e6aa6fb143ef4d59a14946175997479dbc2d1a3cd8\""))
      (%mac hash key msg))
    (method hex (self (param hash SYMBOL "The hash: sha256, sha384 or sha512")
                      (param key ANY "The key: a region (STRING START LEN), or a STRING up to its first NUL")
                      (param msg ANY "The message: a region (STRING START LEN), or a STRING up to its first NUL"))
      (doc "The HMAC tag as lowercase hex, two characters a byte."
        (returns STRING "Hex text")
        (example "(Hmac hex (lit sha256) \"key\" \"The quick brown fox jumps over the lazy dog\")" "\"f7bc83f430538424b13298e6aa6fb143ef4d59a14946175997479dbc2d1a3cd8\""))
      (%hex-of (%mac hash key msg) (%out-size (%hash hash %hashes))))
    (method size (self (param hash SYMBOL "The hash: sha256, sha384 or sha512"))
      (doc "How many bytes the named hash's digest, and so its HMAC tag, has."
        (returns INTEGER "32, 48 or 64")
        (example "(Hmac size (lit sha384))" "48"))
      (%out-size (%hash hash %hashes)))
    (method digest (self (param hash SYMBOL "The hash: sha256, sha384 or sha512")
                         . (param regions LIST "Regions (STRING START LEN), or STRINGs up to their first NUL, digested end to end"))
      (doc "The plain digest of the regions joined, as a fresh buffer of exactly its bytes -- what TLS's transcript hash needs."
        (returns STRING "The digest's bytes, (Hmac size hash) of them")
        (example "(Hmac to-hex (Hmac digest (lit sha256) \"ab\" \"c\") 32)" "\"ba7816bf8f01cfea414140de5dae2223b00361a396177a9cb410ff61f20015ad\""))
      (%digest (%hash hash %hashes) (List map %region regions)))
    (method to-hex (self (param s STRING "A buffer of bytes")
                         (param n INTEGER "How many of its bytes"))
      (doc "The first n bytes of s as lowercase hex, two characters a byte, NULs included."
        (returns STRING "Hex text")
        (example "(Hmac to-hex \"ab\" 2)" "\"6162\""))
      (%hex-of s n))))

(doc (provide x/codec/hmac Hmac)
  "HMAC (RFC 2104) over SHA-256, SHA-384 and SHA-512: (Hmac mac 'sha256 key msg) answers the tag's bytes, binary-safe through regions.")
