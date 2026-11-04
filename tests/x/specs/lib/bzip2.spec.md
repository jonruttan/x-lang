# Bzip2: bzip2 compression in pure x-lang
# @weight 3

The compressor is checked against streams bzip2 1.0.8 wrote at `-9`, carried
here in hex: a stream of ours is right when it is those bytes.  `%bz-region`
puts a byte list into a byte region, `%bz-hex` reads a region back as hex.
The inputs are under the 4KB bar, so compress runs the pure-x loops.

## whole streams

### a short input

```x
(do (import x/codec/bzip2) (import x/codec/hex)
  (def %bz-hex (fn (_ r n) (let ((p ((prim-ref (lit str) (lit ->ptr)) r)))
    (Hex encode-bytes ((fn (self i acc) (if (< i 0) acc (self (- i 1) (pair (& ((prim-ref (lit ptr) (lit ref)) p i 1) 255) acc)))) (- n 1) ())))))
  (def %bz-r (Bzip2 compress "hello, hello\n" 9))
  (write (list (equal? (%bz-hex (first %bz-r) (first (rest %bz-r)))
                         "425a68393141592653599f3c11f30000035100001040040244a0002129a3108602f28370a1e2ee48a70a1213e7823e60")
               (first (rest %bz-r)))))
```
---
    (#t 48)

### nothing to compress is a stream all the same

```x
(do (import x/codec/bzip2) (import x/codec/hex)
  (def %bz-hex (fn (_ r n) (let ((p ((prim-ref (lit str) (lit ->ptr)) r)))
    (Hex encode-bytes ((fn (self i acc) (if (< i 0) acc (self (- i 1) (pair (& ((prim-ref (lit ptr) (lit ref)) p i 1) 255) acc)))) (- n 1) ())))))
  (def %bz-r (Bzip2 compress "" 9))
  (write (list (equal? (%bz-hex (first %bz-r) (first (rest %bz-r)))
                         "425a683917724538509000000000")
               (first (rest %bz-r)))))
```
---
    (#t 14)

### a varied input: every symbol group, and runs

```x
(do (import x/codec/bzip2) (import x/codec/hex)
  (def %bz-region (fn (_ bs) (let ((r ((prim-ref (lit str) (lit make)) (List length bs))))
    (let ((p ((prim-ref (lit str) (lit ->ptr)) r)))
      (do ((fn (self i l) (unless (null? l) (do ((prim-ref (lit ptr) (lit set!)) p i (first l) 1) (self (+ i 1) (rest l))))) 0 bs) r)))))
  (def %bz-hex (fn (_ r n) (let ((p ((prim-ref (lit str) (lit ->ptr)) r)))
    (Hex encode-bytes ((fn (self i acc) (if (< i 0) acc (self (- i 1) (pair (& ((prim-ref (lit ptr) (lit ref)) p i 1) 255) acc)))) (- n 1) ())))))
  (def %bz-in (List map (fn (_ i) (+ 33 (% (* i 7) 90))) (List range 0 300)))
  (def %bz-r (Bzip2 compress (%bz-region %bz-in) 9 0 300))
  (write (list (equal? (%bz-hex (first %bz-r) (first (rest %bz-r))) (Str8 append
    "425a6839314159265359b67dd4d20000019f803ffffffffffffffffffffff03000b80e1a1934d0d323434c8c8323234320313"
    "464d0064c8c431c343269a1a64686991906464686406268c9a00c9918861155462340003269a68d3201a064c86464308c8300"
    "179897c300617138dc8c30d00d10d274dd4755d60d70d80d9769db771dd0de088115df633c0c70e108ec8789e364bc812825b"
    "caf33cef43d21d41d6cc7b1ed7b9ef0f009ace7c59ed07c83cc3d1a2d27d5f6698540f77e1f96ab59ae1603e9fb6cb69fc7f4"
    "3f83fdb6dc6eb79be18030b89c6e4728bb9229c28485b3eea690"))
               (first (rest %bz-r)))))
```
---
    (#t 228)

### the level is the block size, and the digit the stream carries

Three hundred bytes are one block at any level, so `-1` and `-9` write the
same blocks and differ in the digit alone.

```x
(do (import x/codec/bzip2) (import x/codec/hex)
  (def %bz-region (fn (_ bs) (let ((r ((prim-ref (lit str) (lit make)) (List length bs))))
    (let ((p ((prim-ref (lit str) (lit ->ptr)) r)))
      (do ((fn (self i l) (unless (null? l) (do ((prim-ref (lit ptr) (lit set!)) p i (first l) 1) (self (+ i 1) (rest l))))) 0 bs) r)))))
  (def %bz-hex (fn (_ r n) (let ((p ((prim-ref (lit str) (lit ->ptr)) r)))
    (Hex encode-bytes ((fn (self i acc) (if (< i 0) acc (self (- i 1) (pair (& ((prim-ref (lit ptr) (lit ref)) p i 1) 255) acc)))) (- n 1) ())))))
  (def %bz-in (%bz-region (List map (fn (_ i) (+ 33 (% (* i 7) 90))) (List range 0 300))))
  (def %bz-1 (Bzip2 compress %bz-in 1 0 300))
  (def %bz-9 (Bzip2 compress %bz-in 9 0 300))
  (def %bz-h1 (%bz-hex (first %bz-1) (first (rest %bz-1))))
  (def %bz-h9 (%bz-hex (first %bz-9) (first (rest %bz-9))))
  (write (list (equal? (Str8 sub 0 8 %bz-h1) "425a6831")
               (equal? (Str8 sub 0 8 %bz-h9) "425a6839")
               (equal? (Str8 sub 8 440 %bz-h1) (Str8 sub 8 440 %bz-h9)))))
```
---
    (#t #t #t)

### a stream fed a piece at a time writes what one call writes

A fed stream asks for the compiled engine, so this case builds it where a
JIT backend is there; the bytes are the same either way.

```x
(do (import x/codec/bzip2) (import x/codec/hex)
  (def %bz-hex (fn (_ r n) (let ((p ((prim-ref (lit str) (lit ->ptr)) r)))
    (Hex encode-bytes ((fn (self i acc) (if (< i 0) acc (self (- i 1) (pair (& ((prim-ref (lit ptr) (lit ref)) p i 1) 255) acc)))) (- n 1) ())))))
  (def %bz-z (Bzip2 stream 9))
  (def %bz-a (Bzip2 feed %bz-z "hello, " 0 7 #f))
  (def %bz-b (Bzip2 feed %bz-z "hello\n" 0 6 #t))
  (write (equal? (Str8 append (%bz-hex (first %bz-a) (first (rest %bz-a)))
                             (%bz-hex (first %bz-b) (first (rest %bz-b))))
                 "425a68393141592653599f3c11f30000035100001040040244a0002129a3108602f28370a1e2ee48a70a1213e7823e60")))
```
---
    #t

### a run the length coder rewrites

Thirty of one byte, then four of another: the runs of four and more leave the
block as a byte and a count, and the count rides the symbol stream.

```x
(do (import x/codec/bzip2) (import x/codec/hex)
  (def %bz-hex (fn (_ r n) (let ((p ((prim-ref (lit str) (lit ->ptr)) r)))
    (Hex encode-bytes ((fn (self i acc) (if (< i 0) acc (self (- i 1) (pair (& ((prim-ref (lit ptr) (lit ref)) p i 1) 255) acc)))) (- n 1) ())))))
  (def %bz-r (Bzip2 compress "aaaaaaaaaaaaaaaaaaaaaaaaaaaaaabbbb\n" 9))
  (write (list (equal? (%bz-hex (first %bz-r) (first (rest %bz-r)))
                         "425a6839314159265359b82422580000036100401000103000200030cd00c1a104b667177245385090b8242258")
               (first (rest %bz-r)))))
```
---
    (#t 45)
