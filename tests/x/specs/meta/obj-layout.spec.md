# @lib ../tests/x/lib/obj-layout.x

# The object-layout contract, runtime half

`tools/obj-layout.x` commits the header-word layout of every object; the
reflective accessors read their offsets from it. These tests probe LIVE
objects word by word (`%obj->ptr` + `%ptr-ref-word`) and fail if the running
build's layout disagrees with the descriptor. The source half
(`make check-obj-layout`) diffs the same values against x-obj.h.

## data words

### a pair's first and rest live at the descriptor's data slots

```scheme
(do
  (def %obj->ptr (prim-ref (lit obj) (lit ->ptr)))
  (def %ptr-ref-word (prim-ref (lit ptr) (lit ref-word)))
  (def %ptr->int (prim-ref (lit ptr) (lit ->int)))
  (def %word (fn (_ o slot) (%ptr-ref-word (%obj->ptr o) (* slot %word-size))))
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
(do
  (def %obj->ptr (prim-ref (lit obj) (lit ->ptr)))
  (def %ptr-ref-word (prim-ref (lit ptr) (lit ref-word)))
  (display (%ptr-ref-word (%obj->ptr 42) (* %obj-meta-len %word-size))))
```
---
```output
42
```

## header words

### the type slot: equal within a type, distinct across types

```scheme
(do
  (def %obj->ptr (prim-ref (lit obj) (lit ->ptr)))
  (def %ptr-ref-word (prim-ref (lit ptr) (lit ref-word)))
  (def %word (fn (_ o slot) (%ptr-ref-word (%obj->ptr o) (* slot %word-size))))
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
  (def %obj->ptr (prim-ref (lit obj) (lit ->ptr)))
  (def %ptr-ref-word (prim-ref (lit ptr) (lit ref-word)))
  (def %flags (fn (_ o) (& (%ptr-ref-word (%obj->ptr o) (* %obj-slot-flags %word-size))
                           (+ %obj-flag-type-mask %obj-flag-attr-mask))))
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
  (def %obj->ptr (prim-ref (lit obj) (lit ->ptr)))
  (def %ptr->obj (prim-ref (lit ptr) (lit ->obj)))
  (def %ptr-ref-word (prim-ref (lit ptr) (lit ref-word)))
  (def %int->ptr (prim-ref (lit int) (lit ->ptr)))
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

```scheme
(do
  (def %obj->ptr (prim-ref (lit obj) (lit ->ptr)))
  (def %ptr-ref-word (prim-ref (lit ptr) (lit ref-word)))
  (def %meta-count! (prim-ref (lit obj) (lit meta-count!)))
  (def %meta-set! (prim-ref (lit obj) (lit meta-set!)))
  (def %meta-ref (prim-ref (lit obj) (lit meta-ref)))
  (%meta-count! 1)
  (def o (pair 5 6))
  (%meta-count! 0)
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
