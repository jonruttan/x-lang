## vector basics

### vector constructor

```scheme
(vector 1 2 3)
```
---
    #(1 2 3)

### vector? on vector

```scheme
(vector? (vector 1 2))
```
---
    t

### vector? on list

```scheme
(null? (vector? (list 1 2)))
```
---
    t

### vector? on number

```scheme
(null? (vector? 42))
```
---
    t

### vector empty

```scheme
(vector)
```
---
    #()

## vector access

### vector-ref first

```scheme
(vector-ref (vector 10 20 30) 0)
```
---
    10

### vector-ref middle

```scheme
(vector-ref (vector 10 20 30) 1)
```
---
    20

### vector-ref last

```scheme
(vector-ref (vector 10 20 30) 2)
```
---
    30

### vector-length three

```scheme
(vector-length (vector 1 2 3))
```
---
    3

### vector-length empty

```scheme
(vector-length (vector))
```
---
    0

### vector-length one

```scheme
(vector-length (vector 42))
```
---
    1

## make-vector

### make-vector with fill

```scheme
(vector->list (make-vector 3 0))
```
---
    (0 0 0)

### make-vector with value

```scheme
(vector-ref (make-vector 5 42) 3)
```
---
    42

### make-vector length

```scheme
(vector-length (make-vector 4 0))
```
---
    4

## vector conversion

### vector->list

```scheme
(vector->list (vector 1 2 3))
```
---
    (1 2 3)

### vector->list empty

```scheme
(null? (vector->list (vector)))
```
---
    t

### list->vector

```scheme
(list->vector (list 1 2 3))
```
---
    #(1 2 3)

### list->vector empty

```scheme
(list->vector ())
```
---
    #()

### roundtrip list->vector->list

```scheme
(vector->list (list->vector (list 4 5 6)))
```
---
    (4 5 6)

## vector-copy

### vector-copy basic

```scheme
(vector-copy (vector 1 2 3))
```
---
    #(1 2 3)

### vector-copy is equal

```scheme
(equal? (vector->list (vector-copy (vector 1 2))) (list 1 2))
```
---
    t

## vector-append

### vector-append two

```scheme
(vector-append (vector 1 2) (vector 3 4))
```
---
    #(1 2 3 4)

### vector-append empty

```scheme
(vector-append (vector) (vector 1 2))
```
---
    #(1 2)

### vector-append nested

```scheme
(vector-append (vector 1) (vector-append (vector 2) (vector 3)))
```
---
    #(1 2 3)

## vector-map

### vector-map double

```scheme
(vector-map (lambda (x) (* x 2)) (vector 1 2 3))
```
---
    #(2 4 6)

### vector-map increment

```scheme
(vector-map (lambda (x) (+ x 10)) (vector 1 2 3))
```
---
    #(11 12 13)

## vector-for-each

### vector-for-each accumulates

```scheme
(define sum 0) (vector-for-each (lambda (x) (set! sum (+ sum x))) (vector 1 2 3)) sum
```
---
    6

