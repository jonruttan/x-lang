# Base64 codec: RFC 4648, strict decode (#362)
# @weight 1

The standard alphabet with = padding. encode/decode carry strings;
encode-bytes/decode-bytes carry byte lists (the lossless door -- str
values are C strings, so a NUL-bearing payload is only observable as a
byte list). Decode skips whitespace, and raises a label 'value on anything
else outside the alphabet (#61: no silent repair).

## the RFC 4648 vectors

### encode: all seven

```x
(do (import x/codec/base64)
  (list (Base64 encode "") (Base64 encode "f") (Base64 encode "fo")
        (Base64 encode "foo") (Base64 encode "foob") (Base64 encode "fooba")
        (Base64 encode "foobar")))
```
---
    ("" "Zg==" "Zm8=" "Zm9v" "Zm9vYg==" "Zm9vYmE=" "Zm9vYmFy")

### decode: round trips, both padded forms

```x
(do (import x/codec/base64)
  (list (Base64 decode "Zm9vYmFy") (Base64 decode "Zm9vYg==")
        (Base64 decode "Zm8=") (Base64 decode "")))
```
---
    ("foobar" "foob" "fo" "")

## the bytes doors

### a NUL-bearing payload round-trips losslessly

```x
(do (import x/codec/base64)
  (Base64 decode-bytes (Base64 encode-bytes (list 0 255 16 0))))
```
---
    (0 255 16 0)

### the + and / alphabet edges

```x
(do (import x/codec/base64)
  (list (Base64 encode-bytes (list 251 239))
        (Base64 encode-bytes (list 255 255 255))
        (Base64 decode-bytes "//8=")))
```
---
    ("++8=" "////" (255 255))

## tolerance and strictness

### whitespace-wrapped payload decodes (the PEM style)

```x
(do (import x/codec/base64)
  (Base64 decode "Zm9v\nYmFy"))
```
---
    "foobar"

### out-of-alphabet, short group, and misplaced padding all raise 'value

```x
(do (import x/codec/base64)
  (list (guard (e (Err label e)) (Base64 decode "Zm9!"))
        (guard (e (Err label e)) (Base64 decode "Zm9"))
        (guard (e (Err label e)) (Base64 decode "Zm==Zm9v"))))
```
---
    ('value 'value 'value)

## the region doors

### encode-region: the seven vectors, read by count

```x
(do (import x/codec/base64) (import x/codec/bytes)
  (write (List map (fn (_ h) (Bytes hex (Base64 encode-region (Bytes of-hex h))))
              (list "" "66" "666f" "666f6f" "666f6f62" "666f6f6261" "666f6f626172"))))
```
---
    ("" "5a673d3d" "5a6d383d" "5a6d3976" "5a6d397659673d3d" "5a6d3976596d453d" "5a6d3976596d4679")

### encode-region: a NUL and high bytes, and a region that starts past 0

00 ff 10 is AP8Q; the region from byte 1, ff 10, is /xA=.

```x
(do (import x/codec/base64) (import x/codec/bytes)
  (def %b64-r (Bytes of-hex "00ff10fe"))
  (write (list (Bytes hex (Base64 encode-region (list (first %b64-r) 0 3)))
               (Bytes hex (Base64 encode-region (list (first %b64-r) 1 2))))))
```
---
    ("41503851" "2f78413d")

### encode-region round-trips 3000 bytes of every value through decode-region

Under 4 KB, so both run in pure x.

```x
(do (import x/codec/base64) (import x/codec/bytes)
  (def %b64-n ((prim-ref (lit str) (lit make)) 3000))
  ((fn (self i) (when (< i 3000) (do ((prim-ref (lit ptr) (lit set!)) ((prim-ref (lit str) (lit ->ptr)) %b64-n) i (% (* i 7) 256) 1) (self (+ i 1))))) 0)
  (def %b64-e (Base64 encode-region (list %b64-n 0 3000)))
  (write (list (Bytes length %b64-e)
               (Bytes same? (Base64 decode-region %b64-e) (list %b64-n 0 3000)))))
```
---
    (4000 #t)
