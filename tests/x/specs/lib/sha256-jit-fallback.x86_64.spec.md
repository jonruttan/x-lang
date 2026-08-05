# Sha256 JIT engine: the graceful refusal (x86_64)

Arch-tagged to x86_64 deliberately: the ARM64-only engine must REFUSE
on this host — `jit!` answering #f, never raising, never a wrong hash —
and the pure-x digest must carry on exactly as before. This is the
fallback path the arm64 sibling can never exercise, and the ubuntu CI
runs it on every push.

## the refusal

### jit! answers #f and hex still digests correctly

```scheme
(do
  (import x/codec/sha256)
  (display (list (Sha256 jit!)
                 (str=? (Sha256 hex "abc")
                        "ba7816bf8f01cfea414140de5dae2223b00361a396177a9cb410ff61f20015ad"))))
```
---
    (#f #t)
