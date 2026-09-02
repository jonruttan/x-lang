# Sha256 JIT engine

# @weight 15
# @timeout-scale 4

The compiled digest engine behind `(Sha256 jit!)`. Untagged on purpose:
the assembler has both ARM64 and x86-64 backends now, so the engine
builds — and must prove itself — on every CI host. The
`@timeout-scale` above buys the BUILD its budget: compiling the engine
is a one-off ~3500-node generation, and sanitizer instrumentation
multiplies it several-fold (the asan gate's 180s base was exceeded on
real CI hardware — exit 124, no sanitizer report). (The graceful
refusal on a host with NO backend keeps its guard and its teeth, but no
CI machine can exercise it any more; the adoption gate's differential
check is what actually protects it.)

The engine is adopted only after `%sha-jit-make`'s own differential
check: agreement with the pure-x digest on the FIPS vectors plus a
multi-block padding case, any disagreement raising instead of adopting.
These cases then re-prove agreement THROUGH THE CLASS API, where the
dispatch actually happens.

## the engine builds and is adopted

### jit! reports the engine active, and is idempotent

Seconds of compile on the first call; the second is a state read.

```x
(do
  (import x/codec/sha256)
  (display (list (Sha256 jit!) (Sha256 jit!))))
```
---
    (#t #t)

### the FIPS vectors hold through the engine

Same process as above, so the engine is active for these.

```x
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

```x
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
