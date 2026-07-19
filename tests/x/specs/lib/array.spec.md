# Array: the growable container

## construction and growth

### of builds an array variadically

```scheme
(do (import x/type/array) ((Array of 1 2 3) ->list))
```
---
    (1 2 3)

### make yields an empty array

```scheme
(do (import x/type/array) ((Array make) empty?))
```
---
    #t

### push! grows past the initial capacity

```scheme
(do (import x/type/array)
  (let ((v (Array make 2)))
    (List for-each (fn (_ i) (v push! i)) (List range 0 20))
    (list (v length) (v ref 0) (v ref 19))))
```
---
    (20 0 19)

### from-list preserves order

```scheme
(do (import x/type/array) ((Array from-list (list 1 2 3)) ->list))
```
---
    (1 2 3)

## access and mutation

### ref and set! roundtrip

```scheme
(do (import x/type/array)
  (let ((v (Array from-list (list 1 2 3))))
    (v set! 1 99)
    (v ref 1)))
```
---
    99

### negative indices count from the end

```scheme
(do (import x/type/array) ((Array from-list (list 1 2 3)) ref -1))
```
---
    3

### ref errors out of range

```scheme
(do (import x/type/array) ((Array from-list (list 1)) ref 5))
```
---
    Error: #<err:index Array ref: index out of range>

## pop!

### removes and returns the last element

```scheme
(do (import x/type/array)
  (let ((v (Array from-list (list 1 2 3))))
    (list (v pop!) (v length) (v ->list))))
```
---
    (3 2 (1 2))

### errors when empty

```scheme
(do (import x/type/array) ((Array make) pop!))
```
---
    Error: #<err:value Array pop!: empty>

## new is make

### the generic allocator can no longer build an unusable array

```scheme
(do (import x/type/array) (((Array new) push! 7) ->list))
```
---
    (7)
