# Base64 JIT engine
# @weight 15
# @timeout-scale 4

The compiled decoder behind `(Base64 jit!)`, built by x/codec/base64-jit:
one loop over the text's bytes.  It is adopted only after the maker's
own differential check against the pure-x decode-region; these cases
re-prove agreement through the class, on a PEM block and on every
refusal.  The file builds an engine, so it carries the weight of one.

## the engine builds and is adopted

### jit! reports the decoder active, and is idempotent

```x
(do
  (import x/codec/base64)
  (write (list (Base64 jit!) (Base64 jit!))))
```
---
    (#t #t)

## agreement with the pure-x decoder

### a certificate's PEM block, line breaks and all, and the short answers

The block is ISRG Root X1's first lines, as Mozilla's list carries them:
the decoded bytes are the certificate's DER, whose first bytes read
SEQUENCE, 0x56b long, SEQUENCE, 0x353 long.

```x
(do
  (import x/codec/base64)
  (import x/codec/bytes)
  (def %bj-pem "MIIFazCCA1OgAwIBAgIRAIIQz7DSQONZRGPgu2OCiwAwDQYJKoZIhvcNAQELBQAw\nTzELMAkGA1UEBhMCVVMxKTAnBgNVBAoTIEludGVybmV0IFNlY3VyaXR5IFJlc2Vh\ncmNoIEdyb3VwMRUwEwYDVQQDEwxJU1JHIFJvb3QgWDEwHhcNMTUwNjA0MTEwNDM4\nWhcNMzUwNjA0MTEwNDM4WjBPMQswCQYDVQQGEwJVUzEpMCcGA1UEChMgSW50ZXJu\nZXQgU2VjdXJpdHkgUmVzZWFyY2ggR3JvdXAxFTATBgNVBAMTDElTUkcgUm9vdCBY\nMTCCAiIwDQYJKoZIhvcNAQEBBQADggIPADCCAgoCggIBAK3oJHP0FDfzm54rVygc\n")
  (Base64 jit!)
  (def %bj-der (Base64 decode-region %bj-pem))
  (write (list (Bytes length %bj-der)
               (Bytes hex (Bytes sub %bj-der 0 8))
               (Bytes hex (Base64 decode-region "Zm9v"))
               (Bytes hex (Base64 decode-region "Zm9vYg=="))
               (Bytes hex (Base64 decode-region "Zm9vYmE="))
               (Bytes hex (Base64 decode-region "  Zm9v\r\nYmFy  "))
               (Bytes length (Base64 decode-region "")))))
```
---
    (288 "3082056b30820353" "666f6f" "666f6f62" "666f6f6261" "666f6f626172" 0)

### every refusal, in the pure decoder's words

```x
(do
  (import x/codec/base64)
  (import x/codec/bytes)
  (Base64 jit!)
  (def %bj-why (fn (_ text) (guard (e (e msg)) (Base64 decode-region text))))
  (write (list (%bj-why "Zm9") (%bj-why "Zm=9") (%bj-why "Zm9!") (%bj-why "Zm9v==="))))
```
---
    ("Base64 decode: length is not a multiple of 4" "Base64 decode: = padding before the final group" "Base64 decode: character outside the alphabet" "Base64 decode: length is not a multiple of 4")
