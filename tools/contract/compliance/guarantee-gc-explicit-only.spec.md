# Compliance: `(guarantee gc/explicit-only)`

Allocation NEVER collects; only an explicit call does. Six library sites hold a raw
pointer as an integer across an allocating expression on exactly this promise:
`reflect.x:11-12` and `:246`, `boot/string.x:38` and `:53`,
`protocol/str/str8.x:174`, `reader/lit-reader.x:76`. An engine that collected on
allocation would break all six without a word -- the failure this whole gate exists
for, because it is silent.

The object below is referenced only through a raw integer across the churn, so an
engine that collected during allocation would have freed it before it is read back.

### a raw pointer held across allocation still addresses live data

```x
(def %o2p (%coord (lit obj) (lit ->ptr)))
(def %p2i (%coord (lit ptr) (lit ->int)))
(def %i2p (%coord (lit int) (lit ->ptr)))
(def %p2o (%coord (lit ptr) (lit ->obj)))
(def %p (pair 7 8))
(def %i0 (%p2i (%o2p %p)))
(%burn 50000 ())
(%ok (= (first (%p2o (%i2p %i0))) 7))
```
---
    *** ERROR: ok
