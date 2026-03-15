## identity

### returns its argument

```scheme
(identity 42)
```
---
    42

### returns a list

```scheme
(identity (list 1 2))
```
---
    (1 2)

## const

### returns a function that ignores its argument

```scheme
((const 5) 99)
```
---
    5

### works with symbols

```scheme
((const (quote hello)) 0)
```
---
    hello

## compose

### composes two functions

```scheme
(define (double x) (* x 2)) (define (inc x) (+ x 1)) ((compose double inc) 3)
```
---
    8

### applies right function first

```scheme
((compose (lambda (x) (+ x 10)) (lambda (x) (* x 2))) 5)
```
---
    20

## curry

### partially applies a function

```scheme
(define (add a b) (+ a b)) (define add5 (curry add 5)) (add5 3)
```
---
    8

### works with built-in operators

```scheme
(define mul (curry * 10)) (mul 7)
```
---
    70

## fold

### left-folds a list

```scheme
(fold + 0 (list 1 2 3 4))
```
---
    10

### accumulates from the left

```scheme
(fold - 10 (list 1 2 3))
```
---
    4

### returns init for empty list

```scheme
(fold + 0 ())
```
---
    0

## reduce

### reduces a list with no init

```scheme
(reduce + (list 1 2 3 4))
```
---
    10

### works with subtraction

```scheme
(reduce - (list 10 3 2))
```
---
    5

## range

### generates a range

```scheme
(range 0 5)
```
---
    (0 1 2 3 4)

### returns empty for start >= end

```scheme
(null? (range 5 5))
```
---
    #t

### works with non-zero start

```scheme
(range 3 6)
```
---
    (3 4 5)

## zip

### pairs elements from two lists

```scheme
(zip (list 1 2 3) (list 4 5 6))
```
---
    ((1 4) (2 5) (3 6))

### stops at shorter list

```scheme
(zip (list 1 2) (list 3))
```
---
    ((1 3))

### returns empty for empty input

```scheme
(null? (zip () (list 1)))
```
---
    #t

## any?

### returns t when predicate matches

```scheme
(any? (lambda (x) (> x 3)) (list 1 2 3 4 5))
```
---
    #t

### returns nil when none match

```scheme
(not (any? (lambda (x) (> x 10)) (list 1 2 3)))
```
---
    #t

### returns nil for empty list

```scheme
(not (any? (lambda (x) t) ()))
```
---
    #t

## every?

### returns t when all match

```scheme
(every? (lambda (x) (> x 0)) (list 1 2 3))
```
---
    #t

### returns nil when one fails

```scheme
(not (every? (lambda (x) (> x 2)) (list 1 2 3)))
```
---
    #t

### returns t for empty list

```scheme
(every? (lambda (x) (> x 0)) ())
```
---
    #t

