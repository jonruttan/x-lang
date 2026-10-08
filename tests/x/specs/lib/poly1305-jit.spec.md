# Poly1305 JIT engine

# @weight 15
# @timeout-scale 4

The compiled block loop behind `(Poly1305 jit!)`, built by
x/codec/poly1305-jit: one function a block, the five-limb product and
its carries straight-line, calling itself for the next block while the
run and the region allow.  It is adopted only after the maker's own
differential check against the pure-x loop; these cases re-prove
agreement through the class.  The file builds an engine, so it carries
the weight of one.

## the engine builds and is adopted

### jit! reports the engine active, and is idempotent

```x
(do
  (import x/codec/poly1305)
  (display (list (Poly1305 jit!) (Poly1305 jit!) ((Compiled named (lit poly1305)) state))))
```
---
    (#t #t compiled)

### the RFC's vector and the reduction's edges hold through the engine

```x
(do
  (import x/codec/hex)
  (import x/codec/poly1305)
  (Poly1305 jit!)
  (def %pp-bref (prim-ref (lit str) (lit byte-ref)))
  (def %pp-c->i (prim-ref (lit char) (lit ->int)))
  (def %pp-hex
    (fn (_ s n)
      (Hex encode-bytes
        ((fn (self i acc) (if (< i 0) acc (self (- i 1) (pair (%pp-c->i (%pp-bref s i)) acc))))
         (- n 1) ()))))
  (display (Hex encode (Poly1305 mac
    (Hex decode "85d6be7857556d337f4452fe42d506a80103808afb0db2fd4abff6af4149f51b")
    "Cryptographic Forum Research Group")))
  (newline)
  (display (list
    (%pp-hex (Poly1305 mac
      (Hex decode "0200000000000000000000000000000000000000000000000000000000000000")
      (Hex decode "ffffffffffffffffffffffffffffffff") 0 16) 16)
    (%pp-hex (Poly1305 mac
      (Hex decode "0200000000000000000000000000000000000000000000000000000000000000")
      (Hex decode "fdffffffffffffffffffffffffffffff") 0 16) 16))))
```
---
```output
a8061dc1305136c6c22b8baf0c0127a9
(03000000000000000000000000000000 faffffffffffffffffffffffffffffff)
```

### the engine agrees with pure-x on every way a message can end

The pure-x side is the module's own block loop, read through its
environment and run through the class's own finish; the lengths cover a
short message, a block, one over, a run longer than one entry's 128
blocks, and the on-its-own threshold, where mac builds the engine itself.

```x
(do
  (import x/codec/hex)
  (import x/codec/poly1305)
  (import x/type/vector)
  (Poly1305 jit!)
  (def %pp-blocks (eval (lit %blocks!) (module x/codec/poly1305)))
  (def %pp-rv (eval (lit %r-vector) (module x/codec/poly1305)))
  (def %pp-tail (eval (lit %tail) (module x/codec/poly1305)))
  (def %pp-finish (eval (lit %finish) (module x/codec/poly1305)))
  (def %pp-k (Hex decode "85d6be7857556d337f4452fe42d506a80103808afb0db2fd4abff6af4149f51b"))
  (def %pp-in (Str8 pad-right 5000 #\q "z"))
  (def %pp-pure
    (fn (_ n)
      (def h (Vector make 5 0))
      (def rv (%pp-rv %pp-k))
      (def whole (<< (>> n 4) 4))
      (%pp-blocks h rv %pp-in 0 whole 16777216)
      (unless (= whole n) (%pp-blocks h rv (%pp-tail %pp-in whole (- n whole)) 0 16 0))
      (Hex encode (%pp-finish h %pp-k))))
  (def %pp-agree
    (fn (_ n) (str=? (Hex encode (Poly1305 mac %pp-k %pp-in 0 n)) (%pp-pure n))))
  (display (list (%pp-agree 1) (%pp-agree 16) (%pp-agree 17) (%pp-agree 2100) (%pp-agree 5000))))
```
---
    (#t #t #t #t #t)

### binary input: every byte value through the engine, and a region

The bytes 0..255 four times over; the tags are the system openssl's for
the same bytes, whole and from byte 256.

```x
(do
  (import x/codec/hex)
  (import x/codec/poly1305)
  (Poly1305 jit!)
  (def %pp-set (prim-ref (lit ptr) (lit set!)))
  (def %pp-in ((prim-ref (lit str) (lit make)) 1024))
  (def %pp-p ((prim-ref (lit str) (lit ->ptr)) %pp-in))
  ((fn (self i) (unless (= i 1024) (do (%pp-set %pp-p i (& i 255) 1) (self (+ i 1))))) 0)
  (def %pp-k (Str8 pad-right 32 #\k ""))
  (display (list (Hex encode (Poly1305 mac %pp-k %pp-in 0 1024))
                 (Hex encode (Poly1305 mac %pp-k %pp-in 256 768)))))
```
---
    (ad8477617c1ae36560554398604e210d 9423d8bc67db067a5c43d9615bfba4bc)
