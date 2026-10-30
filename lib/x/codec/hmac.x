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
(import x/codec/bytes)
; The bit operations through the int doors: the generic ones dispatch
; through the numeric tower, about a hundred objects a call, these none.
; There is no int xor: a ^ b is (a | b) - (a & b).
(import x/core/doors char->int int& int+ int- int<< int>> int| ptr-ref ptr-set! str->ptr str-byte-len str-byte-ref str-make)
(def %xor (fn (_ a b) (int- (int| a b) (int& a b))))



(def %byte (fn (_ s i) (char->int (str-byte-ref s i))))

; A hash: its block size, its output size, and its digest of a byte
; region as hex.
(def %hashes
  (list (list (lit sha256) 64 32 (fn (_ s n) (Sha256 bytes-n s n)))
        (list (lit sha384) 128 48 (fn (_ s n) (Sha384 bytes-n s n)))
        (list (lit sha512) 128 64 (fn (_ s n) (Sha512 bytes-n s n)))))

(def %hash
  (fn (self name l)
    (match ((null? l) (Err raise (lit value) (Str8 append "Hmac: no hash named " (Str8 str name)) name))
           ((eq? (first (first l)) name) (first l))
           (#t (self name (rest l))))))

(def %block-size (fn (_ h) (first (rest h))))
(def %out-size (fn (_ h) (first (rest (rest h)))))
(def %digest-bytes (fn (_ h) (first (rest (rest (rest h))))))

; An argument as a region: a STRING is its bytes to the first NUL.
(def %region
  (fn (_ x)
    (if (str? x) (list x 0 (str-byte-len x)) x)))

(def %region-len (fn (_ r) (first (rest (rest r)))))

; Regions copied end to end into one fresh buffer: the region of it.  Two
; at a time through Bytes join, which copies by memcpy; a caller hands
; over one to three regions.
(def %join
  (fn (_ regions)
    (match ((null? (rest regions)) (Bytes join (first regions)))
           ((null? (rest (rest regions))) (Bytes join (first regions) (first (rest regions))))
           (#t ((fn (self rs acc) (if (null? rs) acc (self (rest rs) (Bytes join acc (first rs)))))
                (rest regions) (Bytes join (first regions)))))))

; The digest of joined regions: a fresh buffer of its bytes, straight from
; the hash's words.
(def %digest
  (fn (_ h regions)
    (def m (%join regions))
    ((%digest-bytes h) (first m) (%region-len m))))


; The key padded to the block with zeros (hashed first when longer), each
; byte XORed with pad: the region of a fresh buffer.  The key and its zeros
; are copied in by memcpy (Bytes join), and the zeroing and the XOR run four
; bytes at a time, a quarter of the steps a byte loop takes in x.  The zeros
; are made a call at a time, never at load: a state image keeps a string's
; bytes up to its first zero, so a zeroed buffer held by the module comes
; back from one empty.
(def %pad-key
  (fn (_ h key pad)
    (def k (if (> (%region-len key) (%block-size h)) (list (%digest h (list key)) 0 (%out-size h)) key))
    (def b (%block-size h))
    (def n (int- b (%region-len k)))
    (def z (str-make (int+ n 4)))
    (def zp (str->ptr z))
    ((fn (self i) (when (< i n) (do (ptr-set! zp i 0 4) (self (int+ i 4))))) 0)
    (def r (Bytes join k (list z 0 n)))
    (def p (str->ptr (first r)))
    (def pad4 (* pad 16843009))
    ((fn (self i)
       (unless (= i b)
         (do (ptr-set! p i (%xor pad4 (ptr-ref p i 4)) 4)
             (self (int+ i 4))))) 0)
    r))

(def %mac
  (fn (_ name key msg)
    (def h (%hash name %hashes))
    (def k (%region key))
    (def inner (%digest h (list (%pad-key h k 54) (%region msg))))
    (%digest h (list (%pad-key h k 92) (list inner 0 (%out-size h))))))

(def %hex-of
  (fn (_ s n)
    (Hex encode-bytes ((fn (self i acc) (if (< i 0) acc (self (int- i 1) (pair (%byte s i) acc)))) (int- n 1) ()))))

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
