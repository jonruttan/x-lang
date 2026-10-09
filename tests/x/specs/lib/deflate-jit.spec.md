# Deflate JIT engine

# @weight 15
# @timeout-scale 4

The compiled token writer behind `(Deflate jit!)`.  It is adopted only after
writing, for the codec's check inputs, the streams the pure-x writer writes;
these cases re-prove agreement through the class, and read what the engine
writes back with `Inflate` and with the system zlib.  `%dj-fill` puts bytes
into a region from a generator: 0 a short repeat, 1 varied text with repeats
at many distances, 2 six-bit symbols that hardly repeat.  `%dj-bytes` reads a
region back as a byte list.

## the engine builds and is adopted

### jit! reports the engine active, and is idempotent

```x
(do (import x/codec/deflate)
  (display (list (Deflate jit!) (Deflate jit!) ((Compiled named (lit deflate)) state))))
```
---
    (#t #t compiled)

## what the engine writes

### the same bytes as the pure-x writer, for each kind of input

The streams are written before the engine is built, then again through it.

```x
(do (import x/codec/deflate)
  (def %dj-fill (fn (_ which n)
    (def r ((prim-ref (lit str) (lit make)) n))
    (def p ((prim-ref (lit str) (lit ->ptr)) r))
    ((fn (self i s) (when (< i n)
       (do ((prim-ref (lit ptr) (lit set!)) p i
              (match ((= which 0) (+ 97 (% i 3))) ((= which 1) (+ 97 (% (+ (* i i) (/ i 7)) 23))) (#t (+ 32 (& s 63)))) 1)
           (self (+ i 1) (% (* s 75) 65537)))))
     0 1)
    r))
  (def %dj-inputs (list (%dj-fill 0 600) (%dj-fill 1 5000) (%dj-fill 2 5000)))
  (def %dj-sizes (list 600 5000 5000))
  (def %dj-write (fn (_) (List map (fn (_ i) (Deflate zlib (List ref i %dj-inputs) 0 (List ref i %dj-sizes))) (list 0 1 2))))
  (def %dj-pure (%dj-write))
  (Deflate jit!)
  (def %dj-jit (%dj-write))
  (def %dj-same? (fn (_ a b) (and (= (first (rest a)) (first (rest b)))
    (= 0 ((prim-ref (lit mem) (lit cmp)) ((prim-ref (lit str) (lit ->ptr)) (first a)) ((prim-ref (lit str) (lit ->ptr)) (first b)) (first (rest a)))))))
  (write (List map (fn (_ i) (%dj-same? (List ref i %dj-pure) (List ref i %dj-jit))) (list 0 1 2))))
```
---
    (#t #t #t)

### 60000 bytes in several blocks, read back by Inflate and by libz

Past the codec's bar, so the engine is the writer without asking; past one
block of 16384 tokens, and past the output's first growth many times over.

```x
(do (import x/codec/deflate) (import x/codec/inflate) (import x/codec/zlib)
  (def %dj-bytes (fn (_ r n) (let ((p ((prim-ref (lit str) (lit ->ptr)) r)))
    ((fn (self i acc) (if (< i 0) acc (self (- i 1) (pair (& ((prim-ref (lit ptr) (lit ref)) p i 1) 255) acc)))) (- n 1) ()))))
  (write
    ((fn (_)
       (def in ((prim-ref (lit str) (lit make)) 60000))
       (def p ((prim-ref (lit str) (lit ->ptr)) in))
       ((fn (self i s) (when (< i 60000) (do ((prim-ref (lit ptr) (lit set!)) p i (if (< (% i 1000) 500) (+ 32 (& s 63)) (+ 97 (% i 7))) 1) (self (+ i 1) (% (* s 75) 65537))))) 0 1)
       (def z (Deflate zlib in 0 60000))
       (def back (Inflate zlib (first z) 0 (first (rest z))))
       (def same? (= 0 ((prim-ref (lit mem) (lit cmp)) p ((prim-ref (lit str) (lit ->ptr)) (first back)) 60000)))
       (def libz (Zlib decompress (%dj-bytes (first z) (first (rest z))) 60000))
       (list ((Compiled named (lit deflate)) state) (< (first (rest z)) 30000) (first (rest back)) same?
             (List length libz) (List ref 777 libz) (List ref 1777 libz))))))
```
---
    ('compiled #t 60000 #t 60000 97 103)
