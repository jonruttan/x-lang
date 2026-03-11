## define

### defines a variable

```scheme
(define x 42) x
```
---
    42

### defines a function with sugar

```scheme
(define (square x) (* x x)) (square 5)
```
---
    25

### defines multi-body function

```scheme
(define (f x) (+ x 1) (+ x 2)) (f 10)
```
---
    12

### defines recursive function

```scheme
(define (fact n) (if (= n 0) 1 (* n (fact (- n 1))))) (fact 5)
```
---
    120

## lambda

### creates anonymous function

```scheme
((lambda (x) (* x x)) 4)
```
---
    16

### lambda is fn alias

```scheme
(define f (lambda (x y) (+ x y))) (f 3 4)
```
---
    7

## begin

### sequences expressions

```scheme
(begin 1 2 3)
```
---
    3

### begin is do alias

```scheme
(begin (define x 10) (+ x 5))
```
---
    15

## set!

### mutates binding

```scheme
(define x 10) (set! x 20) x
```
---
    20

## cons/car/cdr

### cons builds a pair

```scheme
(cons 1 2)
```
---
    (1 . 2)

### car returns first element

```scheme
(car (cons 1 2))
```
---
    1

### cdr returns rest element

```scheme
(cdr (cons 1 2))
```
---
    2

### cons builds a list

```scheme
(cons 1 (cons 2 (cons 3 ())))
```
---
    (1 2 3)

### car of list

```scheme
(car (list 1 2 3))
```
---
    1

### cdr of list

```scheme
(cdr (list 1 2 3))
```
---
    (2 3)

## boolean constants

### #t is truthy

```scheme
(if #t 1 2)
```
---
    1

### #f is falsy

```scheme
(if #f 1 2)
```
---
    2

## composition accessors

### caar

```scheme
(caar (list (list 1 2) (list 3 4)))
```
---
    1

### cadr

```scheme
(cadr (list 1 2 3))
```
---
    2

### cdar

```scheme
(cdar (list (list 1 2) 3))
```
---
    (2)

### cddr

```scheme
(cddr (list 1 2 3))
```
---
    (3)

### caddr

```scheme
(caddr (list 1 2 3))
```
---
    3

## convenience aliases

### first returns car

```scheme
(first (list 10 20 30))
```
---
    10

### second returns cadr

```scheme
(second (list 10 20 30))
```
---
    20

### third returns caddr

```scheme
(third (list 10 20 30))
```
---
    30

### rest returns cdr

```scheme
(rest (list 10 20 30))
```
---
    (20 30)

### modulo alias

```scheme
(modulo 10 3)
```
---
    1

## I/O constants

### stdin is 0

```scheme
stdin
```
---
    0

### stdout is 1

```scheme
stdout
```
---
    1

### stderr is 2

```scheme
stderr
```
---
    2

