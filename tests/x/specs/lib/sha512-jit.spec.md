# Sha512 JIT engine

# @weight 15
# @timeout-scale 4

The compiled digest engine behind `(Sha512 jit!)`, built by
x/codec/sha512-jit in sha-jit's fold+fill shape on the lane's 64-bit
words.  It is adopted only after the maker's own differential check
against the pure-x digest; these cases re-prove agreement through the
class.  The file builds an engine, so it carries the weight of one.

## the engine builds and is adopted

### jit! reports the engine active, and is idempotent

```x
(do
  (import x/codec/sha512)
  (display (list (Sha512 jit!) (Sha512 jit!) ((Compiled named (lit sha512)) state))))
```
---
    (#t #t compiled)

### the FIPS vectors hold through the engine

```x
(do
  (import x/codec/sha512)
  (Sha512 jit!)
  (display (Sha512 hex "abc"))(newline)
  (display (Sha512 hex ""))(newline)
  (display (Sha512 hex "abcdefghbcdefghicdefghijdefghijkefghijklfghijklmghijklmnhijklmnoijklmnopjklmnopqklmnopqrlmnopqrsmnopqrstnopqrstu")))
```
---
```output
ddaf35a193617abacc417349ae20413112e6fa4e89a97ea20a9eeee64b55d39a2192992a274fc1a836ba3c23a3feebbd454d4423643ce80e2a9ac94fa54ca49f
cf83e1357eefb8bdf1542850d66d8007d620e4050b5715dc83f4a921d36ce9ce47d0d13c5d85f2b0ff8318d2877eec2f63b931bd47417a81a538327af927da3e
8e959b75dae313da8cf4f72814fc143f8f7779c6eb9f7fa17299aeadb6889018501d289e4900f7e4331b99dec4b5433ac7d329eeb6dd26545e96e55b874be909
```

### the engine agrees with pure-x on lengths the vectors do not cover

Every length class the padding branches on: one under the length-tail
boundary (111), one over it (113), a block multiple (128) and three
blocks.  The pure-x side is the module's own digest, read through its
environment.

```x
(do
  (import x/codec/sha512)
  (Sha512 jit!)
  (def %s5-ref (eval (lit %digest-words) (module x/codec/sha512)))
  (def %s5-ih (eval (lit %ih) (module x/codec/sha512)))
  (def %s5-hex (eval (lit %hex) (module x/codec/sha512)))
  (def %s5-mk (fn (_ n) (Str8 pad-right n #\q "z")))
  (def %s5-agree
    (fn (_ n) (str=? (Sha512 hex (%s5-mk n)) (%s5-hex (%s5-ref %s5-ih (%s5-mk n))))))
  (display (list (%s5-agree 111) (%s5-agree 113) (%s5-agree 128) (%s5-agree 300))))
```
---
    (#t #t #t #t)

### SHA-384 rides the same engine, from its own initial words

```x
(do
  (import x/codec/sha384)
  (display (list (Sha384 jit!) ((Compiled named (lit sha512)) state)))
  (newline)
  (display (Sha384 hex "abc"))
  (newline)
  (display (Sha384 hex (Str8 pad-right 300 #\q "z"))))
```
---
```output
(#t compiled)
cb00753f45a35e8bb5a03d699ac65007272c32ab0eded1631a8b605a43ff5bed8086072ba1e7cc2358baeca134c825a7
ce18e8713e167e3c1b2b99e204943573b1152d09cb83b7088f1ae121ac211aec6695d8c4b5a59dd62bbf664e0cbb8c3d
```

### binary input through the engine, past NULs

```x
(do
  (import x/codec/sha512)
  (Sha512 jit!)
  (def %s5-set (prim-ref (lit ptr) (lit set!)))
  (def %s5-r ((prim-ref (lit str) (lit make)) 5))
  (def %s5-p ((prim-ref (lit str) (lit ->ptr)) %s5-r))
  ((fn (self i bs)
     (unless (null? bs) (do (%s5-set %s5-p i (first bs) 1) (self (+ i 1) (rest bs)))))
   0 (list 65 0 66 0 67))
  (display (Sha512 hex-n %s5-r 5)))
```
---
    4c7b7b21845a66228729b18d1baab95424444cec41245000d98b10ccb55fdaa567d363290cdcdf0f004d23dc4c39aeb44c2b18076705d072a805e3fc31ac72ba
