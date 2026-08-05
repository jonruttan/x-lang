# Sha256 JIT engine (arm64)

The compiled digest engine behind `(Sha256 jit!)`. Arch-tagged: the
engine compiles through the ARM64 assembler backend, so this file runs
only on A64 hosts — its x86_64 sibling asserts the graceful refusal.

The engine is adopted only after `%sha-jit-make`'s own differential
check: agreement with the pure-x digest on the FIPS vectors plus a
multi-block padding case, any disagreement raising instead of adopting.
These cases then re-prove agreement THROUGH THE CLASS API, where the
dispatch actually happens.

## the engine builds and is adopted

### jit! reports the engine active, and is idempotent

Seconds of compile on the first call; the second is a state read.

```scheme
(do
  (import x/codec/sha256)
  (display (list (Sha256 jit!) (Sha256 jit!))))
```
---
    (#t #t)

### the FIPS vectors hold through the engine

Same process as above, so the engine is active for these.

```scheme
(do
  (import x/codec/sha256)
  (display (Sha256 hex "abc"))(newline)
  (display (Sha256 hex ""))(newline)
  (display (Sha256 hex "abcdbcdecdefdefgefghfghighijhijkijkljklmklmnlmnomnopnopq")))
```
---
```output
ba7816bf8f01cfea414140de5dae2223b00361a396177a9cb410ff61f20015ad
e3b0c44298fc1c149afbf4c8996fb92427ae41e4649b934ca495991b7852b855
248d6a61d20638b8e5c026930c3e6039a33ce45964ff2167f6ecedd419db06c1
```

### the engine agrees with pure-x on lengths the vectors do not cover

Every length class the padding logic branches on: block-multiple (64),
one under the length-tail boundary (55), one over it (56 is a vector;
57 is not), and a 3-block message. The pure-x side is `%sha-digest-words`
called directly — the reference, bypassing the engine dispatch.

```scheme
(do
  (import x/codec/sha256)
  (Sha256 jit!)
  (def %mk (fn (_ n) (Str8 pad-right n #\q "z")))
  (def %agree
    (fn (_ n) (str=? (Sha256 hex (%mk n)) (%sha-hex-list (%sha-digest-words (%mk n))))))
  (display (list (%agree 55) (%agree 57) (%agree 64) (%agree 150))))
```
---
    (#t #t #t #t)
