## promise basics

### delay creates promise

```scheme
(promise? (delay 42))
```
---
    t

### promise? on non-promise

```scheme
(null? (promise? 42))
```
---
    t

### promise? on list

```scheme
(null? (promise? (list 1 2)))
```
---
    t

## force

### force simple value

```scheme
(force (delay 42))
```
---
    42

### force expression

```scheme
(force (delay (+ 1 2)))
```
---
    3

### force non-promise

```scheme
(force 42)
```
---
    42

### force twice same result

```scheme
(define p (delay (* 6 7))) (list (force p) (force p))
```
---
    (42 42)

## promise memoization

### delay memoizes result

```scheme
(define count 0) (define p (delay (begin (set! count (+ count 1)) count))) (force p) (force p) count
```
---
    1

### side effect runs once

```scheme
(define n 0) (define p (delay (begin (set! n (+ n 10)) n))) (force p) (force p) (force p) n
```
---
    10

## make-promise

### make-promise wraps value

```scheme
(force (make-promise 42))
```
---
    42

### make-promise is idempotent on promise

```scheme
(define p (delay 99)) (eq? (make-promise p) p)
```
---
    t

### make-promise result forceable

```scheme
(force (make-promise (+ 10 20)))
```
---
    30

