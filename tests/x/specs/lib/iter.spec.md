## iter

### iterates a list

```scheme
(Iter ->list (Iter new (list 1 2 3)))
```
---
    (1 2 3)

### iterates a vector

```scheme
(Iter ->list (Iter new (Vector of 10 20 30)))
```
---
    (10 20 30)

### iterates a string by code point

```scheme
(Iter ->list (Iter new "abc"))
```
---
    (#\a #\b #\c)

### empty list yields an empty iterator

```scheme
(null? (Iter ->list (Iter new (list))))
```
---
    #t

### empty vector yields an empty iterator

```scheme
(null? (Iter ->list (Iter new (Vector of))))
```
---
    #t

## iter-empty?

### reports exhaustion across a step

```scheme
(do (def it (Iter new (list 1))) (def before (Iter empty? it)) (Iter next it) (list before (Iter empty? it)))
```
---
    (#f #t)

## iter-next

### advances element by element

```scheme
(do (def it (Iter new (list 7 8 9))) (list (Iter next it) (Iter next it) (Iter next it)))
```
---
    (7 8 9)

## iter-fold

### left-folds the remaining elements

```scheme
(Iter fold + 0 (Iter new (list 1 2 3 4)))
```
---
    10

## iter-for-each

### visits every element

```scheme
(do (def %acc (list 0)) (Iter for-each (fn (_ x) (%set-first! %acc (+ (first %acc) x))) (Iter new (Vector of 1 2 3 4))) (first %acc))
```
---
    10

## iter (class instances)

### iterates a def-class instance as name/value pairs

```scheme
(do (def-class Pt () (x 0) (y 0)) (def p (new Pt x 3 y 4)) (Iter ->list (Iter new p)))
```
---
    (('x . 3) ('y . 4))

## make-iter

### builds an iterator from a custom step function (pure: state -> (value . next-state))

```scheme
(do (def it (Iter make (fn (self st) (if (null? st) () (pair (first st) (rest st)))) (list 5 6))) (Iter ->list it))
```
---
    (5 6)

## step (the functional door)

### yields (value . next-iterator) and leaves the source untouched

```scheme
(do (import x/type/iter)
  (def it (Iter new (list 7 8)))
  (def s (Iter step it))
  (list (first s) (Iter next (rest s)) (Iter next it)))
```
---
    (7 8 7)

### returns nil on an exhausted iterator

```scheme
(do (import x/type/iter) (null? (Iter step (Iter new ()))))
```
---
    #t

## iter?

### true for an iterator

```scheme
(Iter iter? (Iter new (list 1 2 3)))
```
---
    #t

### false for the underlying list

```scheme
(if (Iter iter? (list 1 2 3)) "yes" "no")
```
---
    "no"

### false for an integer

```scheme
(if (Iter iter? 42) "yes" "no")
```
---
    "no"
