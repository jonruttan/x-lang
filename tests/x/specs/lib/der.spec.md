# Der
# @weight 1

DER (X.690) over regions: an element is (TAG CONTENTS WHOLE), the
contents and the whole element regions of the input.  The OIDs are the
ones X.509 uses; the times are UTCTime's and GeneralizedTime's forms,
the expected seconds `date -u` gives.

## elements

### a SEQUENCE of two INTEGERs, and where its parts sit

```x
(do
  (import x/codec/der)
  (import x/codec/bytes)
  (def %dr-e (Der read (Bytes of-hex "3007020101020200ff")))
  (def %dr-items (Der items (first (rest %dr-e))))
  (write (list (first %dr-e) (List length %dr-items)
               (List map (fn (_ i) (Der small (first (rest i)))) %dr-items)
               (Bytes hex (first (rest (rest (first (rest %dr-items)))))))))
```
---
    (48 2 (1 255) "020200ff")

### OIDs, BIT STRINGs, and a long length

```x
(do
  (import x/codec/der)
  (import x/codec/bytes)
  (def %do-big (Bytes join (Bytes of-hex "0481c8") (Bytes of-list (List repeat 200 7))))
  (write (list (Der oid (first (rest (Der read (Bytes of-hex "06082a8648ce3d030107")))))
               (Der oid (first (rest (Der read (Bytes of-hex "06052b81040022")))))
               (Bytes hex (Der bits (first (rest (Der read (Bytes of-hex "0304000102ff"))))))
               (Bytes length (first (rest (Der read %do-big)))))))
```
---
    ("1.2.840.10045.3.1.7" "1.3.132.0.34" "0102ff" 200)

### times: UTCTime either side of 2000, and GeneralizedTime

```x
(do
  (import x/codec/der)
  (import x/codec/bytes)
  (write (list (Der time 23 (Bytes of "700101000000Z"))
               (Der time 23 (Bytes of "991231235959Z"))
               (Der time 23 (Bytes of "260915120000Z"))
               (Der time 24 (Bytes of "20500101000000Z")))))
```
---
    (0 946684799 1789473600 2524608000)

### what is not DER is refused

```x
(do
  (import x/codec/der)
  (import x/codec/bytes)
  (def %dx (fn (_ hex) (guard (e (e msg)) (Der read (Bytes of-hex hex)))))
  (write (list (%dx "3080") (%dx "0205010203") (%dx "02010100") (guard (e (e msg)) (Der bits (Bytes of-hex "0300"))))))
```
---
    ("Der: an indefinite length" "Der: an element longer than what holds it" "Der: bytes after the element" "Der: a BIT STRING with unused bits")
