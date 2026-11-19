# Safetensors: named tensors in a file behind a JSON header
# @weight 1

A safetensors file is 8 bytes of header length, a JSON header naming each
tensor's dtype, shape and byte range, then the data. The hand-made files
here are written out in hex: the length, the header's text, the elements.
The elements are halves, which a single holds exactly.

## decode

### a hand-made file's tensor comes out with its encoding and extent

The header is `{"w":{"dtype":"F32","shape":[2],"data_offsets":[0,8]}}`,
54 bytes, so the data starts off an 8-byte boundary.

```x
(do (import x/codec/safetensors) (import x/codec/bytes)
  (def r (Bytes of-hex "36000000000000007b2277223a7b226474797065223a22463332222c227368617065223a5b325d2c22646174615f6f666673657473223a5b302c385d7d7d0000c03f00002040"))
  (def w ((Safetensors decode r) get "w"))
  (list (w encoding) (w extent) (w ->list)))
```
---
    ('f32 (2) (1.5 2.5))

### a dtype Tensor has no encoding for raises a label type

The file holds an F16 tensor in its first two bytes and an F64 tensor of
extent (2 1) after it. decode answers every tensor, so it cannot answer
this file; an open file reads the F64 one, below.

```x
(do (import x/codec/safetensors) (import x/codec/bytes)
  (def r (Bytes of-hex "8f000000000000007b225f5f6d657461646174615f5f223a7b22666f726d6174223a227074227d2c22626967223a7b226474797065223a22463136222c227368617065223a5b315d2c22646174615f6f666673657473223a5b302c325d7d2c226d223a7b226474797065223a22463634222c227368617065223a5b322c315d2c22646174615f6f666673657473223a5b322c31385d7d7dffff000000000000e03f00000000000000c0"))
  (guard (e (Err label e)) (Safetensors decode r)))
```
---
    'type

### bytes shorter than the length field raise a label value

```x
(do (import x/codec/safetensors)
  (guard (e (Err label e)) (Safetensors decode (list "abc" 0 3))))
```
---
    'value

### a header that runs past the bytes raises a label value

```x
(do (import x/codec/safetensors) (import x/codec/bytes)
  (def r (Bytes of-hex "36000000000000007b2277223a7b"))
  (guard (e (Err label e)) (Safetensors decode r)))
```
---
    'value

### a byte range that is not the shape's raises a label value

The header gives an F32 tensor of two elements six bytes.

```x
(do (import x/codec/safetensors) (import x/codec/bytes)
  (def r (Bytes of-hex "36000000000000007b2277223a7b226474797065223a22463332222c227368617065223a5b325d2c22646174615f6f666673657473223a5b302c365d7d7d0000c03f00002040"))
  (guard (e (Err label e)) (Safetensors decode r)))
```
---
    'value

## encode

### the file is the length, the header padded to 8 bytes, and the elements

encode answers a region, the buffer with its start and length.

```x
(do (import x/codec/safetensors) (import x/codec/bytes)
  (def r (Safetensors encode (Dict from-plist (list "w" (Tensor from '(1.5 2.5) 'f32)))))
  (list (List ref 1 r) (List ref 2 r) (Bytes hex (list (first r) 0 8)) (Bytes hex (list (first r) 64 8))))
```
---
    (0 72 "3800000000000000" "0000c03f00002040")

### the header names each tensor in the order of the names

```x
(do (import x/codec/safetensors)
  (def s (Safetensors encode
           (Dict from-plist (list "b" (Tensor from '(0.5) 'f64) "a" (Tensor from '((1.5 2.5)) 'f32)))))
  ((prim-ref 'str 'byte-sub) (first s) 8 110))
```
---
    "{\"a\":{\"dtype\":\"F32\",\"shape\":[1,2],\"data_offsets\":[0,8]},\"b\":{\"dtype\":\"F64\",\"shape\":[1],\"data_offsets\":[8,16]}}"

### what encode writes, decode reads back

```x
(do (import x/codec/safetensors)
  (def back (Safetensors decode
              (Safetensors encode
                (Dict from-plist (list "b" (Tensor from '(0.5 -2.0) 'f64)
                                       "a" (Tensor from '((1.5 2.5 3.5) (4.5 5.5 6.5)) 'f32))))))
  (list ((back get "a") encoding) ((back get "a") ->list) ((back get "b") encoding) ((back get "b") ->list)))
```
---
    ('f32 ((1.5 2.5 3.5) (4.5 5.5 6.5)) 'f64 (0.5 -2.0))

### a view is written in its own order

```x
(do (import x/codec/safetensors)
  (def t ((Tensor from '((1.5 2.5 3.5) (4.5 5.5 6.5)) 'f32) transpose))
  (((Safetensors decode (Safetensors encode (Dict from-plist (list "t" t)))) get "t") ->list))
```
---
    ((1.5 4.5) (2.5 5.5) (3.5 6.5))

### a tensor of no elements round-trips

```x
(do (import x/codec/safetensors)
  (def back (Safetensors decode (Safetensors encode (Dict from-plist (list "e" (Tensor zeros '(0 3) 'f32))))))
  ((back get "e") extent))
```
---
    (0 3)

### an i64 tensor round-trips where the word holds one

On a 4-byte word Tensor refuses i64, and the case answers what the
round trip would have.

```x
(do (import x/codec/safetensors)
  (guard (e (list 1 2 3))
    (((Safetensors decode (Safetensors encode (Dict from-plist (list "n" (Tensor from '(1 2 3) 'i64))))) get "n")
      ->list)))
```
---
    (1 2 3)

### a c128 tensor raises a label type

```x
(do (import x/codec/safetensors)
  (guard (e (Err label e)) (Safetensors encode (Dict from-plist (list "c" (Tensor zeros 2 'c128))))))
```
---
    'type

### metadata is written under __metadata__, ahead of the tensors

```x
(do (import x/codec/safetensors)
  (def s (Safetensors encode (Dict from-plist (list "w" (Tensor from '(1.5) 'f32)))
                             (Dict from-plist (list "format" "x"))))
  ((prim-ref 'str 'byte-sub) (first s) 8 31))
```
---
    "{\"__metadata__\":{\"format\":\"x\"},"

## an open file

### names, extent and encoding come from the header

```x
(do (import x/codec/safetensors)
  (def tmp (File temp "/tmp/x-safetensors-header-"))
  (File close (first tmp))
  (Safetensors write (rest tmp)
    (Dict from-plist (list "w" (Tensor from '((1.5 2.5 3.5) (4.5 5.5 6.5)) 'f32) "b" (Tensor from '(0.5 -2.0) 'f64)))
    (Dict from-plist (list "format" "x")))
  (def f (Safetensors open (rest tmp)))
  (def out (list (f names) (f extent "w") (f encoding "w") (f extent "b") ((f metadata) get "format")))
  (f close)
  (File unlink (rest tmp))
  out)
```
---
    (("b" "w") (2 3) 'f32 (2) "x")

### ref reads the named tensor

```x
(do (import x/codec/safetensors)
  (def tmp (File temp "/tmp/x-safetensors-ref-"))
  (File close (first tmp))
  (Safetensors write (rest tmp)
    (Dict from-plist (list "w" (Tensor from '((1.5 2.5 3.5) (4.5 5.5 6.5)) 'f32) "b" (Tensor from '(0.5 -2.0) 'f64))))
  (def f (Safetensors open (rest tmp)))
  (def out (list ((f ref "w") ->list) ((f ref "b") ->list) ((f ref "w") encoding)))
  (f close)
  (File unlink (rest tmp))
  out)
```
---
    (((1.5 2.5 3.5) (4.5 5.5 6.5)) (0.5 -2.0) 'f32)

### a name the file lacks answers nil

```x
(do (import x/codec/safetensors)
  (def tmp (File temp "/tmp/x-safetensors-miss-"))
  (File close (first tmp))
  (Safetensors write (rest tmp) (Dict from-plist (list "w" (Tensor from '(1.5) 'f32))))
  (def f (Safetensors open (rest tmp)))
  (def out (list (f ref "v") (f extent "v") (f encoding "v")))
  (f close)
  (File unlink (rest tmp))
  out)
```
---
    (() () ())

### a tensor read before close stays, and ref after it raises a label state

```x
(do (import x/codec/safetensors)
  (def tmp (File temp "/tmp/x-safetensors-close-"))
  (File close (first tmp))
  (Safetensors write (rest tmp) (Dict from-plist (list "w" (Tensor from '(1.5 2.5) 'f32))))
  (def f (Safetensors open (rest tmp)))
  (def w (f ref "w"))
  (f close)
  (File unlink (rest tmp))
  (list (w ->list) (guard (e (Err label e)) (f ref "w"))))
```
---
    ((1.5 2.5) 'state)

### a dtype Tensor has no encoding for is listed, and ref raises a label type

The file is the hand-made one above: an F16 tensor and an F64 one.

```x
(do (import x/codec/safetensors) (import x/codec/bytes)
  (def r (Bytes of-hex "8f000000000000007b225f5f6d657461646174615f5f223a7b22666f726d6174223a227074227d2c22626967223a7b226474797065223a22463136222c227368617065223a5b315d2c22646174615f6f666673657473223a5b302c325d7d2c226d223a7b226474797065223a22463634222c227368617065223a5b322c315d2c22646174615f6f666673657473223a5b322c31385d7d7dffff000000000000e03f00000000000000c0"))
  (def tmp (File temp "/tmp/x-safetensors-dtype-"))
  (File write (first tmp) (first r) (List ref 2 r))
  (File close (first tmp))
  (def f (Safetensors open (rest tmp)))
  (def out (list (f names) (f encoding "big") ((f ref "m") ->list) ((f metadata) get "format")
                 (guard (e (Err label e)) (f ref "big"))))
  (f close)
  (File unlink (rest tmp))
  out)
```
---
    (("big" "m") () ((0.5) (-2.0)) "pt" 'type)

### a path with no file raises a label io

```x
(do (import x/codec/safetensors)
  (guard (e (Err label e)) (Safetensors open "/tmp/x-safetensors-no-such-file")))
```
---
    'io
