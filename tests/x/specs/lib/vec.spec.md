# Vec: the growable vector

## construction and growth

### make yields an empty vec

```scheme
(do (import x/type/vec) ((Vec make) empty?))
```
---
    #t

### push! grows past the initial capacity

```scheme
(do (import x/type/vec)
  (let ((v (Vec make 2)))
    (List for-each (fn (_ i) (v push! i)) (List range 0 20))
    (list (v length) (v ref 0) (v ref 19))))
```
---
    (20 0 19)

### from-list preserves order

```scheme
(do (import x/type/vec) ((Vec from-list (list 1 2 3)) ->list))
```
---
    (1 2 3)

## access and mutation

### ref and set! roundtrip

```scheme
(do (import x/type/vec)
  (let ((v (Vec from-list (list 1 2 3))))
    (v set! 1 99)
    (v ref 1)))
```
---
    99

### negative indices count from the end

```scheme
(do (import x/type/vec) ((Vec from-list (list 1 2 3)) ref -1))
```
---
    3

### ref errors out of range

```scheme
(do (import x/type/vec) ((Vec from-list (list 1)) ref 5))
```
---
    Error: Vec ref: index out of range

## pop!

### removes and returns the last element

```scheme
(do (import x/type/vec)
  (let ((v (Vec from-list (list 1 2 3))))
    (list (v pop!) (v length) (v ->list))))
```
---
    (3 2 (1 2))

### errors when empty

```scheme
(do (import x/type/vec) ((Vec make) pop!))
```
---
    Error: Vec pop!: empty
