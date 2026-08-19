# Base64 codec: RFC 4648, strict decode (#362)

The standard alphabet with = padding. encode/decode carry strings;
encode-bytes/decode-bytes carry byte lists (the lossless door -- str
values are C strings, so a NUL-bearing payload is only observable as a
byte list). Decode skips whitespace, and raises kind-'value on anything
else outside the alphabet (#61: no silent repair).

## the RFC 4648 vectors

### encode: all seven

```scheme
(do (import x/codec/base64)
  (list (Base64 encode "") (Base64 encode "f") (Base64 encode "fo")
        (Base64 encode "foo") (Base64 encode "foob") (Base64 encode "fooba")
        (Base64 encode "foobar")))
```
---
    ("" "Zg==" "Zm8=" "Zm9v" "Zm9vYg==" "Zm9vYmE=" "Zm9vYmFy")

### decode: round trips, both padded shapes

```scheme
(do (import x/codec/base64)
  (list (Base64 decode "Zm9vYmFy") (Base64 decode "Zm9vYg==")
        (Base64 decode "Zm8=") (Base64 decode "")))
```
---
    ("foobar" "foob" "fo" "")

## the bytes doors

### a NUL-bearing payload round-trips losslessly

```scheme
(do (import x/codec/base64)
  (Base64 decode-bytes (Base64 encode-bytes (list 0 255 16 0))))
```
---
    (0 255 16 0)

### the + and / alphabet edges

```scheme
(do (import x/codec/base64)
  (list (Base64 encode-bytes (list 251 239))
        (Base64 encode-bytes (list 255 255 255))
        (Base64 decode-bytes "//8=")))
```
---
    ("++8=" "////" (255 255))

## tolerance and strictness

### whitespace-wrapped payload decodes (the PEM shape)

```scheme
(do (import x/codec/base64)
  (Base64 decode "Zm9v\nYmFy"))
```
---
    "foobar"

### out-of-alphabet, short group, and misplaced padding all raise 'value

```scheme
(do (import x/codec/base64)
  (list (guard (e (Err kind-of e)) (Base64 decode "Zm9!"))
        (guard (e (Err kind-of e)) (Base64 decode "Zm9"))
        (guard (e (Err kind-of e)) (Base64 decode "Zm==Zm9v"))))
```
---
    ('value 'value 'value)
