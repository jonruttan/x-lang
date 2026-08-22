# Compliance: `(param word-size N)` agrees with the engine

The engine's build DECLARES its word size; `lib/x/boot/data.x` PROBES it at boot
by round-tripping 2^32 through a pointer cast. Two independent answers to one
question, and they can disagree in exactly one way: the integer cannot faithfully
carry a pointer.

That is the ptr/int confusion class, which 32-bit builds have surfaced in this
project before, and it is worth catching as a loud mismatch here rather than as
corruption at the first reflective read. The library is entitled to trust the
probe — everything in `reflect.x` is built on it — so a declaration that
contradicts it means the declaration is wrong, or the casts are.

The probe below is the same one `data.x` runs, written with the catalog door
because this suite loads no library.

### the declared word size is the one the engine actually has

```scheme
(def %i2p (%coord (lit int) (lit ->ptr)))
(def %p2i (%coord (lit ptr) (lit ->int)))
(def %probed (match ((< 0 (%p2i (%i2p 4294967296))) 8) (#t 4)))
(%ok (= %probed %param-word-size))
```
---
    *** ERROR: ok
