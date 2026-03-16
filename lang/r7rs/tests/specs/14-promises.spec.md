## promise basics

### delay creates promise

```scheme
(promise? (delay 42))
```
---
    #t

### promise? on non-promise

```scheme
(not (promise? 42))
```
---
    #t

### promise? on list

```scheme
(not (promise? (list 1 2)))
```
---
    #t

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
    #t

### make-promise result forceable

```scheme
(force (make-promise (+ 10 20)))
```
---
    30

## delay-force

### delay-force creates promise

```scheme
(promise? (delay-force (delay 42)))
```
---
    #t

### delay-force basic

```scheme
(force (delay-force (delay 42)))
```
---
    42

### delay-force chains

```scheme
(force (delay-force (delay-force (delay 99))))
```
---
    99

### delay-force with expression

```scheme
(force (delay-force (make-promise (+ 3 4))))
```
---
    7

### delay-force memoizes

```scheme
(define count 0)
(define p (delay-force (begin (set! count (+ count 1)) (make-promise count))))
(force p) (force p) count
```
---
    1

