; chacha20-poly1305.x -- ChaCha20Poly1305: the AEAD of RFC 8439 2.8.
;
; TLS 1.3's TLS_CHACHA20_POLY1305_SHA256 seals every record with it: the
; Poly1305 key is the first 32 bytes of ChaCha20's block 0 for the key and
; nonce, the plaintext is XORed with the keystream from block 1, and the
; tag is Poly1305 over the additional data, the ciphertext, each padded to
; sixteen bytes, and their two lengths as 64-bit little-endian numbers.
; (openssh's chacha20-poly1305 is another construction, x-ssh's own.)
; Inputs and answers are regions (BUF START LEN), as x/codec/bytes says.
(module x/codec/chacha20-poly1305)

(import x/codec/chacha20)
(import x/codec/poly1305)
(import x/codec/bytes)

(def %add (prim-ref 'int '+))
(def %sub (prim-ref 'int '-))

(def %make-str (prim-ref (lit str) (lit make)))
(def %str->ptr (prim-ref (lit str) (lit ->ptr)))
(def %pset1 (prim-ref (lit ptr) (lit set!)))
(def %len (fn (_ r) (first (rest (rest r)))))

; The buffers below are made a call at a time, never at load: a state image
; keeps a string's bytes up to its first zero, so a zeroed buffer held by the
; module comes back from one empty.

; ChaCha20's 16-byte IV: a 32-bit little-endian block counter, 0 or 1, then
; the 96-bit nonce.
(def %iv
  (fn (_ counter nonce)
    (def c (%make-str 4))
    (%pset1 (%str->ptr c) 0 0 4)
    (%pset1 (%str->ptr c) 0 counter 1)
    (first (Bytes join (list c 0 4) nonce))))

; A region as a buffer of its own, starting at 0, for the ciphers' key and
; IV arguments, which read from a buffer's first byte.
(def %buffer
  (fn (_ r) (first (Bytes copy r))))

(def %pad16 (fn (_ n) (& (%sub 16 (& n 15)) 15)))

; Sixteen zero bytes for the pads, then the two lengths as 64-bit
; little-endian numbers: thirty-two bytes.
(def %tail
  (fn (_ a c)
    (def b (%make-str 32))
    (def p (%str->ptr b))
    ((fn (self k) (unless (= k 16) (do (%pset1 p k 0 4) (self (%add k 4))))) 0)
    ((fn (self k) (unless (= k 8)
                    (do (%pset1 p (%add k 16) (& (>> a (<< k 3)) 255) 1)
                        (%pset1 p (%add k 24) (& (>> c (<< k 3)) 255) 1)
                        (self (%add k 1)))))
     0)
    b))

; The MAC's input in one buffer, its pieces copied in by memcpy.
(def %tag
  (fn (_ key nonce aad ct)
    (def otk (ChaCha20 block key (%iv 0 nonce)))
    (def la (%len aad))
    (def lc (%len ct))
    (def t (%tail la lc))
    (def m (Bytes join aad (list t 0 (%pad16 la)) ct (list t 0 (%pad16 lc)) (list t 16 16)))
    (list (Poly1305 mac otk (first m) 0 (%len m)) 0 16)))

(def %xor
  (fn (_ key nonce r)
    (list (ChaCha20 xor key (%iv 1 nonce) (first r) (first (rest r)) (%len r)) 0 (%len r))))

(def %check-sizes
  (fn (_ key nonce)
    (unless (= (Bytes length key) 32) (Err raise (lit value) "ChaCha20Poly1305: the key is 32 bytes" (Bytes length key)))
    (unless (= (Bytes length nonce) 12) (Err raise (lit value) "ChaCha20Poly1305: the nonce is 12 bytes" (Bytes length nonce)))))

(def-class ChaCha20Poly1305 ()
  (static
    (method seal (self (param key ANY "The 32-byte key, a region")
                       (param nonce ANY "The 12-byte nonce, a region; never twice under one key")
                       (param aad ANY "Additional data, authenticated but not encrypted: a region, or a STRING up to its first NUL")
                       (param pt ANY "The plaintext: a region, or a STRING up to its first NUL"))
      (doc "Encrypt and authenticate (RFC 8439 2.8): the ciphertext, as long as the plaintext, followed by the 16-byte tag, in a fresh buffer."
        (returns LIST "(BUF 0 LEN+16)")
        (example "(Bytes length (ChaCha20Poly1305 seal (Bytes of-hex \"0000000000000000000000000000000000000000000000000000000000000000\") (Bytes of-hex \"000000000000000000000000\") (Bytes of-hex \"\") (Bytes of-hex \"0102\")))" "18"))
      (def kr (Bytes of key))
      (def nr (Bytes of nonce))
      (%check-sizes kr nr)
      (def k (%buffer kr))
      (def n (list (%buffer nr) 0 12))
      (def ct (%xor k n (Bytes of pt)))
      (Bytes join ct (%tag k n (Bytes of aad) ct)))
    (method open (self (param key ANY "The 32-byte key, a region")
                       (param nonce ANY "The 12-byte nonce, a region")
                       (param aad ANY "The additional data the sealer gave: a region, or a STRING up to its first NUL")
                       (param sealed ANY "The ciphertext and its 16-byte tag, a region"))
      (doc "Check and decrypt (RFC 8439 2.8): the plaintext in a fresh buffer. The tag is checked first, over every byte in constant time; one that does not match raises a label 'value and nothing is decrypted."
        (returns LIST "(BUF 0 LEN-16)")
        (example "((fn (_ k n) (Bytes hex (ChaCha20Poly1305 open k n (Bytes of-hex \"aa\") (ChaCha20Poly1305 seal k n (Bytes of-hex \"aa\") (Bytes of-hex \"0102\"))))) (Bytes of-hex \"0000000000000000000000000000000000000000000000000000000000000000\") (Bytes of-hex \"000000000000000000000000\"))" "\"0102\""))
      (def kr (Bytes of key))
      (def nr (Bytes of nonce))
      (def sr (Bytes of sealed))
      (%check-sizes kr nr)
      (when (< (Bytes length sr) 16) (Err raise (lit value) "ChaCha20Poly1305: shorter than its tag" (Bytes length sr)))
      (def k (%buffer kr))
      (def n (list (%buffer nr) 0 12))
      (def ct (Bytes sub sr 0 (%sub (Bytes length sr) 16)))
      (def tag (Bytes sub sr (%sub (Bytes length sr) 16) 16))
      (unless (Bytes same? tag (%tag k n (Bytes of aad) ct))
        (Err raise (lit value) "ChaCha20Poly1305: the tag does not match" ()))
      (%xor k n ct))))

(doc (provide x/codec/chacha20-poly1305 ChaCha20Poly1305)
  "The ChaCha20-Poly1305 AEAD (RFC 8439 2.8): (ChaCha20Poly1305 seal key nonce aad pt) and (ChaCha20Poly1305 open key nonce aad sealed), over regions.")
