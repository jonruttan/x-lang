# @lib ../tests/x/lib/obj-layout.x
# @weight 1

# The object-layout contract, runtime half

`engine/tools/contract/obj-layout.x` commits the header-word layout of every object; the
reflective accessors read their offsets from it. These tests probe LIVE
objects word by word (`%obj->ptr` + `%ptr-ref-word`) and fail if the running
build's layout disagrees with the descriptor. The source half
(`make check-obj-layout`) diffs the same values against x-obj.h.  The
instruments (`%word`, `%flags`, the catalog fetches) live in the harness
(`tests/x/lib/obj-layout.x`), fetched once per batch.

## data words

### a pair's first and rest live at the descriptor's data slots

```x
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

```x
(%ptr-ref-word (%obj->ptr 42) (* %obj-meta-len %word-size))
```
---
    42

### a pair-slot write computes no offset

The first and rest offsets are computed once, at load, so `%set-first!` and
`%set-rest!` cost their own frame over the word write itself: fewer than 20
objects a call.

```x
(def %cost
  (fn (_ f)
    (f)
    (def c0 (Heap count))
    ((fn (loop i) (if (= i 0) () (do (f) (loop (- i 1))))) 100)
    (- (Heap count) c0)))
(def %p (pair 1 2))
(def %off (%data-word-off 1))
(def %raw
  (%cost (fn (_) (%ptr-set-word! (%obj->ptr %p) %off (%ptr->int (%obj->ptr 4))))))
(list (< (- (%cost (fn (_) (%set-first! %p 3))) %raw) (* 20 100))
      (< (- (%cost (fn (_) (%set-rest! %p 4))) %raw) (* 20 100))
      %p)
```
---
    (#t #t (3 . 4))

### the data-word formula runs on the integer doors

`(obj ref)` and `(obj set!)` address data word i through `%data-word-off` on
every call: its frame and two integer operations, fewer than 16 objects a call
over one integer add.

```x
(def %cost
  (fn (_ f)
    (f)
    (def c0 (Heap count))
    ((fn (loop i) (if (= i 0) () (do (f) (loop (- i 1))))) 100)
    (- (Heap count) c0)))
(def %add (prim-ref (lit int) (lit +)))
(list (< (- (%cost (fn (_) (%data-word-off 1))) (%cost (fn (_) (%add 1 2)))) (* 16 100))
      (eq? (%data-word-off 1) (* (+ %obj-meta-len 1) %word-size)))
```
---
    (#t #t)

## header words

### the type slot: equal within a type, distinct across types

```x
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

The contract probed here is the flags slot's POSITION and that it holds
per-object attribute bits (str atoms own their storage; ints don't).

```x
(do
  (display (eq? (%flags 7) (%flags 9))) (display " ")
  (display (eq? (%flags 7) (%flags "seven"))))
```
---
```output
#t #f
```

## materialization

(No folklore-reconciliation block anymore: boot/data.x consumes the
descriptor directly -- `%data-offset` is `(* %word-size %obj-meta-len)` --
since e62ac80, so pinning the two together would be a tautology.)

### ptr->obj round-trips a data word back to the object it addresses

```x
(do
  (def p (pair 7 8))
  (display (eq? (%ptr->obj (%int->ptr
                  (%ptr-ref-word (%obj->ptr p) (* %obj-meta-len %word-size))))
                (first p))) (display " ")
  (display ((prim-ref 'obj 'ref) p 1)))
```
---
```output
#t 8
```

## extended metadata

### meta words are PREPENDED: unit I at word -(I+1), and flag-meta is set

The AMBIENT width is used, never changed: boot arms 2 slots (source line
+ file id), so a fresh pair already carries the prefix this block probes.
The old form set the width to 1 and restored -- and the pair it allocated
in between was born at the divergent width, a landmine the next mid-batch
collect freed at the wrong address (the x-engine-c#21 ruling: the width
is boot-time policy; changing it over a live heap is undefined).

```x
(do
  (def o (pair 5 6))
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
