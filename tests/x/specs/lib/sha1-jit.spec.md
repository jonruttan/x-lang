# Sha1 JIT engine

# @weight 15
# @timeout-scale 4

The compiled digest engine behind `(Sha1 jit!)`, built by x/codec/sha-jit
from the same fill and driver as SHA-256's, with SHA-1's round schedule.
It is adopted only after the maker's own differential check against the
pure-x digest; these cases re-prove agreement through the class.

## the engine builds and is adopted

### jit! reports the engine active, and is idempotent

```x
(do
  (import x/codec/sha1)
  (display (list (Sha1 jit!) (Sha1 jit!) ((Compiled named (lit sha1)) state))))
```
---
    (#t #t compiled)

### the FIPS vectors hold through the engine

```x
(do
  (import x/codec/sha1)
  (Sha1 jit!)
  (display (Sha1 hex "abc"))(newline)
  (display (Sha1 hex ""))(newline)
  (display (Sha1 hex "abcdbcdecdefdefgefghfghighijhijkijkljklmklmnlmnomnopnopq")))
```
---
```output
a9993e364706816aba3e25717850c26c9cd0d89d
da39a3ee5e6b4b0d3255bfef95601890afd80709
84983e441c3bd26ebaae4aa1f95129e5e54670f1
```

### the engine agrees with pure-x on lengths the vectors do not cover

Every length class the padding branches on: one under the length-tail
boundary (55), one over it (57), a block multiple (64) and three blocks.
The pure-x side is the module's own digest, read through its environment.

```x
(do
  (import x/codec/sha1)
  (Sha1 jit!)
  (def %s1-ref (eval (lit %digest-words) (module x/codec/sha1)))
  (def %s1-hex (eval (lit %hex) (module x/codec/sha1)))
  (def %s1-mk (fn (_ n) (Str8 pad-right n #\q "z")))
  (def %s1-agree
    (fn (_ n) (str=? (Sha1 hex (%s1-mk n)) (%s1-hex (%s1-ref (%s1-mk n))))))
  (display (list (%s1-agree 55) (%s1-agree 57) (%s1-agree 64) (%s1-agree 150))))
```
---
    (#t #t #t #t)

### SHA-256's engine still agrees after SHA-1's is built in the same process

The two share one module, one fill and one driver; each keeps its own
scratch and H.

```x
(do
  (import x/codec/sha1)
  (import x/codec/sha256)
  (Sha1 jit!)
  (Sha256 jit!)
  (display (list (Sha1 hex "abc") (Sha256 hex "abc"))))
```
---
    (a9993e364706816aba3e25717850c26c9cd0d89d ba7816bf8f01cfea414140de5dae2223b00361a396177a9cb410ff61f20015ad)
