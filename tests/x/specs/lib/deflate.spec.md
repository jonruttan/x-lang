# Deflate: stored streams
# @weight 15
# @timeout-scale 4

What `Deflate` writes is read back two ways: by `Inflate`, and by the
system zlib through `Zlib decompress` (libz), the reader git and
everything else use.  `%df-bytes` reads a region back as a byte list.

The weight and the timeout scale are the 70000-byte case's: its input
is past `Inflate`'s bar, so reading it back builds the compiled engine
-- a one-off compile that a cold runner pays in seconds -- as
inflate-jit.spec.md declares for the same reason.

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
