# ChaCha20Poly1305
# @weight 4

The AEAD of RFC 8439 2.8, which TLS 1.3 seals its records with.  The
vector is the RFC's own 2.8.2; OpenSSL's raw ChaCha20 and Poly1305 agree
with it byte for byte.

## RFC 8439 2.8.2

### seal: the ciphertext and the tag

```x
(do
  (import x/codec/chacha20-poly1305)
  (import x/codec/bytes)
  (def %cp-key (Bytes of-hex "808182838485868788898a8b8c8d8e8f909192939495969798999a9b9c9d9e9f"))
  (def %cp-nonce (Bytes of-hex "070000004041424344454647"))
  (def %cp-aad (Bytes of-hex "50515253c0c1c2c3c4c5c6c7"))
  (def %cp-pt "Ladies and Gentlemen of the class of '99: If I could offer you only one tip for the future, sunscreen would be it.")
  (def %cp-sealed (ChaCha20Poly1305 seal %cp-key %cp-nonce %cp-aad %cp-pt))
  (display (Bytes hex (Bytes sub %cp-sealed 0 114)))
  (newline)
  (display (Bytes hex (Bytes sub %cp-sealed 114 16))))
```
---
```output
d31a8d34648e60db7b86afbc53ef7ec2a4aded51296e08fea9e2b5a736ee62d63dbea45e8ca9671282fafb69da92728b1a71de0a9e060b2905d6a5b67ecd3b3692ddbd7f2d778b8c9803aee328091b58fab324e4fad675945585808b4831d7bc3ff4def08e4b7a9de576d26586cec64b6116
1ae10b594f09e26a7e902ecbd0600691
```

### open: the plaintext back, and a changed byte refused

```x
(do
  (import x/codec/chacha20-poly1305)
  (import x/codec/bytes)
  (def %co-key (Bytes of-hex "808182838485868788898a8b8c8d8e8f909192939495969798999a9b9c9d9e9f"))
  (def %co-nonce (Bytes of-hex "070000004041424344454647"))
  (def %co-aad (Bytes of-hex "50515253c0c1c2c3c4c5c6c7"))
  (def %co-sealed (Bytes of-hex "d31a8d34648e60db7b86afbc53ef7ec2a4aded51296e08fea9e2b5a736ee62d63dbea45e8ca9671282fafb69da92728b1a71de0a9e060b2905d6a5b67ecd3b3692ddbd7f2d778b8c9803aee328091b58fab324e4fad675945585808b4831d7bc3ff4def08e4b7a9de576d26586cec64b61161ae10b594f09e26a7e902ecbd0600691"))
  (def %co-bad (Bytes of-hex "d31a8d34648e60db7b86afbc53ef7ec2a4aded51296e08fea9e2b5a736ee62d63dbea45e8ca9671282fafb69da92728b1a71de0a9e060b2905d6a5b67ecd3b3692ddbd7f2d778b8c9803aee328091b58fab324e4fad675945585808b4831d7bc3ff4def08e4b7a9de576d26586cec64b61161ae10b594f09e26a7e902ecbd0600690"))
  (def %co-pt (ChaCha20Poly1305 open %co-key %co-nonce %co-aad %co-sealed))
  (write (list (Bytes length %co-pt)
               (Bytes hex (Bytes sub %co-pt 0 4))
               (guard (e (e msg)) (ChaCha20Poly1305 open %co-key %co-nonce %co-aad %co-bad))
               (guard (e (e msg)) (ChaCha20Poly1305 open %co-key %co-nonce (Bytes of-hex "50") %co-sealed)))))
```
---
    (114 "4c616469" "ChaCha20Poly1305: the tag does not match" "ChaCha20Poly1305: the tag does not match")

## the edges

### an empty plaintext is a bare tag; sizes are checked

```x
(do
  (import x/codec/chacha20-poly1305)
  (import x/codec/bytes)
  (def %ce-key (Bytes of-hex "0000000000000000000000000000000000000000000000000000000000000000"))
  (def %ce-nonce (Bytes of-hex "000000000000000000000000"))
  (def %ce-sealed (ChaCha20Poly1305 seal %ce-key %ce-nonce (Bytes of-hex "") (Bytes of-hex "")))
  (write (list (Bytes length %ce-sealed)
               (Bytes length (ChaCha20Poly1305 open %ce-key %ce-nonce (Bytes of-hex "") %ce-sealed))
               (guard (e (e msg)) (ChaCha20Poly1305 seal (Bytes of-hex "00") %ce-nonce (Bytes of-hex "") (Bytes of-hex "")))
               (guard (e (e msg)) (ChaCha20Poly1305 seal %ce-key (Bytes of-hex "00") (Bytes of-hex "") (Bytes of-hex ""))))))
```
---
    (16 0 "ChaCha20Poly1305: the key is 32 bytes" "ChaCha20Poly1305: the nonce is 12 bytes")
