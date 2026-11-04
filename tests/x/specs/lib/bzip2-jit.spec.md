# Bzip2 JIT engine

# @weight 15
# @timeout-scale 4

The compiled run, sort, move-to-front, selection and writing loops behind
`(Bzip2 jit!)`.  They are adopted only after writing the codec's check
inputs exactly as the pure-x loops do; these cases re-prove agreement
through the class, against streams bzip2 1.0.8 wrote at the same level.
`%bj-hex` reads an output region back as hex.

## the engine builds and is adopted

### jit! reports the engine active, and is idempotent

```x
(do (import x/codec/bzip2)
  (display (list (Bzip2 jit!) (Bzip2 jit!) ((Compiled named (lit bzip2)) state))))
```
---
    (#t #t compiled)

## agreement through the engine

### an input past the 4KB bar, where compress builds the engine itself

```x
(do (import x/codec/bzip2) (import x/codec/hex)
  (def %bj-hex (fn (_ r n) (let ((p ((prim-ref (lit str) (lit ->ptr)) r)))
    (Hex encode-bytes ((fn (self i acc) (if (< i 0) acc (self (- i 1) (pair (& ((prim-ref (lit ptr) (lit ref)) p i 1) 255) acc)))) (- n 1) ())))))
  (def %bj-r (Bzip2 compress (Str8 repeat 1024 "abcab") 9))
  (write (list (equal? (%bj-hex (first %bj-r) (first (rest %bj-r)))
                       "425a6839314159265359f59b36da0003ff81003800200030cc05536a4004004003001e2ee48a70a121eb366db4")
               (first (rest %bj-r)))))
```
---
    (#t 45)

### more input than a block holds, so the stream carries two

A level of 1 is blocks of 100000 bytes, and 163840 bytes of input fill one
and start another.

```x
(do (import x/codec/bzip2) (import x/codec/hex)
  (Bzip2 jit!)
  (def %bj-hex (fn (_ r n) (let ((p ((prim-ref (lit str) (lit ->ptr)) r)))
    (Hex encode-bytes ((fn (self i acc) (if (< i 0) acc (self (- i 1) (pair (& ((prim-ref (lit ptr) (lit ref)) p i 1) 255) acc)))) (- n 1) ())))))
  (def %bj-r (Bzip2 compress (Str8 repeat 32768 "abcab") 1))
  (write (list (equal? (%bj-hex (first %bj-r) (first (rest %bj-r))) (Str8 append
    "425a6831314159265359703211c6004e1c010038002000405240cc6e2a0a8d4a0a8e8a82a315054798a0ac9329acb0e6e"
    "65680256ac0801c0010002833014a6988aa16a1542c4550bba8550b88aa178bb9229c284840d4f79080"))
               (first (rest %bj-r)))))
```
---
    (#t 90)
