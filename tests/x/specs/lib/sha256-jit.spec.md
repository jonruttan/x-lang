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

The engine is adopted only after `sha-jit-make`'s own differential
check: agreement with the pure-x digest on the FIPS vectors plus a
multi-block padding case, any disagreement raising instead of adopting.
These cases then re-prove agreement THROUGH THE CLASS API, where the
dispatch actually happens.

## the engine builds and is adopted

### the engine is built for an input that repays it, not for a total

The bar is `%sha-jit-threshold` bytes in one input. Two inputs just under
it, whose total is well over, stay pure-x: a total says nothing about what
is left to digest. One input over it builds. FIRST in this file on purpose:
the cases below build the engine explicitly, and the state is per process.

```x
(do
  (import x/codec/sha256)
  (def %under (Str8 repeat (- %sha-jit-threshold 1) "a"))
  (Sha256 hex %under)
  (Sha256 hex %under)
  (def %after-two (null? %sha-jit-engine))
  (Sha256 hex (Str8 repeat %sha-jit-threshold "a"))
  (display (list %after-two (not (null? %sha-jit-engine)) (Sha256 jit!))))
```
---
    (#t #t #t)

### jit! reports the engine active, and is idempotent

Seconds of compile on the first call; the second is a state read.

```x
(do
  (import x/codec/sha256)
  (display (list (Sha256 jit!) (Sha256 jit!))))
```
---
    (#t #t)

### the engine's two bodies come back from the cache

`jit!` compiles a round schedule and a fill body; both are far past the
128 nodes the cache once refused to key, and the fill body's record file
is past the 64KB one read used to be. A load answering a callable for each
is what keeps the build at seconds of relocation instead of seconds of
compile, in every process that digests an archive.

```x
(do
  (import x/codec/sha256)
  (Sha256 jit!)
  (import x/tool/asm-cache)
  (def %ac (fn (_ name) (eval name (module x/tool/asm-cache))))
  (def %sj (fn (_ name) (eval name (module x/codec/sha256-jit))))
  (def %hit? (fn (_ e)
    (def %t ((%ac (lit %asm-cache-text)) e () #f))
    (not (null? ((%ac (lit %asm-cache-load)) %t ((%ac (lit %asm-cache-path)) %t) ())))))
  (display (list (%hit? (%sj (lit %sj-rounds-expr))) (%hit? (%sj (lit %sj-fill-expr))))))
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
