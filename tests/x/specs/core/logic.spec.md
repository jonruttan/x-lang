## and

### returns #t for empty and

```scheme
(and)
```
---
    #t

### returns value for single truthy

```scheme
(and 1)
```
---
    1

### returns nil for single falsy

```scheme
(and (lit ()))
```
---

### returns last value when all truthy

```scheme
(and 1 2 3)
```
---
    3

### returns #f on first falsy

```scheme
(and 1 (lit ()) 3)
```
---
    #f

### returns actual value not t

```scheme
(and 1 "yes")
```
---
    "yes"

### short-circuits evaluation

```scheme
(do (def x 0) (and (lit ()) (set! x 1)) x)
```
---
    0

### short-circuits before error

```scheme
(and (lit ()) (error "boom"))
```
---
    #f

### and with nested function calls

```scheme
(let ((x 5)) (and (> x 3) (< x 10)))
```
---
    #t

## or

### returns nil for empty or

```scheme
(or)
```
---

### returns value for single truthy

```scheme
(or 1)
```
---
    1

### returns nil for single falsy

```scheme
(or (lit ()))
```
---

### returns first truthy value

```scheme
(or (lit ()) 2 3)
```
---
    2

### returns nil when all falsy

```scheme
(or (lit ()) (lit ()))
```
---

### returns actual value not t

```scheme
(or (lit ()) "yes")
```
---
    "yes"

### short-circuits evaluation

```scheme
(do (def x 0) (or 1 (set! x 1)) x)
```
---
    0

### short-circuits before error

```scheme
(or 1 (error "boom"))
```
---
    1

### or with nested function calls

```scheme
(let ((x 5)) (or (< x 0) (> x 3)))
```
---
    #t

## not

### returns #t for nil

```scheme
(not (lit ()))
```
---
    #t

### returns #f for non-nil

```scheme
(not 1)
```
---
    #f

## nested and/or

### nested and/or returns correct value

```scheme
(and (or (lit ()) 1) (or (lit ()) 2))
```
---
    2

### or of ands returns correct value

```scheme
(or (and (lit ()) 1) (and 1 2))
```
---
    2

### and of ors returns correct value

```scheme
(and (or 1 2) (or 3 4))
```
---
    3

### deeply nested logic

```scheme
(or (and (or (lit ()) (lit ())) 1) (and (or (lit ()) 5) 6))
```
---
    6

## guard

### returns body result when no error

```scheme
(guard (e 'caught) (+ 1 2))
```
---
    3

### catches explicit error

```scheme
(guard (e e) (error "boom"))
```
---
    "boom"

### runs handler body on error

```scheme
(guard (e (list 'caught e)) (error "oops"))
```
---
    ('caught "oops")

### catches unbound symbol

```scheme
(guard (e 'handled) no-such-var)
```
---
    'handled

### returns last body form

```scheme
(guard (e e) 1 2 3)
```
---
    3

### handler sees error value

```scheme
(guard (e (list 'err e)) (error 42))
```
---
    ('err 42)

### a handler-body re-raise propagates to the ENCLOSING guard

The guard pops its handler BEFORE the handler body runs (control.c), so
(error e) inside a handler reaches the outer guard -- the docs/spec.md
propagation idiom.  (Regression pin: the handler used to stay installed,
and a re-raise longjmp'd back into its own guard forever.)

```scheme
(guard (e2 (Str8 append "outer: " e2))
  (guard (e (error (Str8 append "re: " e)))
    (error "inner")))
```
---
    "outer: re: inner"

### a handler-body re-raise with NO outer guard leaves the handler popped

```scheme
(do
  (def %r1 (guard (e2 'outer) (guard (e (error e)) (error 'boom))))
  (def %r2 (guard (e3 'clean) (+ 1 2)))
  (list %r1 %r2))
```
---
    ('outer 3)

## error

### signals with string

```scheme
(guard (e e) (error "test"))
```
---
    "test"

### signals with number

```scheme
(guard (e e) (error 99))
```
---
    99

### signals from nested call

```scheme
(do (def boom (fn (_ ) (error "inner"))) (guard (e e) (boom)))
```
---
    "inner"

## nested guard

### inner guard catches inner error

```scheme
(guard (e 'outer) (guard (e 'inner) (error "x")))
```
---
    'inner

### outer guard catches when inner has no guard

```scheme
(guard (e (list 'outer e)) (do (def f (fn (_ ) (error "deep"))) (f)))
```
---
    ('outer "deep")

### inner guard does not catch outer body error

```scheme
(guard (e (list 'caught e)) (+ 1 2) (error "after"))
```
---
    ('caught "after")

## guard with env restore

### restores env after error in let

```scheme
(do (def x 10) (guard (e x) (let ((x 20)) (error "err"))))
```
---
    10

### restores env after error in fn

```scheme
(do (def x 5) (guard (e x) ((fn (_ ) (error "err")))))
```
---
    5

