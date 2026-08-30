# Struct codec: binary records against a field spec (#371)
# @weight 1

Little-endian by default, u16be/u32be for network order, str/cstr for
byte fields, (pad N) for layout gaps. Buffers are strings; reads are
NUL-blind (str byte-ref); pack emits byte lists (the lossless carrier).
First adopter: sys/file.x's stat/lstat decode.

## round trips

### every scalar type, both endiannesses, pads skipped

```scheme
(do (import x/codec/struct)
  (def spec (list (list 'a 'u8) (list 'b 'u16) (list 'pad 2)
                  (list 'c 'i16) (list 'p 'u16be)))
  (Struct unpack spec (bytes->str (Struct pack spec
    (list (pair 'a 7) (pair 'b 513) (pair 'c -2) (pair 'p 443))))))
```
---
    (('a . 7) ('b . 513) ('c . -2) ('p . 443))

### i64 round-trips negative values exactly (the wrap IS the signed value)

```scheme
(do (import x/codec/struct)
  (def s2 (list (list 'v 'i64)))
  (rest (Assoc entry 'v
    (Struct unpack s2 (bytes->str (Struct pack s2 (list (pair 'v -123456789))))))))
```
---
    -123456789

### str is a raw fixed slice; cstr stops at the NUL

```scheme
(do (import x/codec/struct)
  (def spec (list (list 's 'str 3) (list 'n 'cstr 5)))
  (Struct unpack spec (bytes->str (Struct pack spec
    (list (pair 's "xyz") (pair 'n "hi"))))))
```
---
    (('s . "xyz") ('n . "hi"))

## the pieces

### length sums fields and pads

```scheme
(do (import x/codec/struct)
  (Struct length (list (list 'a 'u16) (list 'pad 5) (list 'b 'i64))))
```
---
    15

### unpack takes an offset; interior NULs do not stop the reads

```scheme
(do (import x/codec/struct)
  (Struct unpack (list (list 'pad 1) (list 'p 'u16be))
    (bytes->str (list 0 0 1 187)) 1))
```
---
    (('p . 443))

### reader compiles once and decodes like unpack

```scheme
(do (import x/codec/struct)
  (def spec (list (list 'a 'u8) (list 'b 'u16)))
  (def rdr (Struct reader spec))
  (list (rdr (bytes->str (list 7 1 2)) 0)
        (equal? (rdr (bytes->str (list 9 3 4)) 0)
                (Struct unpack spec (bytes->str (list 9 3 4))))))
```
---
    ((('a . 7) ('b . 513)) #t)

## strictness (#61)

### unknown types and missing pack values raise 'value

```scheme
(do (import x/codec/struct)
  (list (guard (e (Err kind-of e))
          (Struct unpack (list (list 'x 'float)) "ab"))
        (guard (e (Err kind-of e))
          (Struct pack (list (list 'v 'i64)) ()))))
```
---
    ('value 'value)

## str and cstr fields away from offset zero

### a str field's width is its LENGTH, not an end index

`(str byte-sub s start len)` takes a length; the plan builder passed
`(+ off n)`, so a field at a non-zero offset read `off` extra bytes -- a
3-byte field at offset 1 came back 4 bytes long. Correct at offset 0,
which is why it survived every earlier case here. Found by the engine
conformance suite pinning byte-sub's argument convention.

```scheme
(do (import x/codec/struct)
  (def buf (bytes->str (list 88 104 105 33 33 33)))
  (list (rest (Assoc entry 's (Struct unpack (list (list 'pad 1) (list 's 'str 3)) buf)))
        (rest (Assoc entry 's (Struct unpack (list (list 's 'str 3)) buf)))))
```
---
    ("hi!" "Xhi")

### a cstr field stops at the NUL, still measured from its own offset

```scheme
(do (import x/codec/struct)
  (def buf (bytes->str (list 88 104 105 0 122 122)))
  (rest (Assoc entry 's (Struct unpack (list (list 'pad 1) (list 's 'cstr 4)) buf))))
```
---
    "hi"
