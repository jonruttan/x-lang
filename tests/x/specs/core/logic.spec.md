# @weight 1
## and

### returns #t for empty and

```x
(and)
```
---
    #t

### returns value for single truthy

```x
(and 1)
```
---
    1

### returns nil for single falsy

```x
(and (lit ()))
```
---

### returns last value when all truthy

```x
(and 1 2 3)
```
---
    3

### returns #f on first falsy

```x
(and 1 (lit ()) 3)
```
---
    #f

### returns actual value not t

```x
(and 1 "yes")
```
---
    "yes"

### short-circuits evaluation

```x
(do (def x 0) (and (lit ()) (set! x 1)) x)
```
---
    0

### short-circuits before error

```x
(and (lit ()) (error "boom"))
```
---
    #f

### and with nested function calls

```x
(let ((x 5)) (and (> x 3) (< x 10)))
```
---
    #t

## or

### returns nil for empty or

```x
(or)
```
---

### returns value for single truthy

```x
(or 1)
```
---
    1

### returns nil for single falsy

```x
(or (lit ()))
```
---

### returns first truthy value

```x
(or (lit ()) 2 3)
```
---
    2

### returns nil when all falsy

```x
(or (lit ()) (lit ()))
```
---

### returns actual value not t

```x
(or (lit ()) "yes")
```
---
    "yes"

### short-circuits evaluation

```x
(do (def x 0) (or 1 (set! x 1)) x)
```
---
    0

### short-circuits before error

```x
(or 1 (error "boom"))
```
---
    1

### or with nested function calls

```x
(let ((x 5)) (or (< x 0) (> x 3)))
```
---
    #t

## not

### returns #t for nil

```x
(not (lit ()))
```
---
    #t

### returns #f for non-nil

```x
(not 1)
```
---
    #f

## nested and/or

### nested and/or returns correct value

```x
(and (or (lit ()) 1) (or (lit ()) 2))
```
---
    2

### or of ands returns correct value

```x
(or (and (lit ()) 1) (and 1 2))
```
---
    2

### and of ors returns correct value

```x
(and (or 1 2) (or 3 4))
```
---
    3

### deeply nested logic

```x
(or (and (or (lit ()) (lit ())) 1) (and (or (lit ()) 5) 6))
```
---
    6

## guard

### returns body result when no error

```x
(guard (e 'caught) (+ 1 2))
```
---
    3

### catches explicit error

```x
(guard (e e) (error "boom"))
```
---
    "boom"

### runs handler body on error

```x
(guard (e (list 'caught e)) (error "oops"))
```
---
    ('caught "oops")

### catches unbound symbol

```x
(guard (e 'handled) no-such-var)
```
---
    'handled

### returns last body form

```x
(guard (e e) 1 2 3)
```
---
    3

### handler sees error value

```x
(guard (e (list 'err e)) (error 42))
```
---
    ('err 42)

### a handler-body re-raise propagates to the ENCLOSING guard

The guard pops its handler BEFORE the handler body runs (control.c), so
(error e) inside a handler reaches the outer guard -- the docs/spec.md
propagation idiom.  (Regression pin: the handler used to stay installed,
and a re-raise longjmp'd back into its own guard forever.)

```x
(guard (e2 (Str8 append "outer: " e2))
  (guard (e (error (Str8 append "re: " e)))
    (error "inner")))
```
---
    "outer: re: inner"

### a handler-body re-raise with NO outer guard leaves the handler popped

```x
(do
  (def %r1 (guard (e2 'outer) (guard (e (error e)) (error 'boom))))
  (def %r2 (guard (e3 'clean) (+ 1 2)))
  (list %r1 %r2))
```
---
    ('outer 3)

## error

### signals with string

```x
(guard (e e) (error "test"))
```
---
    "test"

### signals with number

```x
(guard (e e) (error 99))
```
---
    99

### signals from nested call

```x
(do (def boom (fn (_ ) (error "inner"))) (guard (e e) (boom)))
```
---
    "inner"

## nested guard

### inner guard catches inner error

```x
(guard (e 'outer) (guard (e 'inner) (error "x")))
```
---
    'inner

### outer guard catches when inner has no guard

```x
(guard (e (list 'outer e)) (do (def f (fn (_ ) (error "deep"))) (f)))
```
---
    ('outer "deep")

### inner guard does not catch outer body error

```x
(guard (e (list 'caught e)) (+ 1 2) (error "after"))
```
---
    ('caught "after")

## guard with env restore

### restores env after error in let

```x
(do (def x 10) (guard (e x) (let ((x 20)) (error "err"))))
```
---
    10

### restores env after error in fn

```x
(do (def x 5) (guard (e x) ((fn (_ ) (error "err")))))
```
---
    5

