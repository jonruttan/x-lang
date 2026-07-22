## meta: obj-meta-count primitives

### obj-meta-count defaults to 0

```scheme
(display (Obj meta-count))
```
---
    0

### obj-meta-ref on non-extended object returns 0

```scheme
(do
  (def %p (pair 1 2))
  (display (Obj meta-ref %p 0)))
```
---
    0

## meta: extended object metadata

### obj-meta-count! sets and returns old value

```scheme
(do
  (def %old (Obj meta-count! 3))
  (display %old)
  (display " ")
  (display (Obj meta-count)))
```
---
    0 3

### obj-meta-set! and obj-meta-ref round-trip

```scheme
(do
  (Obj meta-count! 3)
  (def %p (pair 1 2))
  (Obj meta-set! %p 0 42)
  (display (Obj meta-ref %p 0)))
```
---
    42

### multiple extra slots work

```scheme
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

```scheme
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

```scheme
(do
  (Obj meta-count! 3)
  (def %tokens (Tok read-str (%base) "(+ 1 2)\n"))
  (display (Obj meta-ref (first %tokens) 0)))
```
---
    1

### tokens on different lines get correct line numbers

```scheme
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

```scheme
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
