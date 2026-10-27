# Bunzip2 JIT engine

# @weight 15
# @timeout-scale 4

The compiled symbol, link and walk loops behind `(Bunzip2 jit!)`.  They are
adopted only after decoding two check streams exactly as the pure-x loops
do; these cases re-prove agreement through the class, on streams written by
bzip2 1.0.8 at `-9`.  `%bj-region` puts a byte list into a byte region.

## the engine builds and is adopted

### jit! reports the engine active, and is idempotent

```x
(do (import x/codec/bunzip2)
  (display (list (Bunzip2 jit!) (Bunzip2 jit!) ((Compiled named (lit bunzip2)) state))))
```
---
    (#t #t compiled)

## agreement through the engine

### a varied input: every symbol group, and runs

```x
(do (import x/codec/bunzip2) (import x/codec/hex)
  (Bunzip2 jit!)
  (def %bj-region (fn (_ bs) (let ((r ((prim-ref (lit str) (lit make)) (List length bs))))
    (let ((p ((prim-ref (lit str) (lit ->ptr)) r)))
      (do ((fn (self i l) (unless (null? l) (do ((prim-ref (lit ptr) (lit set!)) p i (first l) 1) (self (+ i 1) (rest l))))) 0 bs) r)))))
  (def %bj-z (Hex decode-bytes (Str8 append
    "425a6839314159265359b67dd4d20000019f803ffffffffffffffffffffff03000b80e1a1934d0d323434c8c8323234320313464d0064c8c431c343269a1a64686991906464686406268c9a00c9918861155462340003269a68d3201a064c86464308c8300179897c300617138dc8c30d00d10d274dd4755d60d70d80d9769db771dd0de088115df633c0c70e108ec8789e364bc812825bcaf33cef43d21d41d6cc7b1ed7b9ef0f009ace7c59ed07c83cc3d1a2d27d5f6698540f77e1f96ab59ae1603e9fb6cb69fc7f43f83fdb6dc6eb79be18030b89c6e4728bb9229c28485b3eea690")))
  (def %bj-r (Bunzip2 decode (%bj-region %bj-z) 0 (List length %bj-z)))
  (def %bj-p ((prim-ref (lit str) (lit ->ptr)) (first %bj-r)))
  (write (list (first (rest %bj-r)) (first (rest (rest %bj-r)))
               ((fn (self i) (if (= i 300) #t (if (= (& ((prim-ref (lit ptr) (lit ref)) %bj-p i 1) 255) (+ 33 (% (* i 7) 90))) (self (+ i 1)) #f))) 0))))
```
---
    (300 228 #t)

### an output that outgrows its region many times over

The walk returns whenever less than 256 bytes of room are left: 20000
bytes of a period of 26 cross that many times, and the step's budget too.

```x
(do (import x/codec/bunzip2) (import x/codec/hex)
  (Bunzip2 jit!)
  (def %bj-region (fn (_ bs) (let ((r ((prim-ref (lit str) (lit make)) (List length bs))))
    (let ((p ((prim-ref (lit str) (lit ->ptr)) r)))
      (do ((fn (self i l) (unless (null? l) (do ((prim-ref (lit ptr) (lit set!)) p i (first l) 1) (self (+ i 1) (rest l))))) 0 bs) r)))))
  (def %bj-z (Hex decode-bytes (Str8 append
    "425a6839314159265359f64b702b00018086003ffffff03000d8050000064c82800003264052aa00000d335328058ce016900b100b6402dc80b7c02e100b8c02e500b9a02e900bac02ed00bbc02f080bcc02f500bdc02f900bea02ca017e8059c02d20161017f177245385090f64b702b0")))
  (def %bj-r (Bunzip2 decode (%bj-region %bj-z) 0 (List length %bj-z)))
  (def %bj-p ((prim-ref (lit str) (lit ->ptr)) (first %bj-r)))
  (write (list (first (rest %bj-r)) (first (rest (rest %bj-r)))
               ((fn (self i) (if (= i 20000) #t (if (= (& ((prim-ref (lit ptr) (lit ref)) %bj-p i 1) 255) (+ 65 (% (* i 31) 26))) (self (+ i 1)) #f))) 0))))
```
---
    (20000 113 #t)

### a changed block CRC is refused through the engine too

```x
(do (import x/codec/bunzip2) (import x/codec/hex)
  (Bunzip2 jit!)
  (def %bj-region (fn (_ bs) (let ((r ((prim-ref (lit str) (lit make)) (List length bs))))
    (let ((p ((prim-ref (lit str) (lit ->ptr)) r)))
      (do ((fn (self i l) (unless (null? l) (do ((prim-ref (lit ptr) (lit set!)) p i (first l) 1) (self (+ i 1) (rest l))))) 0 bs) r)))))
  (def %bj-z (Hex decode-bytes "425a68393141592653599f3c11f20000035100001040040244a0002129a3108602f28370a1e2ee48a70a1213e7823e60"))
  (guard (e (e msg)) (Bunzip2 decode (%bj-region %bj-z) 0 (List length %bj-z))))
```
---
    "Bunzip2: a block's CRC is wrong"

### a stream cut short inside its symbols is refused through the engine too

```x
(do (import x/codec/bunzip2) (import x/codec/hex)
  (Bunzip2 jit!)
  (def %bj-region (fn (_ bs) (let ((r ((prim-ref (lit str) (lit make)) (List length bs))))
    (let ((p ((prim-ref (lit str) (lit ->ptr)) r)))
      (do ((fn (self i l) (unless (null? l) (do ((prim-ref (lit ptr) (lit set!)) p i (first l) 1) (self (+ i 1) (rest l))))) 0 bs) r)))))
  (def %bj-z (Hex decode-bytes "425a68393141592653599f3c11f30000035100001040040244a0002129a3108602f28370a1e2ee48a70a1213e7823e60"))
  (guard (e (list (e msg) (e data))) (Bunzip2 decode (%bj-region %bj-z) 0 40)))
```
---
    ("Bunzip2: the input ends inside the stream" (('bunzip . 'data) ('short . #t)))
