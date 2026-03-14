## meta: obj-meta-extra primitives

### obj-meta-extra defaults to 0

```scheme
(display (obj-meta-extra))
```
---
    0

### obj-meta-ref on non-extended object returns 0

```scheme
(do
  (def %p (pair 1 2))
  (display (obj-meta-ref %p 0)))
```
---
    0

## meta: extended object metadata

### obj-meta-extra! sets and returns old value

```scheme
(do
  (def %old (obj-meta-extra! 3))
  (display %old)
  (display " ")
  (display (obj-meta-extra)))
```
---
    0 3

### obj-meta-set! and obj-meta-ref round-trip

```scheme
(do
  (obj-meta-extra! 3)
  (def %p (pair 1 2))
  (obj-meta-set! %p 0 42)
  (display (obj-meta-ref %p 0)))
```
---
    42

### multiple extra slots work

```scheme
(do
  (obj-meta-extra! 3)
  (def %p (pair 1 2))
  (obj-meta-set! %p 0 10)
  (obj-meta-set! %p 1 20)
  (obj-meta-set! %p 2 30)
  (display (obj-meta-ref %p 0))
  (display " ")
  (display (obj-meta-ref %p 1))
  (display " ")
  (display (obj-meta-ref %p 2)))
```
---
    10 20 30

### extended object survives GC

```scheme
(do
  (obj-meta-extra! 3)
  (def %p (pair 1 2))
  (obj-meta-set! %p 0 99)
  ; Force allocations to trigger GC
  (def %junk (map (fn (x) (pair x x)) (list 1 2 3 4 5 6 7 8 9 10)))
  (display (obj-meta-ref %p 0)))
```
---
    99
