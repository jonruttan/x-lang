## iter

### iterates a list

```scheme
(iter->list (iter (list 1 2 3)))
```
---
    (1 2 3)

### iterates a vector

```scheme
(iter->list (iter (vector 10 20 30)))
```
---
    (10 20 30)

### iterates a string by code point

```scheme
(iter->list (iter "abc"))
```
---
    (#\a #\b #\c)

### empty list yields an empty iterator

```scheme
(null? (iter->list (iter (list))))
```
---
    #t

### empty vector yields an empty iterator

```scheme
(null? (iter->list (iter (vector))))
```
---
    #t

## iter-empty?

### reports exhaustion across a step

```scheme
(do (def it (iter (list 1))) (def before (Iter empty? it)) (Iter next it) (list before (Iter empty? it)))
```
---
    (#f #t)

## iter-next

### advances element by element

```scheme
(do (def it (iter (list 7 8 9))) (list (Iter next it) (Iter next it) (Iter next it)))
```
---
    (7 8 9)

## iter-fold

### left-folds the remaining elements

```scheme
(iter-fold + 0 (iter (list 1 2 3 4)))
```
---
    10

## iter-for-each

### visits every element

```scheme
(do (def %acc (list 0)) (iter-for-each (fn (_ x) (set-first! %acc (+ (first %acc) x))) (iter (vector 1 2 3 4))) (first %acc))
```
---
    10

## iter (class instances)

### iterates a def-class instance as name/value pairs

```scheme
(do (def-class Pt () (x 0) (y 0)) (def p (new Pt x 3 y 4)) (iter->list (iter p)))
```
---
    (((lit x) . 3) ((lit y) . 4))

## make-iter

### builds an iterator from a custom step function

```scheme
(do (def it (Iter make (fn (self it) (if (null? (rest it)) () (do (def v (first (rest it))) (set-rest! it (rest (rest it))) v))) (list 5 6))) (iter->list it))
```
---
    (5 6)
