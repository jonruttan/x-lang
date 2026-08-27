# Compliance: `(guarantee int/ptr-same-width)`

The fixnum and the pointer are the same width. x-engine-c asserts this at COMPILE
time (`sizeof(x_int_t) == sizeof(void *)` in its `ext/x-expr/include/x.h`), which makes
it the strongest row that engine declares — but a second engine states it in
prose like any other claim, and prose is what this suite exists to falsify.

x-lang leans on it twice over: `lib/x/boot/data.x` sizes a word by round-tripping
2^32 through a pointer cast, and six sites in the library hold an object's address
as an integer across an allocating expression. An engine whose integer could not
carry a pointer would lose the high bits silently — the address would come back
truncated and address something else, which is corruption rather than an error.

The case takes a real object's address rather than an arbitrary number: a
plausible integer might survive a round trip by luck, but an object either comes
back as itself or does not.

### an object's address survives a round trip through an integer

```scheme
(def %o2p (%coord (lit obj) (lit ->ptr)))
(def %p2i (%coord (lit ptr) (lit ->int)))
(def %i2p (%coord (lit int) (lit ->ptr)))
(def %p2o (%coord (lit ptr) (lit ->obj)))
(def %p (pair 5 6))
(%ok (same? (%p2o (%i2p (%p2i (%o2p %p)))) %p))
```
---
    *** ERROR: ok
