# Deflate: compressed and stored streams
# @weight 15
# @timeout-scale 4

What `Deflate` writes is read back two ways: by `Inflate`, and by the
system zlib through `Zlib decompress` (libz), the reader git and
everything else use.  `%df-bytes` reads a region back as a byte list;
`%df-back` is the round trip through both readers: (SIZE SAME-BY-INFLATE
SAME-BY-LIBZ), SIZE the stream's bytes.

The weight and the timeout scale are the 70000-byte stored case's: its input
is past `Inflate`'s bar, so reading it back builds the compiled engine
-- a one-off compile that a cold runner pays in seconds -- as
inflate-jit.spec.md declares for the same reason.

## compressed

### a repeat is coded once: fixed codes, shorter than the input

```x
(do (import x/codec/deflate) (import x/codec/inflate) (import x/codec/zlib)
  (def %df-text "abcabcabcabcabcabcabcabcabcabc")
  (def %df-z (Deflate zlib %df-text))
  (def %df-b (Inflate zlib (first %df-z) 0 (first (rest %df-z))))
  (def %df-bytes (fn (_ r n) (let ((p ((prim-ref (lit str) (lit ->ptr)) r)))
    ((fn (self i acc) (if (< i 0) acc (self (- i 1) (pair (& ((prim-ref (lit ptr) (lit ref)) p i 1) 255) acc)))) (- n 1) ()))))
  (write (list (List take 2 (%df-bytes (first %df-z) (first (rest %df-z))))
               (< (first (rest %df-z)) 20)
               (Str8 sub 0 (first (rest %df-b)) (first %df-b))
               (equal? (Zlib decompress (%df-bytes (first %df-z) (first (rest %df-z)))) (Str8 ->list %df-text)))))
```
---
    ((120 156) #t "abcabcabcabcabcabcabcabcabcabc" #t)

### varied text: a block under its own codes, read back by both readers

The input is 3000 bytes of lowercase text with repeats at many
distances, so every kind of symbol is coded: literals, lengths with
extra bits, distances with extra bits, and a dynamic header with runs
in its code lengths.

```x
(do (import x/codec/deflate) (import x/codec/inflate) (import x/codec/zlib)
  (def %df-bytes (fn (_ r n) (let ((p ((prim-ref (lit str) (lit ->ptr)) r)))
    ((fn (self i acc) (if (< i 0) acc (self (- i 1) (pair (& ((prim-ref (lit ptr) (lit ref)) p i 1) 255) acc)))) (- n 1) ()))))
  (def %df-back (fn (_ data z)
    (def n (List length data))
    (def back (Inflate zlib (first z) 0 (first (rest z))))
    (def same? (and (= (first (rest back)) n) (equal? (%df-bytes (first back) n) data)))
    (list (first (rest z)) same? (equal? (Zlib decompress (%df-bytes (first z) (first (rest z))) n) data))))
  (def %df-data (List map (fn (_ i) (+ 97 (% (+ (* i i) (/ i 7)) 23))) (List range 0 3000)))
  (def %df-region (fn (_ bs) (let ((r ((prim-ref (lit str) (lit make)) (List length bs))))
    (let ((p ((prim-ref (lit str) (lit ->ptr)) r)))
      (do ((fn (self i l) (unless (null? l) (do ((prim-ref (lit ptr) (lit set!)) p i (first l) 1) (self (+ i 1) (rest l))))) 0 bs) r)))))
  (def %df-in (%df-region %df-data))
  (def %df-r (%df-back %df-data (Deflate zlib %df-in 0 3000)))
  (write (list (< (first %df-r) 1500) (rest %df-r))))
```
---
    (#t (#t #t))

### bytes that do not repeat are stored, not grown

```x
(do (import x/codec/deflate) (import x/codec/inflate) (import x/codec/zlib)
  (def %df-bytes (fn (_ r n) (let ((p ((prim-ref (lit str) (lit ->ptr)) r)))
    ((fn (self i acc) (if (< i 0) acc (self (- i 1) (pair (& ((prim-ref (lit ptr) (lit ref)) p i 1) 255) acc)))) (- n 1) ()))))
  (def %df-data (List map (fn (_ i) (% (+ (* i 7919) (* i i 31)) 256)) (List range 0 1000)))
  (def %df-region (fn (_ bs) (let ((r ((prim-ref (lit str) (lit make)) (List length bs))))
    (let ((p ((prim-ref (lit str) (lit ->ptr)) r)))
      (do ((fn (self i l) (unless (null? l) (do ((prim-ref (lit ptr) (lit set!)) p i (first l) 1) (self (+ i 1) (rest l))))) 0 bs) r)))))
  (def %df-in (%df-region %df-data))
  (def %df-z (Deflate raw %df-in 0 1000))
  (def %df-b (Inflate raw (first %df-z) 0 (first (rest %df-z))))
  (write (list (<= (first (rest %df-z)) 1005) (first (rest %df-b)) (equal? (%df-bytes (first %df-b) 1000) %df-data))))
```
---
    (#t 1000 #t)

### an empty input is one final block of the end code alone

```x
(do (import x/codec/deflate) (import x/codec/inflate) (import x/codec/zlib)
  (def %df-bytes (fn (_ r n) (let ((p ((prim-ref (lit str) (lit ->ptr)) r)))
    ((fn (self i acc) (if (< i 0) acc (self (- i 1) (pair (& ((prim-ref (lit ptr) (lit ref)) p i 1) 255) acc)))) (- n 1) ()))))
  (def %df-z (Deflate zlib ""))
  (write (list (first (rest %df-z)) (first (rest (Inflate zlib (first %df-z) 0 (first (rest %df-z)))))
               (Zlib decompress (%df-bytes (first %df-z) (first (rest %df-z)))))))
```
---
    (8 0 ())

### 20000 bytes from a generator: two blocks, nearly all literals

Six-bit symbols from a multiplicative generator of period 65536 hardly
ever repeat three in a row, so nearly every byte is a literal token: past
16384 tokens the stream is two blocks, each coded in six bits or so a byte.

```x
(do (import x/codec/deflate) (import x/codec/inflate) (import x/codec/zlib)
  (def %df-bytes (fn (_ r n) (let ((p ((prim-ref (lit str) (lit ->ptr)) r)))
    ((fn (self i acc) (if (< i 0) acc (self (- i 1) (pair (& ((prim-ref (lit ptr) (lit ref)) p i 1) 255) acc)))) (- n 1) ()))))
  (write
    ((fn (_)
       (def in ((prim-ref (lit str) (lit make)) 20000))
       (def p ((prim-ref (lit str) (lit ->ptr)) in))
       ((fn (self i s) (when (< i 20000) (do ((prim-ref (lit ptr) (lit set!)) p i (+ 32 (& s 63)) 1) (self (+ i 1) (% (* s 75) 65537))))) 0 1)
       (def z (Deflate zlib in 0 20000))
       (def back (Inflate zlib (first z) 0 (first (rest z))))
       (def same? (= 0 ((prim-ref (lit mem) (lit cmp)) p ((prim-ref (lit str) (lit ->ptr)) (first back)) 20000)))
       (def libz (Zlib decompress (%df-bytes (first z) (first (rest z))) 20000))
       (list (and (< 14000 (first (rest z))) (< (first (rest z)) 17000)) (first (rest back)) same? (List length libz) (List ref 777 libz))))))
```
---
    (#t 20000 #t 20000 94)

### a span inside a string, compressed

```x
(do (import x/codec/deflate) (import x/codec/inflate)
  (def %df-r (Deflate zlib "xxabcabcabcxx" 2 9))
  (def %df-b (Inflate zlib (first %df-r) 0 (first (rest %df-r))))
  (write (list (first (rest %df-b)) (Str8 sub 0 9 (first %df-b)))))
```
---
    (9 "abcabcabc")

## stored blocks

### a short input is one final block, framed in five bytes

```x
(do (import x/codec/deflate)
  (def %df-bytes (fn (_ r n) (let ((p ((prim-ref (lit str) (lit ->ptr)) r)))
    ((fn (self i acc) (if (< i 0) acc (self (- i 1) (pair (& ((prim-ref (lit ptr) (lit ref)) p i 1) 255) acc)))) (- n 1) ()))))
  (def %df-r (Deflate stored "abc"))
  (write (%df-bytes (first %df-r) (first (rest %df-r)))))
```
---
    (1 3 0 252 255 97 98 99)

### an empty input is one empty final block

```x
(do (import x/codec/deflate)
  (write (first (rest (Deflate stored "")))))
```
---
    5

### the zlib wrapper: header, blocks, Adler-32 -- what libz reads

```x
(do (import x/codec/deflate) (import x/codec/zlib)
  (def %df-bytes (fn (_ r n) (let ((p ((prim-ref (lit str) (lit ->ptr)) r)))
    ((fn (self i acc) (if (< i 0) acc (self (- i 1) (pair (& ((prim-ref (lit ptr) (lit ref)) p i 1) 255) acc)))) (- n 1) ()))))
  (def %df-r (Deflate zlib-stored "hello, world"))
  (def %df-z (%df-bytes (first %df-r) (first (rest %df-r))))
  (write (list (List take 2 %df-z) (first (rest %df-r)) (Zlib decompress %df-z))))
```
---
    ((120 1) 23 (104 101 108 108 111 44 32 119 111 114 108 100))

### 70000 bytes with NULs: two blocks, read back by Inflate and by libz

Past one block's 65535, and a NUL every 256th byte, so the count is what
carries the length, never a string's own.

```x
(do (import x/codec/deflate) (import x/codec/inflate) (import x/codec/zlib)
  (def %df-bytes (fn (_ r n) (let ((p ((prim-ref (lit str) (lit ->ptr)) r)))
    ((fn (self i acc) (if (< i 0) acc (self (- i 1) (pair (& ((prim-ref (lit ptr) (lit ref)) p i 1) 255) acc)))) (- n 1) ()))))
  (write
    ((fn (_)
       (def in ((prim-ref (lit str) (lit make)) 70000))
       (def p ((prim-ref (lit str) (lit ->ptr)) in))
       ((fn (self i) (when (< i 70000) (do ((prim-ref (lit ptr) (lit set!)) p i (& (* i 7) 255) 1) (self (+ i 1))))) 0)
       (def z (Deflate zlib-stored in 0 70000))
       (def back (Inflate zlib (first z) 0 (first (rest z))))
       (def same? (= 0 ((prim-ref (lit mem) (lit cmp)) p ((prim-ref (lit str) (lit ->ptr)) (first back)) 70000)))
       (def libz (Zlib decompress (%df-bytes (first z) (first (rest z))) 70000))
       (list (first (rest z)) (first (rest back)) same? (List length libz) (List ref 256 libz))))))
```
---
    (70016 70000 #t 70000 0)

### a span inside a string

```x
(do (import x/codec/deflate) (import x/codec/inflate)
  (def %df-r (Deflate zlib-stored "xxabcxx" 2 3))
  (def %df-b (Inflate zlib (first %df-r) 0 (first (rest %df-r))))
  (write (list (first (rest %df-b)) (Str8 sub 0 3 (first %df-b)))))
```
---
    (3 "abc")
