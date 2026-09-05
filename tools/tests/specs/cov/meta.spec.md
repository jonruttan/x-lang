# @no-seam-collect
<!-- This file TESTS the divergent-width mechanism: it arms meta-count
     values the live base never has, which the x-engine-c#21 ruling makes
     undefined to collect over (objects born at another width are freed at
     the wrong address).  The directive suppresses the runner's seam
     collects and makes the file run alone, restoring the exact regime it
     always passed under.  Everything else should NOT copy this: test
     against the ambient width instead (see meta/base-paths.spec.md). -->

## meta: obj-meta-count primitives

### obj-meta-count defaults to 2 (source-location line/file slots)

```x
; Boot reserves meta slots 0/1 for raise-time line/file stamping
; (lib/x/boot/ + docs: source-location errors), so a base that has
; loaded x-core reports 2, not 0.
(display (Obj meta-count))
```
---
    2

### obj-meta-ref on non-extended object returns 0

```x
(do
  (def %p (pair 1 2))
  (display (Obj meta-ref %p 0)))
```
---
    0

## meta: extended object metadata

### obj-meta-count! sets and returns old value

```x
; The old value is 2: the source-location slots x-core booted with.
(do
  (def %old (Obj meta-count! 3))
  (display %old)
  (display " ")
  (display (Obj meta-count)))
```
---
    2 3

### obj-meta-set! and obj-meta-ref round-trip

```x
(do
  (Obj meta-count! 3)
  (def %p (pair 1 2))
  (Obj meta-set! %p 0 42)
  (display (Obj meta-ref %p 0)))
```
---
    42

### multiple extra slots work

```x
(do
  (Obj meta-count! 3)
  (def %p (pair 1 2))
  (Obj meta-set! %p 0 10)
  (Obj meta-set! %p 1 20)
  (Obj meta-set! %p 2 30)
  (display (Obj meta-ref %p 0))
  (display " ")
  (display (Obj meta-ref %p 1))
  (display " ")
  (display (Obj meta-ref %p 2)))
```
---
    10 20 30

### extended object survives GC

```x
(do
  (Obj meta-count! 3)
  (def %p (pair 1 2))
  (Obj meta-set! %p 0 99)
  ; Force allocations to trigger GC
  (def %junk (%map (fn (x) (pair x x)) (list 1 2 3 4 5 6 7 8 9 10)))
  (display (Obj meta-ref %p 0)))
```
---
    99

## meta: tokenizer line stamping

### token-read-string stamps line 1 on first token

```x
(do
  (Obj meta-count! 3)
  (def %tokens (Tok read-str (%base) "(+ 1 2)\n"))
  (display (Obj meta-ref (first %tokens) 0)))
```
---
    1

### tokens on different lines get correct line numbers

```x
(do
  (Obj meta-count! 3)
  (def %tokens (Tok read-str (%base) "(+ 1 2)\n(- 3 4)\n"))
  (display (Obj meta-ref (first %tokens) 0))
  (display " ")
  (display (Obj meta-ref (first (rest %tokens)) 0)))
```
---
    1 2

### nested form elements get correct line numbers

```x
(do
  (Obj meta-count! 3)
  (def %tokens (Tok read-str (%base) "(if t\n  1\n  2)\n"))
  (def %form (first %tokens))
  (def %then (first (rest (rest %form))))
  (def %else (first (rest (rest (rest %form)))))
  (display (Obj meta-ref %form 0))
  (display " ")
  (display (Obj meta-ref %then 0))
  (display " ")
  (display (Obj meta-ref %else 0)))
```
---
    1 2 3
