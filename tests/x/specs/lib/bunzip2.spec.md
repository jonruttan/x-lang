# Bunzip2: bzip2 in pure x-lang
# @weight 3

The decoder is checked against streams written by bzip2 1.0.8 at `-9`,
carried here in hex.  `%bz-region` puts a byte list into a byte region and
`%bz-bytes` reads one back.  The inputs are under the 4KB bar, so decode
runs the pure-x loops; a fed stream builds the compiled engine.

## whole streams

### a short input

```x
(do (import x/codec/bunzip2) (import x/codec/hex)
  (def %bz-region (fn (_ bs) (let ((r ((prim-ref (lit str) (lit make)) (List length bs))))
    (let ((p ((prim-ref (lit str) (lit ->ptr)) r)))
      (do ((fn (self i l) (unless (null? l) (do ((prim-ref (lit ptr) (lit set!)) p i (first l) 1) (self (+ i 1) (rest l))))) 0 bs) r)))))
  (def %bz-bytes (fn (_ r n) (let ((p ((prim-ref (lit str) (lit ->ptr)) r)))
    ((fn (self i acc) (if (< i 0) acc (self (- i 1) (pair (& ((prim-ref (lit ptr) (lit ref)) p i 1) 255) acc)))) (- n 1) ()))))
  (def %bz-z (Hex decode-bytes "425a68393141592653599f3c11f30000035100001040040244a0002129a3108602f28370a1e2ee48a70a1213e7823e60"))
  (def %bz-r (Bunzip2 decode (%bz-region %bz-z) 0 (List length %bz-z)))
  (write (list (equal? (%bz-bytes (first %bz-r) (first (rest %bz-r))) (list 104 101 108 108 111 44 32 104 101 108 108 111 10))
               (first (rest (rest %bz-r))))))
```
---
    (#t 48)

### a varied input: every symbol group, and runs

```x
(do (import x/codec/bunzip2) (import x/codec/hex)
  (def %bz-region (fn (_ bs) (let ((r ((prim-ref (lit str) (lit make)) (List length bs))))
    (let ((p ((prim-ref (lit str) (lit ->ptr)) r)))
      (do ((fn (self i l) (unless (null? l) (do ((prim-ref (lit ptr) (lit set!)) p i (first l) 1) (self (+ i 1) (rest l))))) 0 bs) r)))))
  (def %bz-bytes (fn (_ r n) (let ((p ((prim-ref (lit str) (lit ->ptr)) r)))
    ((fn (self i acc) (if (< i 0) acc (self (- i 1) (pair (& ((prim-ref (lit ptr) (lit ref)) p i 1) 255) acc)))) (- n 1) ()))))
  (def %bz-z (Hex decode-bytes (Str8 append
    "425a6839314159265359b67dd4d20000019f803ffffffffffffffffffffff03000b80e1a1934d0d323434c8c8323234320313464d0064c8c431c343269a1a64686991906464686406268c9a00c9918861155462340003269a68d3201a064c86464308c8300179897c300617138dc8c30d00d10d274dd4755d60d70d80d9769db771dd0de088115df633c0c70e108ec8789e364bc812825bcaf33cef43d21d41d6cc7b1ed7b9ef0f009ace7c59ed07c83cc3d1a2d27d5f6698540f77e1f96ab59ae1603e9fb6cb69fc7f43f83fdb6dc6eb79be18030b89c6e4728bb9229c28485b3eea690")))
  (def %bz-r (Bunzip2 decode (%bz-region %bz-z) 0 (List length %bz-z)))
  (write (list (equal? (%bz-bytes (first %bz-r) (first (rest %bz-r)))
                       (List map (fn (_ i) (+ 33 (% (* i 7) 90))) (List range 0 300)))
               (first (rest %bz-r))
               (first (rest (rest %bz-r))))))
```
---
    (#t 300 228)

### an empty input: no blocks, only the end marker

```x
(do (import x/codec/bunzip2) (import x/codec/hex)
  (def %bz-region (fn (_ bs) (let ((r ((prim-ref (lit str) (lit make)) (List length bs))))
    (let ((p ((prim-ref (lit str) (lit ->ptr)) r)))
      (do ((fn (self i l) (unless (null? l) (do ((prim-ref (lit ptr) (lit set!)) p i (first l) 1) (self (+ i 1) (rest l))))) 0 bs) r)))))
  (def %bz-z (Hex decode-bytes "425a683917724538509000000000"))
  (rest (Bunzip2 decode (%bz-region %bz-z) 0 (List length %bz-z))))
```
---
    (0 14)

## where a stream ends

### USED counts the first stream alone; the second decodes from there

bzip2 writes a file of several streams for input concatenated: "one\n"
compressed, then "two\n".

```x
(do (import x/codec/bunzip2) (import x/codec/hex)
  (def %bz-region (fn (_ bs) (let ((r ((prim-ref (lit str) (lit make)) (List length bs))))
    (let ((p ((prim-ref (lit str) (lit ->ptr)) r)))
      (do ((fn (self i l) (unless (null? l) (do ((prim-ref (lit ptr) (lit set!)) p i (first l) 1) (self (+ i 1) (rest l))))) 0 bs) r)))))
  (def %bz-bytes (fn (_ r n) (let ((p ((prim-ref (lit str) (lit ->ptr)) r)))
    ((fn (self i acc) (if (< i 0) acc (self (- i 1) (pair (& ((prim-ref (lit ptr) (lit ref)) p i 1) 255) acc)))) (- n 1) ()))))
  (def %bz-z (Hex decode-bytes (Str8 append
    "425a68393141592653597813c082000001c10000100201a000219a68334d0cbc5dc914e14241e04f0208"
    "425a68393141592653592eb71ad700000141800010000084802000219a68334d073c5dc914e14240badc6b5c")))
  (def %bz-in (%bz-region %bz-z))
  (def %bz-n (List length %bz-z))
  (def %bz-a (Bunzip2 decode %bz-in 0 %bz-n))
  (def %bz-used (first (rest (rest %bz-a))))
  (def %bz-b (Bunzip2 decode %bz-in %bz-used (- %bz-n %bz-used)))
  (write (list (%bz-bytes (first %bz-a) (first (rest %bz-a))) %bz-used
               (%bz-bytes (first %bz-b) (first (rest %bz-b))) (first (rest (rest %bz-b))))))
```
---
    ((111 110 101 10) 42 (116 119 111 10) 44)

## a stream fed a piece at a time

### seven bytes at a time: the same output, and the next stream in rest

```x
(do (import x/codec/bunzip2) (import x/codec/hex)
  (def %bz-region (fn (_ bs) (let ((r ((prim-ref (lit str) (lit make)) (List length bs))))
    (let ((p ((prim-ref (lit str) (lit ->ptr)) r)))
      (do ((fn (self i l) (unless (null? l) (do ((prim-ref (lit ptr) (lit set!)) p i (first l) 1) (self (+ i 1) (rest l))))) 0 bs) r)))))
  (def %bz-bytes (fn (_ r n) (let ((p ((prim-ref (lit str) (lit ->ptr)) r)))
    ((fn (self i acc) (if (< i 0) acc (self (- i 1) (pair (& ((prim-ref (lit ptr) (lit ref)) p i 1) 255) acc)))) (- n 1) ()))))
  (def %bz-z (Hex decode-bytes (Str8 append
    "425a68393141592653597813c082000001c10000100201a000219a68334d0cbc5dc914e14241e04f0208"
    "425a68393141592653592eb71ad700000141800010000084802000219a68334d073c5dc914e14240badc6b5c")))
  (def %bz-in (%bz-region %bz-z))
  (def %bz-n (List length %bz-z))
  (def %bz-s (Bunzip2 stream))
  (def %bz-out
    ((fn (self at acc)
       (if (< at %bz-n)
         (let ((k (if (< (- %bz-n at) 7) (- %bz-n at) 7)))
           (let ((r (Bunzip2 feed %bz-s %bz-in at k)))
             (self (+ at k) (List append acc (%bz-bytes (first r) (first (rest r)))))))
         (let ((r (Bunzip2 finish %bz-s)))
           (List append acc (%bz-bytes (first r) (first (rest r)))))))
     0 ()))
  (def %bz-rest (Bunzip2 rest %bz-s))
  (write (list %bz-out (Bunzip2 done? %bz-s) (Bunzip2 ok? %bz-s)
               (%bz-bytes (first %bz-rest) 3) (first (rest %bz-rest)))))
```
---
    ((111 110 101 10) #t #t (66 90 104) 44)

### a changed block CRC: the block is answered, and ok? turns #f

As busybox's bunzip2 does, the bytes of the block come out before the
error is known.

```x
(do (import x/codec/bunzip2) (import x/codec/hex)
  (def %bz-region (fn (_ bs) (let ((r ((prim-ref (lit str) (lit make)) (List length bs))))
    (let ((p ((prim-ref (lit str) (lit ->ptr)) r)))
      (do ((fn (self i l) (unless (null? l) (do ((prim-ref (lit ptr) (lit set!)) p i (first l) 1) (self (+ i 1) (rest l))))) 0 bs) r)))))
  (def %bz-z (Hex decode-bytes "425a68393141592653599f3c11f20000035100001040040244a0002129a3108602f28370a1e2ee48a70a1213e7823e60"))
  (def %bz-s (Bunzip2 stream))
  (def %bz-r (Bunzip2 feed %bz-s (%bz-region %bz-z) 0 (List length %bz-z)))
  (write (list (first (rest %bz-r)) (Bunzip2 done? %bz-s) (Bunzip2 ok? %bz-s))))
```
---
    (13 #t #f)

## refusals

### a changed block CRC, decoded whole

```x
(do (import x/codec/bunzip2) (import x/codec/hex)
  (def %bz-region (fn (_ bs) (let ((r ((prim-ref (lit str) (lit make)) (List length bs))))
    (let ((p ((prim-ref (lit str) (lit ->ptr)) r)))
      (do ((fn (self i l) (unless (null? l) (do ((prim-ref (lit ptr) (lit set!)) p i (first l) 1) (self (+ i 1) (rest l))))) 0 bs) r)))))
  (def %bz-z (Hex decode-bytes "425a68393141592653599f3c11f20000035100001040040244a0002129a3108602f28370a1e2ee48a70a1213e7823e60"))
  (guard (e (list (Err label e) (e msg) (e data))) (Bunzip2 decode (%bz-region %bz-z) 0 (List length %bz-z))))
```
---
    ('value "Bunzip2: a block's CRC is wrong" (('bunzip . 'crc)))

### an input that is not bzip2's

```x
(do (import x/codec/bunzip2)
  (guard (e (list (e msg) (e data))) (Bunzip2 decode "abcdefgh")))
```
---
    ("Bunzip2: no BZ magic" (('bunzip . 'magic)))

### a block size digit out of range

```x
(do (import x/codec/bunzip2)
  (guard (e (list (e msg) (e data))) (Bunzip2 decode "BZh0abcd")))
```
---
    ("Bunzip2: no block size header" (('bunzip . 'header)))

### a stream cut short

```x
(do (import x/codec/bunzip2) (import x/codec/hex)
  (def %bz-region (fn (_ bs) (let ((r ((prim-ref (lit str) (lit make)) (List length bs))))
    (let ((p ((prim-ref (lit str) (lit ->ptr)) r)))
      (do ((fn (self i l) (unless (null? l) (do ((prim-ref (lit ptr) (lit set!)) p i (first l) 1) (self (+ i 1) (rest l))))) 0 bs) r)))))
  (def %bz-z (Hex decode-bytes "425a68393141592653599f3c11f30000035100001040040244a0002129a3108602f28370a1e2ee48a70a1213e7823e60"))
  (guard (e (list (e msg) (e data))) (Bunzip2 decode (%bz-region %bz-z) 0 20)))
```
---
    ("Bunzip2: the input ends inside the stream" (('bunzip . 'data) ('short . #t)))

### a fed stream cut short is refused at finish

```x
(do (import x/codec/bunzip2) (import x/codec/hex)
  (def %bz-region (fn (_ bs) (let ((r ((prim-ref (lit str) (lit make)) (List length bs))))
    (let ((p ((prim-ref (lit str) (lit ->ptr)) r)))
      (do ((fn (self i l) (unless (null? l) (do ((prim-ref (lit ptr) (lit set!)) p i (first l) 1) (self (+ i 1) (rest l))))) 0 bs) r)))))
  (def %bz-z (Hex decode-bytes "425a68393141592653599f3c11f30000035100001040040244a0002129a3108602f28370a1e2ee48a70a1213e7823e60"))
  (def %bz-s (Bunzip2 stream))
  (def %bz-r (Bunzip2 feed %bz-s (%bz-region %bz-z) 0 20))
  (list (first (rest %bz-r)) (guard (e (e msg)) (Bunzip2 finish %bz-s))))
```
---
    (0 "Bunzip2: the input ends inside the stream")
