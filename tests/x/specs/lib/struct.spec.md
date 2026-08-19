# Struct codec: binary records against a field spec (#371)

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
