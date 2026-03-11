## procedure?

### procedure? on lambda

```scheme
(procedure? (lambda (x) x))
```
---
    t

### procedure? on builtin

```scheme
(procedure? +)
```
---
    t

### procedure? on number

```scheme
(null? (procedure? 42))
```
---
    t

### procedure? on list

```scheme
(null? (procedure? (list 1 2)))
```
---
    t

### procedure? on symbol

```scheme
(null? (procedure? (quote foo)))
```
---
    t

## apply

### apply with list arg

```scheme
(apply + (list 1 2 3))
```
---
    6

### apply with lambda

```scheme
(apply (lambda (a b c) (+ a b c)) (list 1 2 3))
```
---
    6

### apply with builtin

```scheme
(apply * (list 2 3 4))
```
---
    24

### apply cons

```scheme
(apply cons (list 1 2))
```
---
    (1 . 2)

## map

### map single list

```scheme
(map (lambda (x) (* x x)) (list 1 2 3 4))
```
---
    (1 4 9 16)

### map with car

```scheme
(map car (list (cons 1 2) (cons 3 4) (cons 5 6)))
```
---
    (1 3 5)

### map with lambda

```scheme
(map (lambda (x) (+ x 1)) (list 10 20 30))
```
---
    (11 21 31)

### map on empty

```scheme
(null? (map (lambda (x) x) ()))
```
---
    t

### map preserves order

```scheme
(map car (list (list 1 2) (list 3 4) (list 5 6)))
```
---
    (1 3 5)

## for-each

### for-each visits all elements

```scheme
(define sum 0) (for-each (lambda (x) (set! sum (+ sum x))) (list 1 2 3 4)) sum
```
---
    10

### for-each order

```scheme
(define acc ()) (for-each (lambda (x) (set! acc (cons x acc))) (list 1 2 3)) (reverse acc)
```
---
    (1 2 3)

## higher-order patterns

### compose

```scheme
(define (double x) (* x 2)) (define (inc x) (+ x 1)) (map (compose double inc) (list 1 2 3))
```
---
    (4 6 8)

### filter and map pipeline

```scheme
(map (lambda (x) (* x x)) (filter (lambda (x) (> x 2)) (list 1 2 3 4 5)))
```
---
    (9 16 25)

### closure captures variable

```scheme
(define (make-adder n) (lambda (x) (+ x n))) ((make-adder 5) 10)
```
---
    15

### closure mutation counter

```scheme
(define (make-counter) (define n 0) (lambda () (set! n (+ n 1)) n)) (define c (make-counter)) (c) (c) (c)
```
---
    3

### independent closures

```scheme
(define (make-counter) (define n 0) (lambda () (set! n (+ n 1)) n)) (define a (make-counter)) (define b (make-counter)) (a) (a) (b) (list (a) (b))
```
---
    (3 2)

## tail recursion

### tail-recursive factorial

```scheme
(define (fact n acc) (if (= n 0) acc (fact (- n 1) (* n acc)))) (fact 10 1)
```
---
    3628800

### deep tail recursion

```scheme
(define (loop n) (if (= n 0) (quote done) (loop (- n 1)))) (loop 50000)
```
---
    done

## values

### single value passthrough

```scheme
(call-with-values (lambda () (values 42)) (lambda (x) x))
```
---
    42

### two values

```scheme
(call-with-values (lambda () (values 1 2)) +)
```
---
    3

### three values

```scheme
(call-with-values (lambda () (values 1 2 3)) +)
```
---
    6

### values with computation

```scheme
(call-with-values (lambda () (values (* 2 3) (* 4 5))) +)
```
---
    26

### single value optimization

```scheme
(values 42)
```
---
    42

### call-with-values non-values producer

```scheme
(call-with-values (lambda () 42) (lambda (x) (* x 2)))
```
---
    84

### values with list consumer

```scheme
(call-with-values (lambda () (values 1 2 3)) list)
```
---
    (1 2 3)

### values in let binding

```scheme
(call-with-values (lambda () (values 10 20)) (lambda (a b) (- a b)))
```
---
    -10

