# Compliance: `(guarantee gc/non-moving)`

A live object's address is stable for its lifetime. x-lang's reflective accessors
take an address, then allocate (every argument spine does), then use the address --
so an engine that relocated a live object would corrupt `lib/x/boot/reflect.x`
silently, with no error and no crash at the point of damage.

### an address survives heavy allocation

```scheme
(def %o2p (%coord (lit obj) (lit ->ptr)))
(def %p2i (%coord (lit ptr) (lit ->int)))
(def %p (pair 1 2))
(def %a0 (%p2i (%o2p %p)))
(%burn 50000 ())
(%ok (= %a0 (%p2i (%o2p %p))))
```
---
    *** ERROR: ok
