## vector

### creates a vector from arguments

```scheme
(write (vector 1 2 3))
```
---
    #(1 2 3)

### creates a single-element vector

```scheme
(write (vector 42))
```
---
    #(42)

### creates an empty vector

```scheme
(write (vector))
```
---
    #()

## vector indexing

### indexes from the start

```scheme
((vector 10 20 30) 1)
```
---
    20

### indexes first element

```scheme
((vector 10 20 30) 0)
```
---
    10

### indexes last element

```scheme
((vector 10 20 30) 2)
```
---
    30

### indexes from the end with negative

```scheme
((vector 10 20 30) -1)
```
---
    30

## vector?

### returns #t for a vector

```scheme
(vector? (vector 1))
```
---
    #t

### returns nil for a list

```scheme
(if (vector? (list 1)) "yes" "no")
```
---
    "no"

### returns nil for an integer

```scheme
(if (vector? 42) "yes" "no")
```
---
    "no"

## vector-ref

### retrieves element by index

```scheme
(vector-ref (vector 10 20 30) 1)
```
---
    20

## vector-length

### returns the length of a vector

```scheme
(vector-length (vector 1 2 3))
```
---
    3

### returns 0 for empty vector

```scheme
(vector-length (vector))
```
---
    0

## vector->list

### converts a vector to a list

```scheme
(vector->list (vector 1 2 3))
```
---
    (1 2 3)

## list->vector

### converts a list to a vector

```scheme
(write (list->vector (list 4 5 6)))
```
---
    #(4 5 6)

## make-vector

### creates a vector of repeated values

```scheme
(write (make-vector 3 0))
```
---
    #(0 0 0)

### creates a vector with custom fill

```scheme
(write (make-vector 2 7))
```
---
    #(7 7)

### creates an empty vector with make-vector

```scheme
(write (make-vector 0 0))
```
---
    #()

### write separates elements with spaces

```scheme
(write (vector 1 2))
```
---
    #(1 2)

