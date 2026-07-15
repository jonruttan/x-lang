# @lib ../tests/x/lib/obj-layout.x

# The object-layout contract, runtime half

`tools/obj-layout.x` commits the header-word layout of every object; the
reflective accessors read their offsets from it. These tests probe LIVE
objects word by word (`%obj->ptr` + `%ptr-ref-word`) and fail if the running
build's layout disagrees with the descriptor. The source half
(`make check-obj-layout`) diffs the same values against x-obj.h.  The
instruments (`%word`, `%flags`, the catalog fetches) live in the harness
(`tests/x/lib/obj-layout.x`), fetched once per batch.

## data words

### a pair's first and rest live at the descriptor's data slots

```scheme
(do
  (def p (pair 1 2))
  (display (eq? (%word p (+ %obj-meta-len %obj-slot-first))
                (%ptr->int (%obj->ptr (first p))))) (display " ")
  (display (eq? (%word p (+ %obj-meta-len %obj-slot-rest))
                (%ptr->int (%obj->ptr (rest p))))))
```
---
```output
#t #t
```

### an atom's value is the data word at meta-len

```scheme
(%ptr-ref-word (%obj->ptr 42) (* %obj-meta-len %word-size))
```
---
    42

## header words

### the type slot: equal within a type, distinct across types

```scheme
(do
  (display (eq? (%word (pair 1 2) %obj-slot-type)
                (%word (pair 3 4) %obj-slot-type))) (display " ")
  (display (eq? (%word (pair 1 2) %obj-slot-type)
                (%word 42 %obj-slot-type))))
```
---
```output
#t #f
```

### the flags slot: alike within a type, differing int vs str

Note: the simple-type code (%obj-flag-int etc.) is an ADVISORY tag -- C sets
it where it needs it (e.g. FFI-created atoms), and plain heap ints carry no
code. The contract probed here is the flags slot's POSITION and that it
holds per-object attribute bits (str atoms own their storage; ints don't).

```scheme
(do
  (display (eq? (%flags 7) (%flags 9))) (display " ")
  (display (eq? (%flags 7) (%flags "seven"))))
```
---
```output
#t #f
```

## materialization

### ptr->obj round-trips a data word back to the object it addresses

```scheme
(do
  (def p (pair 7 8))
  (display (eq? (%ptr->obj (%int->ptr
                  (%ptr-ref-word (%obj->ptr p) (* %obj-meta-len %word-size))))
                (first p))) (display " ")
  (display ((prim-ref (lit obj) (lit ref)) p 1)))
```
---
```output
#t 8
```

## folklore reconciliation

### boot/data.x's %data-offset equals the descriptor's meta-len

data.x predates the descriptor and hardcodes the data offset; until it
consumes the descriptor (a boot-order change), this pins the two together.

```scheme
(eq? %data-offset (* %obj-meta-len %word-size))
```
---
    #t

## extended metadata

### meta words are PREPENDED: unit I at word -(I+1), and flag-meta is set

The ambient meta-count is saved and RESTORED (boot arms 1 slot for
source-line tracking; leaving it at a test value would strip line meta
from every object a later block allocates -- see base-paths.spec.md).

```scheme
(do
  (def %mc-prev (%meta-count! 1))
  (def o (pair 5 6))
  (%meta-count! %mc-prev)
  (%meta-set! o 0 42)
  (display (%meta-ref o 0)) (display " ")
  (display (%ptr-ref-word (%obj->ptr o) (- 0 %word-size))) (display " ")
  (display (eq? (& (%ptr-ref-word (%obj->ptr o) (* %obj-slot-flags %word-size))
                   %obj-flag-meta)
                %obj-flag-meta)))
```
---
```output
42 42 #t
```
