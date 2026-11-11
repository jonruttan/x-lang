# Image walk: the mark and its clear
# @weight 1
# @no-seam-collect

`image-mark!` flags every object reachable from a root, and the flag is the
walk's visited test. `image-clear!` takes the flag back, from the allocation
chain and from the base object, which no chain holds.

## image-clear!

### the base object carries no flag after a clear

```x
(import x/tool/image/walk image-mark! image-clear! image-trace-flag)
(do
  (def set? (fn (_ o) (if (eq? (& (%reflect-flags o) image-trace-flag) 0) #f #t)))
  (image-mark! (%base) image-trace-flag)
  (def during (set? (%base)))
  (image-clear! image-trace-flag)
  (list during (set? (%base))))
```
---
    (#t #f)

### a second mark from the base reaches what the first did, and what came after

```x
(import x/tool/image/walk image-mark! image-clear! image-trace-flag)
(do
  (def set? (fn (_ o) (if (eq? (& (%reflect-flags o) image-trace-flag) 0) #f #t)))
  (def one (pair 'first ()))
  (image-mark! (%base) image-trace-flag)
  (def first-mark (set? one))
  (image-clear! image-trace-flag)
  (def between (set? one))
  (def two (pair 'second ()))
  (image-mark! (%base) image-trace-flag)
  (def second-mark (list (set? one) (set? two)))
  (image-clear! image-trace-flag)
  (list first-mark between second-mark (list (set? one) (set? two))))
```
---
    (#t #f (#t #t) (#f #f))

### a clear leaves every other flag bit as it was

```x
(import x/tool/image/walk image-mark! image-clear! image-trace-flag)
(do
  (def before (%reflect-flags (%base)))
  (image-mark! (%base) image-trace-flag)
  (image-clear! image-trace-flag)
  (eq? (%reflect-flags (%base)) before))
```
---
    #t
