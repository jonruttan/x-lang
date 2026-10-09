# TlsKeys
# @weight 4

The TLS 1.3 key schedule against RFC 8448's "Simple 1-RTT Handshake"
(section 3): the client's X25519 private key and the messages of the
trace go in, and every secret, key and Finished value the RFC prints
must come out.  The trace's suite is TLS_AES_128_GCM_SHA256, so its keys
are 16 bytes; the schedule is the same SHA-256 one TLS_CHACHA20_POLY1305
uses with 32.

## RFC 8448 section 3

### the fixture: the trace's private key and messages

```x
(do
  (import x/net/tls-keys)
  (import x/codec/bytes)
  (import x/codec/x25519)
  (def %tk-priv (Bytes of-hex "49af42ba7f7994852d713ef2784bcbcaa7911de26adc5642cb634540e7ea5005"))
  (def %tk-ch (Bytes of-hex "010000c00303cb34ecb1e78163ba1c38c6dacb196a6dffa21a8d9912ec18a2ef6283024dece7000006130113031302010000910000000b0009000006736572766572ff01000100000a00140012001d0017001800190100010101020103010400230000003300260024001d002099381de560e4bd43d23d8e435a7dbafeb3c06e51c13cae4d5413691e529aaf2c002b0003020304000d0020001e040305030603020308040805080604010501060102010402050206020202002d00020101001c00024001"))
  (def %tk-sh (Bytes of-hex "020000560303a6af06a4121860dc5e6e60249cd34c95930c8ac5cb1434dac155772ed3e2692800130100002e00330024001d0020c9828876112095fe66762bdbf7c672e156d6cc253b833df1dd69b1b04e751f0f002b00020304"))
  (def %tk-flight (Bytes of-hex "080000240022000a00140012001d00170018001901000101010201030104001c00024001000000000b0001b9000001b50001b0308201ac30820115a003020102020102300d06092a864886f70d01010b0500300e310c300a06035504031303727361301e170d3136303733303031323335395a170d3236303733303031323335395a300e310c300a0603550403130372736130819f300d06092a864886f70d010101050003818d0030818902818100b4bb498f8279303d980836399b36c6988c0c68de55e1bdb826d3901a2461eafd2de49a91d015abbc9a95137ace6c1af19eaa6af98c7ced43120998e187a80ee0ccb0524b1b018c3e0b63264d449a6d38e22a5fda430846748030530ef0461c8ca9d9efbfae8ea6d1d03e2bd193eff0ab9a8002c47428a6d35a8d88d79f7f1e3f0203010001a31a301830090603551d1304023000300b0603551d0f0404030205a0300d06092a864886f70d01010b05000381810085aad2a0e5b9276b908c65f73a7267170618a54c5f8a7b337d2df7a594365417f2eae8f8a58c8f8172f9319cf36b7fd6c55b80f21a03015156726096fd335e5e67f2dbf102702e608ccae6bec1fc63a42a99be5c3eb7107c3c54e9b9eb2bd5203b1c3b84e0a8b2f759409ba3eac9d91d402dcc0cc8f8961229ac9187b42b4de100000f000084080400805a747c5d88fa9bd2e55ab085a61015b7211f824cd484145ab3ff52f1fda8477b0b7abc90db78e2d33a5c141a078653fa6bef780c5ea248eeaaa785c4f394cab6d30bbe8d4859ee511f602957b15411ac027671459e46445c9ea58c181e818e95b8c3fb0bf3278409d3be152a3da5043e063dda65cdf5aea20d53dfacd42f74f3140000209b9b141d906337fbd2cbdce71df4deda4ab42c309572cb7fffee5454b78f0718"))
  (def %tk-server-pub (Bytes sub %tk-sh 52 32))
  (def %tk-shared (list (X25519 scalarmult (first %tk-priv) (first (Bytes copy %tk-server-pub))) 0 32))
  (def %tk-hs (TlsKeys handshake-secret (lit sha256) %tk-shared))
  (def %tk-hello-hash (TlsKeys transcript-hash (lit sha256) (Bytes join %tk-ch %tk-sh)))
  (def %tk-c-hs (TlsKeys derive-secret (lit sha256) %tk-hs "c hs traffic" %tk-hello-hash))
  (def %tk-s-hs (TlsKeys derive-secret (lit sha256) %tk-hs "s hs traffic" %tk-hello-hash))
  (def %tk-master (TlsKeys master-secret (lit sha256) %tk-hs))
  (display (Bytes hex %tk-server-pub)))
```
---
    c9828876112095fe66762bdbf7c672e156d6cc253b833df1dd69b1b04e751f0f

### the shared secret and the early and handshake secrets

```x
(write (list (Bytes hex %tk-shared)
             (Bytes hex (TlsKeys early-secret (lit sha256)))
             (Bytes hex %tk-hs)))
```
---
    ("8bd4054fb55b9d63fdfbacf9f04b9f0d35e6d63f537563efd46272900f89492d" "33ad0a1c607ec03b09e6cd9893680ce210adf300aa1f2660e1b22e10f170f92a" "1dc826e93606aa6fdc0aadc12f741b01046aa6b99f691ed221a9f0ca043fbeac")

### the handshake traffic secrets, over ClientHello and ServerHello

```x
(write (list (Bytes hex %tk-hello-hash) (Bytes hex %tk-c-hs) (Bytes hex %tk-s-hs)))
```
---
    ("860c06edc07858ee8e78f0e7428c58edd6b43f2ca3e6e95f02ed063cf0e1cad8" "b3eddb126e067f35a780b3abf45e2d8f3b1a950738f52e9600746a0e27a55a21" "b67b7d690cc16c4e75e54213cb2d37b4e9c912bcded9105d42befd59d391ad38")

### the server's handshake key and IV, and the client's

```x
(do
  (def %tk-sk (TlsKeys traffic-keys (lit sha256) %tk-s-hs 16))
  (def %tk-ck (TlsKeys traffic-keys (lit sha256) %tk-c-hs 16))
  (write (List map (fn (_ r) (Bytes hex r)) (list (first %tk-sk) (first (rest %tk-sk)) (first %tk-ck) (first (rest %tk-ck))))))
```
---
    ("3fce516009c21727d0f2e4e86ee403bc" "5d313eb2671276ee13000b30" "dbfaa693d1762c5b666af5d950258d01" "5bd3c71b836e0b76bb73265f")

### the master secret and both Finished values

The server's Finished covers the transcript to its CertificateVerify, the
flight's first 621 bytes; the client's covers it through the server's
Finished.

```x
(do
  (def %tk-to-cv (TlsKeys transcript-hash (lit sha256) (Bytes join %tk-ch %tk-sh (Bytes sub %tk-flight 0 621))))
  (def %tk-to-sf (TlsKeys transcript-hash (lit sha256) (Bytes join %tk-ch %tk-sh %tk-flight)))
  (write (list (Bytes hex %tk-master)
               (Bytes hex (TlsKeys finished (lit sha256) %tk-s-hs %tk-to-cv))
               (Bytes hex (TlsKeys finished (lit sha256) %tk-c-hs %tk-to-sf)))))
```
---
    ("18df06843d13a08bf2a449844c5f8a478001bc4d4c627984d5a41da8d0402919" "9b9b141d906337fbd2cbdce71df4deda4ab42c309572cb7fffee5454b78f0718" "a8ec436d677634ae525ac1fcebe11a039ec17694fac6e98527b642f2edd5ce61")

### the application traffic secrets and the server's application key

```x
(do
  (def %tk-to-sf2 (TlsKeys transcript-hash (lit sha256) (Bytes join %tk-ch %tk-sh %tk-flight)))
  (def %tk-c-ap (TlsKeys derive-secret (lit sha256) %tk-master "c ap traffic" %tk-to-sf2))
  (def %tk-s-ap (TlsKeys derive-secret (lit sha256) %tk-master "s ap traffic" %tk-to-sf2))
  (def %tk-ak (TlsKeys traffic-keys (lit sha256) %tk-s-ap 16))
  (write (list (Bytes hex %tk-to-sf2) (Bytes hex %tk-c-ap) (Bytes hex %tk-s-ap)
               (Bytes hex (first %tk-ak)) (Bytes hex (first (rest %tk-ak))))))
```
---
    ("9608102a0f1ccc6db6250b7b7e417b1a000eaada3daae4777a7686c9ff83df13" "9e40646ce79a7f9dc05af8889bce6552875afa0b06df0087f792ebb7c17504a5" "a11af9f05531f856ad47116b45a950328204b4f44bfb6b3a4b4f1f3fcb631643" "9f02283b6c9c07efc26bb9f2ac92e356" "cf782b88dd83549aadf1e984")
