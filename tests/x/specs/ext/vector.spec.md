## vector

### creates a vector from arguments

```scheme
(write (Vector of 1 2 3))
```
---
    #(1 2 3)

### creates a single-element vector

```scheme
(write (Vector of 42))
```
---
    #(42)

### creates an empty vector

```scheme
(write (Vector of))
```
---
    #()

### builds a vector from an index function

```scheme
(write (Vector build 4 (fn (_ i) (* i i))))
```
---
    #(0 1 4 9)

## vector indexing

### indexes from the start

```scheme
((Vector of 10 20 30) 1)
```
---
    20

### indexes first element

```scheme
((Vector of 10 20 30) 0)
```
---
    10

### indexes last element

```scheme
((Vector of 10 20 30) 2)
```
---
    30

### indexes from the end with negative

```scheme
((Vector of 10 20 30) -1)
```
---
    30

## vector?

### returns #t for a vector

```scheme
(Vector vector? (Vector of 1))
```
---
    #t

### returns nil for a list

```scheme
(if (Vector vector? (list 1)) "yes" "no")
```
---
    "no"

### returns nil for an integer

```scheme
(if (Vector vector? 42) "yes" "no")
```
---
    "no"

## vector-ref

### retrieves element by index

```scheme
(Vector ref 1 (Vector of 10 20 30))
```
---
    20

### indexes from the end with negative, matching the call slot

```scheme
(Vector ref -1 (Vector of 10 20 30))
```
---
    30

### errors past the end instead of reading raw memory

```scheme
(Vector ref 5 (Vector of 10 20 30))
```
---
    Error: #<err:index Vector ref: index out of range>

### errors past the front on a negative index

```scheme
(Vector ref -4 (Vector of 10 20 30))
```
---
    Error: #<err:index Vector ref: index out of range>

### the bare call slot is bounds-checked too

```scheme
((Vector of 10 20 30) 5)
```
---
    Error: #<err:index vector: index out of range>

## vector-length

### returns the length of a vector

```scheme
(Vector length (Vector of 1 2 3))
```
---
    3

### returns 0 for empty vector

```scheme
(Vector length (Vector of))
```
---
    0

## vector->list

### converts a vector to a list

```scheme
(Vector ->list (Vector of 1 2 3))
```
---
    (1 2 3)

## list->vector

### converts a list to a vector

```scheme
(write (Vector from-list (list 4 5 6)))
```
---
    #(4 5 6)

## make-vector

### creates a vector of repeated values

```scheme
(write (Vector make 3 0))
```
---
    #(0 0 0)

### creates a vector with custom fill

```scheme
(write (Vector make 2 7))
```
---
    #(7 7)

### creates an empty vector with make-vector

```scheme
(write (Vector make 0 0))
```
---
    #()

### write separates elements with spaces

```scheme
(write (Vector of 1 2))
```
---
    #(1 2)


## value dispatch (subject-last method form + preserved index call)

### method form: a vector dispatches to Vector (subject appended last)

```scheme
((Vector of 1 2 3) ->list)
```
---
    (1 2 3)

### bare index call still works

```scheme
((Vector of 10 20 30) 1)
```
---
    20

## vector-set!

### stores in place and chains

```scheme
(Vector ref 0 (Vector set! 0 99 (Vector of 1 2)))
```
---
    99

### negative index counts from the end

```scheme
(do (def v (Vector of 1 2 3)) (Vector set! -1 9 v) v)
```
---
    #(1 2 9)

### errors past the end

```scheme
(Vector set! 5 9 (Vector of 1 2))
```
---
    Error: #<err:index Vector set!: index out of range>
