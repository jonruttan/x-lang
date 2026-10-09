; net/tls-keys.x -- TlsKeys: the TLS 1.3 key schedule (RFC 8446 7.1, 4.4.4).
;
; Every secret a TLS 1.3 session uses comes from HKDF over the cipher
; suite's hash: the early secret from zeros, the handshake secret from the
; key exchange's shared secret, the master secret from zeros again, and
; between them traffic secrets bound to the transcript hash so far.  A
; traffic secret gives a record key and IV (7.3), and a Finished message is
; an HMAC under a key from the handshake traffic secret (4.4.4).  These are
; pure functions over regions (BUF START LEN), as x/codec/bytes has them,
; so RFC 8448's traces check them byte for byte without a network
; (tests/x/specs/lib/tls-keys.spec.md).  The steps that chain several
; HMACs show samples rather than examples: pure x they cost the doctest
; batch seconds, and the spec checks every one against the RFC.
(module x/net/tls-keys)

(import x/codec/bytes)
(import x/codec/hmac)
(import x/codec/hkdf)

; HkdfLabel (7.1): the output length as u16, then "tls13 " and the label,
; then the context, each with a one-byte length in front.
(def %hkdf-label
  (fn (_ label context len)
    (def full (Str8 append "tls13 " label))
    (def w (Bytes writer))
    (Bytes put-u16 w len)
    (Bytes put-u8 w (Str8 length full))
    (Bytes put w full)
    (Bytes put-u8 w (Bytes length context))
    (Bytes put w context)
    (Bytes written w)))

; A fresh buffer the HKDF and HMAC codecs answer, as the region of its first
; len bytes.
(def %cut (fn (_ buf len) (list buf 0 len)))

(def %no-bytes (Bytes of-list ()))

(def-class TlsKeys ()
  (static
    (method expand-label (self (param hash SYMBOL "The suite's hash: sha256 or sha384")
                               (param secret LIST "The secret, a region")
                               (param label STRING "The label, without its tls13 prefix")
                               (param context ANY "The context, a region (a transcript hash, or empty)")
                               (param len INTEGER "How many bytes"))
      (doc "HKDF-Expand-Label (RFC 8446 7.1): len bytes from secret, label and context."
        (returns LIST "(BUF 0 len)")
        (example "(Bytes hex (TlsKeys expand-label (lit sha256) (Bytes of-hex \"b67b7d690cc16c4e75e54213cb2d37b4e9c912bcded9105d42befd59d391ad38\") \"iv\" (Bytes of-list ()) 12))" "\"5d313eb2671276ee13000b30\""))
      (%cut (Hkdf expand hash secret (%hkdf-label label (Bytes of context) len) len) len))
    (method derive-secret (self (param hash SYMBOL "The suite's hash")
                                (param secret LIST "The secret, a region")
                                (param label STRING "The label, without its tls13 prefix")
                                (param th LIST "The transcript hash, a region"))
      (doc "Derive-Secret (RFC 8446 7.1): Expand-Label with the transcript hash as context, the hash's size of bytes."
        (returns LIST "(BUF 0 HashLen)")
        (sample "(Bytes length (TlsKeys derive-secret (lit sha256) (Bytes of-hex \"00\") \"derived\" (TlsKeys empty-hash (lit sha256))))" "32"))
      (TlsKeys expand-label hash secret label th (Hmac size hash)))
    (method empty-hash (self (param hash SYMBOL "The suite's hash"))
      (doc "The hash of no bytes, the context Derive-Secret's \"derived\" steps take."
        (returns LIST "(BUF 0 HashLen)")
        (example "(Bytes hex (TlsKeys empty-hash (lit sha256)))" "\"e3b0c44298fc1c149afbf4c8996fb92427ae41e4649b934ca495991b7852b855\""))
      (%cut (Hmac digest hash %no-bytes) (Hmac size hash)))
    (method transcript-hash (self (param hash SYMBOL "The suite's hash")
                                  (param messages LIST "The handshake messages so far, a region"))
      (doc "Transcript-Hash (RFC 8446 4.4.1): the hash of the handshake messages, header and all, end to end."
        (returns LIST "(BUF 0 HashLen)")
        (example "(Bytes length (TlsKeys transcript-hash (lit sha256) (Bytes of-hex \"0100\")))" "32"))
      (%cut (Hmac digest hash messages) (Hmac size hash)))
    (method early-secret (self (param hash SYMBOL "The suite's hash"))
      (doc "The early secret with no pre-shared key: HKDF-Extract of HashLen zeros under a zero salt."
        (returns LIST "(BUF 0 HashLen)")
        (example "(Bytes hex (TlsKeys early-secret (lit sha256)))" "\"33ad0a1c607ec03b09e6cd9893680ce210adf300aa1f2660e1b22e10f170f92a\""))
      (def zeros (Bytes of-list (List repeat (Hmac size hash) 0)))
      (%cut (Hkdf extract hash %no-bytes zeros) (Hmac size hash)))
    (method handshake-secret (self (param hash SYMBOL "The suite's hash")
                                   (param shared LIST "The key exchange's shared secret, a region"))
      (doc "The handshake secret: HKDF-Extract of the shared secret under Derive-Secret(early secret, \"derived\", \"\")."
        (returns LIST "(BUF 0 HashLen)")
        (sample "(Bytes length (TlsKeys handshake-secret (lit sha256) (Bytes of-list (List repeat 32 1))))" "32"))
      (def salt (TlsKeys derive-secret hash (TlsKeys early-secret hash) "derived" (TlsKeys empty-hash hash)))
      (%cut (Hkdf extract hash salt shared) (Hmac size hash)))
    (method master-secret (self (param hash SYMBOL "The suite's hash")
                                (param hs LIST "The handshake secret, a region"))
      (doc "The master secret: HKDF-Extract of HashLen zeros under Derive-Secret(handshake secret, \"derived\", \"\")."
        (returns LIST "(BUF 0 HashLen)")
        (sample "(Bytes length (TlsKeys master-secret (lit sha256) (Bytes of-list (List repeat 32 1))))" "32"))
      (def salt (TlsKeys derive-secret hash hs "derived" (TlsKeys empty-hash hash)))
      (def zeros (Bytes of-list (List repeat (Hmac size hash) 0)))
      (%cut (Hkdf extract hash salt zeros) (Hmac size hash)))
    (method traffic-keys (self (param hash SYMBOL "The suite's hash")
                               (param secret LIST "A traffic secret, a region")
                               (param key-len INTEGER "The AEAD's key length: 32 for ChaCha20-Poly1305"))
      (doc "The record key and IV a traffic secret gives (RFC 8446 7.3): (KEY IV), each a region; the IV is 12 bytes."
        (returns LIST "(KEY IV)")
        (example "(Bytes hex (first (rest (TlsKeys traffic-keys (lit sha256) (Bytes of-hex \"b67b7d690cc16c4e75e54213cb2d37b4e9c912bcded9105d42befd59d391ad38\") 16))))" "\"5d313eb2671276ee13000b30\""))
      (list (TlsKeys expand-label hash secret "key" %no-bytes key-len)
            (TlsKeys expand-label hash secret "iv" %no-bytes 12)))
    (method finished (self (param hash SYMBOL "The suite's hash")
                           (param ts LIST "The sender's handshake traffic secret, a region")
                           (param th LIST "The transcript hash the Finished covers, a region"))
      (doc "The Finished verify_data (RFC 8446 4.4.4): HMAC of the transcript hash under Expand-Label(secret, \"finished\", \"\", HashLen)."
        (returns LIST "(BUF 0 HashLen)")
        (sample "(Bytes length (TlsKeys finished (lit sha256) (Bytes of-list (List repeat 32 1)) (TlsKeys empty-hash (lit sha256))))" "32"))
      (def key (TlsKeys expand-label hash ts "finished" %no-bytes (Hmac size hash)))
      (%cut (Hmac mac hash key th) (Hmac size hash)))
    (method next-traffic-secret (self (param hash SYMBOL "The suite's hash")
                                      (param secret LIST "The current application traffic secret, a region"))
      (doc "The application traffic secret after a KeyUpdate (RFC 8446 7.2): Expand-Label(secret, \"traffic upd\", \"\", HashLen)."
        (returns LIST "(BUF 0 HashLen)")
        (sample "(Bytes length (TlsKeys next-traffic-secret (lit sha256) (Bytes of-list (List repeat 32 1))))" "32"))
      (TlsKeys expand-label hash secret "traffic upd" %no-bytes (Hmac size hash)))))

(doc (provide x/net/tls-keys TlsKeys)
  "The TLS 1.3 key schedule (RFC 8446 7.1): Expand-Label, Derive-Secret, the early, handshake and master secrets, traffic keys and Finished, over regions.")
