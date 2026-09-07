# @weight 1
## vector

### creates a vector from arguments

```x
(write (Vector of 1 2 3))
```
---
    #(1 2 3)

### creates a single-element vector

```x
(write (Vector of 42))
```
---
    #(42)

### creates an empty vector

```x
(write (Vector of))
```
---
    #()

### builds a vector from an index function

```x
(write (Vector build 4 (fn (_ i) (* i i))))
```
---
    #(0 1 4 9)

## vector indexing

### indexes from the start

```x
((Vector of 10 20 30) 1)
```
---
    20

### indexes first element

```x
((Vector of 10 20 30) 0)
```
---
    10

### indexes last element

```x
((Vector of 10 20 30) 2)
```
---
    30

### indexes from the end with negative

```x
((Vector of 10 20 30) -1)
```
---
    30

## vector?

### returns #t for a vector

```x
(Vector vector? (Vector of 1))
```
---
    #t

### returns nil for a list

```x
(if (Vector vector? (list 1)) "yes" "no")
```
---
    "no"

### returns nil for an integer

```x
(if (Vector vector? 42) "yes" "no")
```
---
    "no"

## vector-ref

### retrieves element by index

```x
(Vector ref 1 (Vector of 10 20 30))
```
---
    20

### indexes from the end with negative, matching the call slot

```x
(Vector ref -1 (Vector of 10 20 30))
```
---
    30

### errors past the end instead of reading raw memory

```x
(Vector ref 5 (Vector of 10 20 30))
```
---
    Error: #<err:index Vector ref: index out of range>

### errors past the front on a negative index

```x
(Vector ref -4 (Vector of 10 20 30))
```
---
    Error: #<err:index Vector ref: index out of range>

### the bare call slot is bounds-checked too

```x
((Vector of 10 20 30) 5)
```
---
    Error: #<err:index vector: index out of range>

## vector-length

### returns the length of a vector

```x
(Vector length (Vector of 1 2 3))
```
---
    3

### returns 0 for empty vector

```x
(Vector length (Vector of))
```
---
    0

## vector->list

### converts a vector to a list

```x
(Vector ->list (Vector of 1 2 3))
```
---
    (1 2 3)

## list->vector

### converts a list to a vector

```x
(write (Vector from-list (list 4 5 6)))
```
---
    #(4 5 6)

## make-vector

### creates a vector of repeated values

```x
(write (Vector make 3 0))
```
---
    #(0 0 0)

### creates a vector with custom fill

```x
(write (Vector make 2 7))
```
---
    #(7 7)

### creates an empty vector with make-vector

```x
(write (Vector make 0 0))
```
---
    #()

### write separates elements with spaces

```x
(write (Vector of 1 2))
```
---
    #(1 2)


## value dispatch (subject-last method form + preserved index call)

### method form: a vector dispatches to Vector (subject appended last)

```x
((Vector of 1 2 3) ->list)
```
---
    (1 2 3)

### bare index call still works

```x
((Vector of 10 20 30) 1)
```
---
    20

## vector-set!

### stores in place and chains

```x
(Vector ref 0 (Vector set! 0 99 (Vector of 1 2)))
```
---
    99

### negative index counts from the end

```x
(do (def v (Vector of 1 2 3)) (Vector set! -1 9 v) v)
```
---
    #(1 2 9)

### errors past the end

```x
(Vector set! 5 9 (Vector of 1 2))
```
---
    Error: #<err:index Vector set!: index out of range>

### rejects a non-vector receiver

```x
(Vector length 7)
```
---
    Error: #<err:type Vector length: not a vector>

### ref rejects a non-vector receiver

```x
(Vector ref 0 42)
```
---
    Error: #<err:type Vector ref: not a vector>

### ref on a list no longer returns pair internals

```x
(Vector ref 0 (list 1 2 3))
```
---
    Error: #<err:type Vector ref: not a vector>

### set! rejects a non-vector receiver

```x
(Vector set! 0 9 42)
```
---
    Error: #<err:type Vector set!: not a vector>

### ->list rejects a non-vector receiver

```x
(Vector ->list 7)
```
---
    Error: #<err:type Vector ->list: not a vector>

### make rejects a negative length (#52)

A negative n built a vector REPORTING length n, so every later bounds check
compared against a lie.

```x
(list (guard (e (Err kind-of e)) (Vector make -5)) (Vector length (Vector make 0)))
```
---
    ('value 0)

## traversal

### map builds a new vector in place

```x
(Vector map (fn (_ x) (* x 2)) (Vector of 1 2 3))
```
---
    #(2 4 6)

### map over an empty vector is empty

```x
(Vector map (fn (_ x) x) (Vector of))
```
---
    #()

### filter keeps the satisfying elements, in order

```x
(Vector filter (fn (_ x) (> x 1)) (Vector of 3 1 2))
```
---
    #(3 2)

### filter can keep nothing

```x
(Vector length (Vector filter (fn (_ x) #f) (Vector of 1 2)))
```
---
    0

### fold threads the accumulator left to right

```x
(Vector fold (fn (_ a x) (Str8 str a x)) "" (Vector of "a" "b" "c"))
```
---
    "abc"

### fold over an empty vector returns the seed

```x
(Vector fold + 99 (Vector of))
```
---
    99

### for-each visits every element in order and returns nil

```x
(let ((acc (list ()))) (Vector for-each (fn (_ x) (%set-first! acc (pair x (first acc)))) (Vector of 1 2 3)) (first acc))
```
---
    (3 2 1)

### traversal rejects a non-vector receiver

```x
(guard (e (Err kind-of e)) (Vector map (fn (_ x) x) 7))
```
---
    'type

### the value form dispatches subject-last

```x
((Vector of 1 2 3) filter (fn (_ x) (> x 1)))
```
---
    #(2 3)

### a bare call with no index is an error, not a crash

`first` on `()` is undefined and would dereference nil, so the index handler
guards before it reads. `(Vector length v)` is the length door.

```x
(guard (e e) (#(1 2 3)))
```
---
    #<err:index vector: call with no index>

### indexing still works either way round it

```x
(list (#(1 2 3) 0) (#(1 2 3) -1) (guard (e (Err kind-of e)) (#(1 2 3) 9)))
```
---
    (1 3 'index)
