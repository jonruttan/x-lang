# GHASH JIT engine

# @weight 15
# @timeout-scale 4

The compiled hash behind `(Ghash jit!)`, built by x/codec/ghash-jit: the
4-bit table multiply, one function taking a block a nibble a call and
going on to the next block while the run and the input allow.  It is
adopted only after the maker's own differential check against the pure-x
hash; these cases re-prove agreement through the class.  The file builds
an engine, so it carries the weight of one.

## the engine builds and is adopted

### jit! reports the engine active, and is idempotent

```x
(do
  (import x/codec/ghash)
  (display (list (Ghash jit!) (Ghash jit!) ((Compiled named (lit ghash)) state))))
```
---
    (#t #t compiled)

### test cases 2 and 4 hold through the engine

```x
(do
  (import x/codec/hex)
  (import x/codec/ghash)
  (Ghash jit!)
  (def %gh-bref (prim-ref (lit str) (lit byte-ref)))
  (def %gh-c->i (prim-ref (lit char) (lit ->int)))
  (def %gh-hex
    (fn (_ s n)
      (Hex encode-bytes
        ((fn (self i acc) (if (< i 0) acc (self (- i 1) (pair (%gh-c->i (%gh-bref s i)) acc))))
         (- n 1) ()))))
  (display (list
    (%gh-hex (Ghash hash (Hex decode "66e94bd4ef8a2c3b884cfa59ca342b2e") "" 0 0
               (Hex decode "0388dace60b6a392f328c2b971b2fe78") 0 16) 16)
    (%gh-hex (Ghash hash (Hex decode "b83b533708bf535d0aa6e52980d53b78")
               (Hex decode "feedfacedeadbeeffeedfacedeadbeefabaddad2") 0 20
               (Hex decode "42831ec2217774244b7221b784d0d49ce3aa212f2c02a4e035c17e2329aca12e21d514b25466931c7d8f6a5aac84aa051ba30b396a0aac973d58e091") 0 60) 16))))
```
---
    (f38cbb1ad69223dcc3457ae5b6b0f885 698e57f70e6ecc7fd9463b7260a9ae5f)

### the engine agrees with pure-x across runs and keys

The pure-x side is the module's own block loop, read through its
environment.  The lengths cover one block, a run's four, one over, and a
long input; the keys change between calls, so the engine's multiples of
H are made again, and the last call goes back to the first key.

```x
(do
  (import x/codec/ghash)
  (Ghash jit!)
  (def %gh-pure (eval (lit %hash-blocks) (module x/codec/ghash)))
  (def %gh-eng ((Compiled named (lit ghash)) compiled))
  (def %gh-ramp
    (fn (_ n from step)
      (def r ((prim-ref (lit str) (lit make)) n))
      (def p ((prim-ref (lit str) (lit ->ptr)) r))
      ((fn (self i) (unless (= i n) (do ((prim-ref (lit ptr) (lit set!)) p i (& (+ from (* i step)) 255) 1) (self (+ i 1))))) 0)
      r))
  (def %gh-in (%gh-ramp 4096 7 131))
  (def %gh-agree
    (fn (_ h n) (str=? (%gh-hex (%gh-eng h %gh-in n) 16) (%gh-hex (%gh-pure h %gh-in n) 16))))
  (import x/codec/hex)
  (def %gh-bref (prim-ref (lit str) (lit byte-ref)))
  (def %gh-c->i (prim-ref (lit char) (lit ->int)))
  (def %gh-hex
    (fn (_ s n)
      (Hex encode-bytes
        ((fn (self i acc) (if (< i 0) acc (self (- i 1) (pair (%gh-c->i (%gh-bref s i)) acc))))
         (- n 1) ()))))
  (def %gh-k1 (%gh-ramp 16 1 37))
  (def %gh-k2 (%gh-ramp 16 255 254))
  (display (list (%gh-agree %gh-k1 16) (%gh-agree %gh-k2 64) (%gh-agree %gh-k2 80)
                 (%gh-agree %gh-k1 4096) (%gh-agree %gh-k1 48))))
```
---
    (#t #t #t #t #t)
