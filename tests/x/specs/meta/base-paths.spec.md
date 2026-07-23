# The base-paths contract, runtime half

`tools/base-paths.x` commits every base-object field as a first/rest path;
`boot/reflect.x` walks them. These tests prove the LIVE base agrees: cells
reached by walking must be the same objects the C layer serves. The source
half (`make check-base-paths`) re-derives the paths from the headers.

## walked cells are the C layer's cells

### the prims path lands on the catalog cell

```scheme
(eq? (first (%reflect-base-cell 'prims)) (prims))
```
---
    #t

### the true/false paths land on the boolean singletons

```scheme
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

The ambient count is NOT assumed (boot arms 2 meta slots: source line +
source file id); the test saves, sets, and restores it.

```scheme
(do
  (def %mc  (prim-ref 'obj 'meta-count))
  (def %mc! (prim-ref 'obj 'meta-count!))
  (def %before (%mc! 3))
  (display (%mc)) (display " ")
  (display (eq? (%mc! %before) 3)) (display " ")
  (display (eq? (%mc) %before)))
```
---
```output
3 #t #t
```

### error-line reads the frozen raise-site line as an integer

The contract pinned here: (io error-line) reads the err-line snapshot the
raise path freezes (reflect.x), so it yields a non-negative integer outside
a handler (the most recent error's line -- boot catches some, so rarely 0)
and, from within a handler, the actual raise-site line without raising.
Unlike the old handler-slot walk this survives the handler pop the guard
does before its body runs.

```scheme
(do
  (def %el (prim-ref 'io 'error-line))
  (display (>= (%el) 0)) (display " ")
  (display (number? (guard (e (%el)) (error "boom")))))
```
---
```output
#t #t
```
