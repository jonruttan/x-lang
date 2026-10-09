# Sha3 JIT engine

# @weight 15
# @timeout-scale 4

The compiled Keccak engine behind `(Sha3 jit!)`, built by x/codec/sha3-jit:
absorb, theta, rho-pi and chi-iota, each a compiled function over the
lanes in a scratch buffer.  It is adopted only after the maker's own
differential check against the pure-x digest; these cases re-prove
agreement through the class.  The file builds an engine, so it carries
the weight of one.

## the engine builds and is adopted

### jit! reports the engine active, and is idempotent

```x
(do
  (import x/codec/sha3)
  (display (list (Sha3 jit!) (Sha3 jit!) ((Compiled named (lit sha3)) state))))
```
---
    (#t #t compiled)

### the widths and the padding's boundaries hold through the engine

```x
(do
  (import x/codec/sha3)
  (Sha3 jit!)
  (display (Sha3 hex 224 "abc"))(newline)
  (display (Sha3 hex 512 ""))(newline)
  (display (Sha3 hex 256 (Str8 pad-right 135 #\z "")))(newline)
  (display (Sha3 hex 256 (Str8 pad-right 136 #\y "x"))))
```
---
```output
e642824c3f8cf24ad09234ee7d3c766fc9a3a5168d0c94ad73b46fdf
a69f73cca23a9ac5c8b567dc185a756e97c982164fe25859e0d1dcc1475c80a615b2123af1f5f94c11e3e9402c3ac558f500199d95b6d3e301758586281dcd26
42793503c1b01806dc99fc04d80db0dd244013e3ce66b6fab9b9d542e6c867e4
d64acb4b7ff9bcd79db07d858c4b9b18a4ae1911b873995c4a1649b1c7320366
```

### 64 KB, through the engine, as the system's openssl answers

```x
(do
  (import x/codec/sha3)
  (Sha3 jit!)
  (display (Sha3 hex 256 (Str8 pad-right 65536 #\a ""))))
```
---
    e304a7a94bc86fe7bc81c4c80906794f9f5dde280b8a76027cbfd2e49aa3c395
