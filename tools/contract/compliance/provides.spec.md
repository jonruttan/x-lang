# Compliance: a declared capability group resolves

Run once per `(provides ...)` row in the engine's x-engine.xon. The coordinates to
look for arrive as DATA, injected as `%expect-coords` and `%expect-bare` by
`tools/contract/gen-compliance.sh` -- this file is static, and the shell computes
a list rather than emitting x-lang.

The check is one-directional on purpose: it fails when a DECLARED capability is
absent. An engine that provides more than it declares is not the problem this
gate exists for.

### every coordinate the group declares actually resolves

```scheme
(%ok (= (+ (%count-missing %expect-coords 0) (%count-missing-bare %expect-bare 0)) 0))
```
---
    *** ERROR: ok
