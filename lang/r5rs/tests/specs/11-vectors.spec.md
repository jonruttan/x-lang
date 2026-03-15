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
    #t

### vector? on list

```scheme
(not (vector? (list 1 2)))
```
---
    #t

### vector? on non-vector

```scheme
(not (vector? 42))
```
---
    #t

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

### vector-length

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
    #t

### list->vector

```scheme
(list->vector (list 1 2 3))
```
---
    #(1 2 3)

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

