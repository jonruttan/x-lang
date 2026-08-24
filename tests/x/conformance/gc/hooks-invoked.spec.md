# Conformance: the collector invokes its hooks (profile `gc`)

`applicative/gc-hooks.spec.md` asks whether a registered hook SURVIVES a
collection. That is true of a hook nobody ever calls, and it passed 13 of 13
against an engine that only ever appended to the list — so the law needs a check
that counts.

`x_heap_mark_phase` opens with `x_heap_run_hooks(mark_hooks)` and
`x_heap_sweep_phase` opens with the free hooks: the engine IS the consuming
layer. See [docs/engine-laws.md](../../../../docs/engine-laws.md).

### a registered mark hook is invoked once per collection

covers: heap/mark-hook! heap/collect

```scheme
(def %mh (%coord (lit heap) (lit mark-hook!)))
(def %gc (%coord (lit heap) (lit collect)))
(def hits 0)
(%mh (fn (_) (set! hits (+ hits 1))))
(%gc)
(%gc)
(%ok (= hits 2))
```
---
    *** ERROR: ok

### a mark hook runs BEFORE the marking passes

covers: heap/mark-hook! heap/mark-root! heap/collect

The ordering was paid for with a use-after-free. Everything a hook allocates is
born unmarked, so hooks running after the mark passes let an allocation that
ESCAPED into reachable state — a `mark-root!` spine cell, a value stored through
`set!` — be freed by the same sweep, leaving a reachable dangling pointer for the
next collection to walk.

A hook that allocates and escapes its allocation must therefore find it intact.

```scheme
(def %mh (%coord (lit heap) (lit mark-hook!)))
(def %gc (%coord (lit heap) (lit collect)))
(def kept ())
(%mh (fn (_) (set! kept (pair 7 kept))))
(%gc)
(%gc)
(%ok (= (first kept) 7))
```
---
    *** ERROR: ok
