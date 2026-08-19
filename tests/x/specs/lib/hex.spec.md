# Hex codec: bytes <-> hexadecimal text (#362)

Lowercase out, either case in, strict decode (odd length or a character
outside [0-9a-fA-F] raises kind-'value -- #61: no silent repair).
encode/decode carry strings; the -bytes doors carry byte lists losslessly.
(Hash ->hex) remains the INT-digest formatter; this codec transcodes
byte sequences.

## round trips

### encode and decode, string doors

```scheme
(do (import x/codec/hex)
  (list (Hex encode "foobar") (Hex decode "666f6f626172")
        (Hex encode "") (Hex decode "")))
```
---
    ("666f6f626172" "foobar" "" "")

### uppercase input decodes

```scheme
(do (import x/codec/hex)
  (Hex decode "666F6F"))
```
---
    "foo"

### a NUL-bearing payload round-trips losslessly through the bytes doors

```scheme
(do (import x/codec/hex)
  (list (Hex encode-bytes (list 255 0 16))
        (Hex decode-bytes "ff0010")))
```
---
    ("ff0010" (255 0 16))

## strictness

### odd length and out-of-range characters raise 'value

```scheme
(do (import x/codec/hex)
  (list (guard (e (Err kind-of e)) (Hex decode "abc"))
        (guard (e (Err kind-of e)) (Hex decode "zz"))))
```
---
    ('value 'value)
