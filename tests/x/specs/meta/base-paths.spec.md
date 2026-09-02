# The base-paths contract, runtime half
# @weight 1

`engine/tools/contract/base-paths.x` commits every base-object field as a first/rest path;
`boot/reflect.x` walks them. These tests prove the LIVE base agrees: cells
reached by walking must be the same objects the C layer serves. The source
half (`make check-base-paths`) re-derives the paths from the headers.

## walked cells are the C layer's cells

### the prims path lands on the catalog cell

```x
(eq? (first (%reflect-base-cell 'prims)) (prims))
```
---
    #t

### the true/false paths land on the boolean singletons

```x
(do
  (display (eq? (first (%reflect-base-cell 'true)) #t)) (display " ")
  (display (eq? (first (%reflect-base-cell 'false)) #f)))
```
---
```output
#t #t
```

## migrated accessors

### meta-count! round-trips through the policy cell

The write NEVER DIVERGES the width: it sets the value the cell already
holds, which still exercises the C contract (the setter answers the
PREVIOUS count).  Setting a DIFFERENT width over a live heap is undefined
-- every object born at another width is freed at the wrong address by
the next collect (the x-engine-c#21 ruling: the engine core is not privy
to the metadata, so the width is boot-time policy, not a runtime knob).
The old form of this test set 3 and restored, and the objects it
allocated in between were exactly such landmines: they aborted the
process at the first mid-batch collect, 40 specs at a stroke.

```x
(do
  (def %mc  (prim-ref 'obj 'meta-count))
  (def %mc! (prim-ref 'obj 'meta-count!))
  (def %ambient (%mc))
  (display (eq? (%mc! %ambient) %ambient)) (display " ")
  (display (eq? (%mc) %ambient)) (display " ")
  (display %ambient))
```
---
```output
#t #t 2
```

### error-line reads the frozen raise-site line as an integer

The contract pinned here: (io error-line) reads the err-line snapshot the
raise path freezes (reflect.x), so it yields a non-negative integer outside
a handler (the most recent error's line -- boot catches some, so rarely 0)
and, from within a handler, the actual raise-site line without raising.
Unlike the old handler-slot walk this survives the handler pop the guard
does before its body runs.

```x
(do
  (def %el (prim-ref 'io 'error-line))
  (display (>= (%el) 0)) (display " ")
  (display (number? (guard (e (%el)) (error "boom")))))
```
---
```output
#t #t
```
