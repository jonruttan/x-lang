# Ecdsa
# @weight 15
# @timeout-scale 4

ECDSA verification (SEC 1 4.1.4) over P-256 and P-384, pure x on
x/codec/mont.  Every key, hash and signature here is OpenSSL's: a key
made with `openssl ecparam -genkey`, the message signed with `openssl
dgst -sign`, and each signature verified by `openssl dgst -verify` before
it was written down.  The last vector signs a SHA-384 hash with a P-256
key, so the hash is cut to the curve's 32 bytes, and its broken hash bit is in
the first byte, since a bit past the cut is not signed.  Each case then breaks
one thing -- a hash bit, a signature bit, the key off its curve -- and
must answer #f.  The first verification on a curve builds its two compiled
engines (x/codec/mont-jit), so the file carries an engine's weight.

## OpenSSL's signatures

### P-256 over SHA-256

```x
(do
  (import x/codec/ecdsa)
  (import x/codec/bytes)
  (def %ec-pub (Bytes of-hex "049047697cab29305038ea53cef5d1bb5f568f8ac60adea2eec0a66d2cc7c6abc2ed84e26809fa045a4cec571b0b06d810b37aab5d9070fb36b6d76284f56a8d0a"))
  (def %ec-h (Bytes of-hex "05f22f773748d38852d6a9ccf5702b35d25bb4378f4954e1bed40bbe6d1fb0a9"))
  (def %ec-sig (Bytes of-hex "3045022100f9fcecb00e62812176bfa3bf42001ef3c69c29a0ce94851a4787e9a7063d511302205a5401430560a247fd24f11c70ee60ff6cb20f17eb176d4c988aedd236dc9d03"))
  (write (list (Ecdsa verify-der (lit p256) %ec-pub %ec-h %ec-sig)
               (Ecdsa verify-der (lit p256) %ec-pub (Bytes of-hex "05f22f773748d38852d6a9ccf5702b35d25bb4378f4954e1bed40bbe6d1fb0a8") %ec-sig)
               (Ecdsa verify-der (lit p256) %ec-pub %ec-h (Bytes of-hex "3045022100f9fcecb00e62812176bfa3bf42001ef3c69c29a0ce94851a4787e9a7063d511302205a5401430560a247fd24f11c70ee60ff6cb20f17eb176d4c988aedd236dc9d02"))
               (Ecdsa verify-der (lit p256) (Bytes of-hex "049047697cab29305038ea53cef5d1bb5f568f8ac60adea2eec0a66d2cc7c6abc2ed84e26809fa045a4cec571b0b06d810b37aab5d9070fb36b6d76284f56a8d0b") %ec-h %ec-sig))))
```
---
    (#t #f #f #f)

### P-384 over SHA-384

```x
(do
  (import x/codec/ecdsa)
  (import x/codec/bytes)
  (def %ec-pub (Bytes of-hex "0464e9af3c731dea8a620d85e34b062edbd8ee2d9d95ce175172fef849b0a6c06ebaf1f7f458037214cd213cbe82bf7a6d54f9df14d8e4bbad1e99db493a29b31352a6a75e134c22bd6af1a7507d58e704ab221fb63bab778fa2d81e6883582d66"))
  (def %ec-h (Bytes of-hex "1e03bed0e36707331bc6eab0eda45fb77be7a5720a2c1182194d93a45dc28d60c135f285204f9f4b039e729aee6ee03e"))
  (def %ec-sig (Bytes of-hex "3065023100afedf2bcff3a4a74a705170ba845f06c4ec7d513186f8fe633f1ba307084c0c391939d9bad6a03ffb4698709498bbb7a0230699549672815954d0a9228a8ae95dfabe1b144621770fa29b7fa9bcab519003f52376fdb9ab0361fb880c81fb61acdba"))
  (write (list (Ecdsa verify-der (lit p384) %ec-pub %ec-h %ec-sig)
               (Ecdsa verify-der (lit p384) %ec-pub (Bytes of-hex "1f03bed0e36707331bc6eab0eda45fb77be7a5720a2c1182194d93a45dc28d60c135f285204f9f4b039e729aee6ee03e") %ec-sig)
               (Ecdsa verify-der (lit p384) %ec-pub %ec-h (Bytes of-hex "3065023100afedf2bcff3a4a74a705170ba845f06c4ec7d513186f8fe633f1ba307084c0c391939d9bad6a03ffb4698709498bbb7a0230699549672815954d0a9228a8ae95dfabe1b144621770fa29b7fa9bcab519003f52376fdb9ab0361fb880c81fb61acdbb"))
               (Ecdsa verify-der (lit p384) (Bytes of-hex "0464e9af3c731dea8a620d85e34b062edbd8ee2d9d95ce175172fef849b0a6c06ebaf1f7f458037214cd213cbe82bf7a6d54f9df14d8e4bbad1e99db493a29b31352a6a75e134c22bd6af1a7507d58e704ab221fb63bab778fa2d81e6883582d67") %ec-h %ec-sig))))
```
---
    (#t #f #f #f)

### P-256 over SHA-384, the hash cut to 32 bytes

```x
(do
  (import x/codec/ecdsa)
  (import x/codec/bytes)
  (def %ec-pub (Bytes of-hex "04da355d259dfb4cb93d7a80d0b91833573d6ab1d533bbd9ebe982f23e299220d638db6e77cd0902b14159410c5dc8f2576f4b182fa085187b8bce06189542c15b"))
  (def %ec-h (Bytes of-hex "1e03bed0e36707331bc6eab0eda45fb77be7a5720a2c1182194d93a45dc28d60c135f285204f9f4b039e729aee6ee03e"))
  (def %ec-sig (Bytes of-hex "3046022100cee687ab839ac06f36696a55270b2f0a1207b5a2d0cd051ca09925ab67e09e08022100814f6b5d4da0d8e21127a4efa8bc59f1fb842e7732e52513038701d0aeddb9e4"))
  (write (list (Ecdsa verify-der (lit p256) %ec-pub %ec-h %ec-sig)
               (Ecdsa verify-der (lit p256) %ec-pub (Bytes of-hex "1f03bed0e36707331bc6eab0eda45fb77be7a5720a2c1182194d93a45dc28d60c135f285204f9f4b039e729aee6ee03e") %ec-sig)
               (Ecdsa verify-der (lit p256) %ec-pub %ec-h (Bytes of-hex "3046022100cee687ab839ac06f36696a55270b2f0a1207b5a2d0cd051ca09925ab67e09e08022100814f6b5d4da0d8e21127a4efa8bc59f1fb842e7732e52513038701d0aeddb9e5"))
               (Ecdsa verify-der (lit p256) (Bytes of-hex "04da355d259dfb4cb93d7a80d0b91833573d6ab1d533bbd9ebe982f23e299220d638db6e77cd0902b14159410c5dc8f2576f4b182fa085187b8bce06189542c15a") %ec-h %ec-sig))))
```
---
    (#t #f #f #f)

## what is not a signature

### a malformed DER signature, r of zero, and an unknown curve

```x
(do
  (import x/codec/ecdsa)
  (import x/codec/bytes)
  (def %ec-g (Bytes of-hex "046b17d1f2e12c4247f8bce6e563a440f277037d812deb33a0f4a13945d898c2964fe342e2fe1a7f9b8ee7eb4a7c0f9e162bce33576b315ececbb6406837bf51f5"))
  (def %ec-h0 (Bytes of-hex "0000000000000000000000000000000000000000000000000000000000000001"))
  (write (list (Ecdsa verify-der (lit p256) %ec-g %ec-h0 (Bytes of-hex "3003020101"))
               (Ecdsa verify (lit p256) %ec-g %ec-h0 (Bytes of-hex "00") (Bytes of-hex "01"))
               (guard (e (e msg)) (Ecdsa verify (lit p521) %ec-g %ec-h0 (Bytes of-hex "01") (Bytes of-hex "01"))))))
```
---
    (#f #f "Ecdsa: no curve named p521")

## Signing

The keys are ones `openssl ecparam -genkey` made; the signatures are
what `openssl dgst -sign -sigopt nonce-type:1` made over "sample":
OpenSSL's deterministic ECDSA, RFC 6979's nonce, so each is byte for byte
what sign answers.

### sign is openssl's RFC 6979 signature, on P-256 and on P-384

```x
(do (import x/codec/bytes)
    (import x/codec/ecdsa)
    (def %es-2 (Ecdsa sign (lit p256) (Bytes of-hex "997294f6157cff07ccb3ab00b83a4ebfbdcc8577c5d920b39784a11a9513ca5b") (Bytes of-hex "af2bdbe1aa9b6ec1e2ade1d694f41fc71a831d0268e9891562113d8a62add1bf")))
    (def %es-3 (Ecdsa sign (lit p384) (Bytes of-hex "da4448cd6023c3e1744605ab68e7cf606d3ae0014f264df84a1ab9c73bf730631c478d22cd4526e496dcc5753b6cef94") (Bytes of-hex "9a9083505bc92276aec4be312696ef7bf3bf603f4bbd381196a029f340585312313bca4a9b5b890efee42c77b1ee25fe")))
    (list (Bytes hex (first %es-2)) (Bytes hex (first (rest %es-2)))
          (Bytes hex (first %es-3)) (Bytes hex (first (rest %es-3)))))
```
---
    ("ae2327fc3521fec0a7d85ec34256b8fe2421fab17053daad7412b99834161e6b" "d31b4a52dcb3c6fb0919ff1dcd6b4b3fee9934d4e42dbe53a6c1be329d204302" "1f81085d018250fd75762852a2827c0c34d26dc933e3060ec38a56998c8c3b4976a41823d7539e85a90f161aff73b5f2" "b8ac3f955e585a6e0058153c6759634fa56baf5fafad309fd2a594cb7c78473b6a6106529422f1dca61e092c804d5464")

### public is the key's point, and verify takes what sign makes

```x
(do (import x/codec/bytes)
    (import x/codec/ecdsa)
    (def %ep-d (Bytes of-hex "997294f6157cff07ccb3ab00b83a4ebfbdcc8577c5d920b39784a11a9513ca5b"))
    (def %ep-q (Ecdsa public (lit p256) %ep-d))
    (def %ep-h (Bytes of-hex "af2bdbe1aa9b6ec1e2ade1d694f41fc71a831d0268e9891562113d8a62add1bf"))
    (def %ep-s (Ecdsa sign (lit p256) %ep-d %ep-h))
    (list (str=? (Bytes hex %ep-q) "0480283b9043bc5d1b8841cafabcc87f757d56a84d1d07ecdbb6e458b03bc4928761942631f9f060e7f33d9a9afd97e3e02e9856a5926ab58f57b675cdfa77f605")
          (str=? (Bytes hex (Ecdsa public (lit p384) (Bytes of-hex "da4448cd6023c3e1744605ab68e7cf606d3ae0014f264df84a1ab9c73bf730631c478d22cd4526e496dcc5753b6cef94"))) "041cf72ca03d2997bf602746edaa78586f0bbecacf8774c808ef6f64080292387ecd880096260c93d1f4c6358426a877424cd9af511155de372e7298b99fda38456b586a5e0236ff902b39520fa8ee76c2671c8449b0aa7aff3dda389050b14768")
          (Ecdsa verify (lit p256) %ep-q %ep-h (first %ep-s) (first (rest %ep-s)))))
```
---
    (#t #t #t)

### a private key outside 1..n-1 is refused

```x
(do (import x/codec/bytes)
    (import x/codec/ecdsa)
    (guard (e (e msg)) (Ecdsa sign (lit p256) (Bytes of-hex "00") (Bytes of-hex "af2bdbe1aa9b6ec1e2ade1d694f41fc71a831d0268e9891562113d8a62add1bf"))))
```
---
    "Ecdsa: a private key outside 1..n-1"
