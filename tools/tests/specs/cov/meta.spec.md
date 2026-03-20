## meta: obj-meta-count primitives

### obj-meta-count defaults to 0

```scheme
(display (obj-meta-count))
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

### obj-meta-count! sets and returns old value

```scheme
(do
  (def %old (obj-meta-count! 3))
  (display %old)
  (display " ")
  (display (obj-meta-count)))
```
---
    0 3

### obj-meta-set! and obj-meta-ref round-trip

```scheme
(do
  (obj-meta-count! 3)
  (def %p (pair 1 2))
  (obj-meta-set! %p 0 42)
  (display (obj-meta-ref %p 0)))
```
---
    42

### multiple extra slots work

```scheme
(do
  (obj-meta-count! 3)
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
  (obj-meta-count! 3)
  (def %p (pair 1 2))
  (obj-meta-set! %p 0 99)
  ; Force allocations to trigger GC
  (def %junk (map (fn (x) (pair x x)) (list 1 2 3 4 5 6 7 8 9 10)))
  (display (obj-meta-ref %p 0)))
```
---
    99

## meta: tokenizer line stamping

### token-read-string stamps line 1 on first token

```scheme
(do
  (obj-meta-count! 3)
  (def %tokens (token-read-string (%base) "(+ 1 2)\n"))
  (display (obj-meta-ref (first %tokens) 0)))
```
---
    1

### tokens on different lines get correct line numbers

```scheme
(do
  (obj-meta-count! 3)
  (def %tokens (token-read-string (%base) "(+ 1 2)\n(- 3 4)\n"))
  (display (obj-meta-ref (first %tokens) 0))
  (display " ")
  (display (obj-meta-ref (first (rest %tokens)) 0)))
```
---
    1 2

### nested form elements get correct line numbers

```scheme
(do
  (obj-meta-count! 3)
  (def %tokens (token-read-string (%base) "(if t\n  1\n  2)\n"))
  (def %form (first %tokens))
  (def %then (first (rest (rest %form))))
  (def %else (first (rest (rest (rest %form)))))
  (display (obj-meta-ref %form 0))
  (display " ")
  (display (obj-meta-ref %then 0))
  (display " ")
  (display (obj-meta-ref %else 0)))
```
---
    1 2 3
