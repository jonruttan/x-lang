## define

### defines a variable

```scheme
(define x 42) x
```
---
    42

### defines a function

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

### redefines top-level variable

```scheme
(define x 1) (define x 2) x
```
---
    2

### defines with expression body

```scheme
(define x (+ 1 2)) x
```
---
    3

### interior define in lambda body

```scheme
((lambda () (define x 42) x))
```
---
    42

### interior define does not leak

```scheme
(define x 1) ((lambda () (define x 99) x)) x
```
---
    1

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

### lambda with multiple body forms

```scheme
((lambda (x) (+ x 1) (+ x 2)) 10)
```
---
    12

### lambda with no args

```scheme
((lambda () 42))
```
---
    42

### nested lambda (currying)

```scheme
(((lambda (x) (lambda (y) (+ x y))) 3) 4)
```
---
    7

### lambda as value in list

```scheme
(define fs (list (lambda (x) (+ x 1)) (lambda (x) (* x 2)))) ((car fs) 5)
```
---
    6

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

### begin with side effects

```scheme
(define x 0) (begin (set! x 1) (set! x 2) x)
```
---
    2

## set!

### mutates binding

```scheme
(define x 10) (set! x 20) x
```
---
    20

### set! in nested scope

```scheme
(define x 10) (let ((y 0)) (set! x 20)) x
```
---
    20

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

## quote shorthand

### quote symbol

```scheme
(write 'a)
```
---
    a

### quote list

```scheme
(write '(1 2 3))
```
---
    (1 2 3)

### quote nil

```scheme
(null? '())
```
---
    #t

### nested quote

```scheme
(write ''a)
```
---
    (lit a)

### quote in list context

```scheme
(write (list 'a 'b))
```
---
    (a b)


