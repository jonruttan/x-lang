## cons / car / cdr

### cons creates dotted pair

```scheme
(cons 1 2)
```
---
    (1 . 2)

### cons with list

```scheme
(cons 1 (list 2 3))
```
---
    (1 2 3)

### car of cons

```scheme
(car (cons 1 2))
```
---
    1

### cdr of cons

```scheme
(cdr (cons 1 2))
```
---
    2

### car of list

```scheme
(car (list 10 20 30))
```
---
    10

### cdr of list

```scheme
(cdr (list 10 20 30))
```
---
    (20 30)

## accessors

### cadr

```scheme
(cadr (list 1 2 3))
```
---
    2

### caddr

```scheme
(caddr (list 1 2 3))
```
---
    3

### caar

```scheme
(caar (list (list 1 2) 3))
```
---
    1

### cdar

```scheme
(cdar (list (list 1 2) 3))
```
---
    (2)

### cddr

```scheme
(cddr (list 1 2 3 4))
```
---
    (3 4)

## list constructor

### list creates list

```scheme
(list 1 2 3)
```
---
    (1 2 3)

### list with single element

```scheme
(list 42)
```
---
    (42)

### empty list

```scheme
(null? (list))
```
---
    #t

## pair? / null?

### pair? on list

```scheme
(pair? (list 1 2))
```
---
    #t

### pair? on cons

```scheme
(pair? (cons 1 2))
```
---
    #t

### pair? on number

```scheme
(not (pair? 42))
```
---
    #t

### pair? on nil

```scheme
(not (pair? ()))
```
---
    #t

### null? on empty

```scheme
(null? ())
```
---
    #t

### null? on non-empty

```scheme
(not (null? (list 1)))
```
---
    #t

## list?

### proper list

```scheme
(list? (list 1 2 3))
```
---
    #t

### empty list

```scheme
(list? ())
```
---
    #t

### dotted pair

```scheme
(not (list? (cons 1 2)))
```
---
    #t

### non-list

```scheme
(not (list? 42))
```
---
    #t

## length

### empty list

```scheme
(length ())
```
---
    0

### non-empty list

```scheme
(length (list 1 2 3))
```
---
    3

### single element

```scheme
(length (list 42))
```
---
    1

## append

### appends two lists

```scheme
(append (list 1 2) (list 3 4))
```
---
    (1 2 3 4)

### append with empty

```scheme
(append () (list 1 2))
```
---
    (1 2)

### append empty to empty

```scheme
(null? (append () ()))
```
---
    #t

## reverse

### reverses a list

```scheme
(reverse (list 1 2 3))
```
---
    (3 2 1)

### reverse empty

```scheme
(null? (reverse ()))
```
---
    #t

### reverse single

```scheme
(reverse (list 42))
```
---
    (42)

## list-ref

### gets element by index

```scheme
(list-ref (list 10 20 30) 1)
```
---
    20

### first element

```scheme
(list-ref (list 10 20 30) 0)
```
---
    10

### last element

```scheme
(list-ref (list 10 20 30) 2)
```
---
    30

## list-tail

### gets tail from index

```scheme
(list-tail (list 1 2 3 4) 2)
```
---
    (3 4)

### tail from zero

```scheme
(list-tail (list 1 2 3) 0)
```
---
    (1 2 3)

## map

### maps function over list

```scheme
(define (double x) (* x 2)) (map double (list 1 2 3))
```
---
    (2 4 6)

### maps lambda

```scheme
(map (lambda (x) (+ x 10)) (list 1 2 3))
```
---
    (11 12 13)

### map over empty list

```scheme
(null? (map (lambda (x) x) ()))
```
---
    #t

## filter

### filters elements

```scheme
(filter (lambda (x) (> x 2)) (list 1 2 3 4 5))
```
---
    (3 4 5)

### filter none match

```scheme
(null? (filter (lambda (x) (> x 10)) (list 1 2 3)))
```
---
    #t

### filter all match

```scheme
(filter (lambda (x) (> x 0)) (list 1 2 3))
```
---
    (1 2 3)

## for-each

### applies to each element

```scheme
(define sum 0) (for-each (lambda (x) (set! sum (+ sum x))) (list 1 2 3)) sum
```
---
    6

## member

### finds symbol

```scheme
(member (quote b) (list (quote a) (quote b) (quote c)))
```
---
    (b c)

### finds number

```scheme
(member 3 (list 1 2 3 4 5))
```
---
    (3 4 5)

### returns false when not found

```scheme
(not (member (quote z) (list (quote a) (quote b))))
```
---
    #t

## memq

### finds symbol

```scheme
(memq (quote b) (list (quote a) (quote b) (quote c)))
```
---
    (b c)

### not found

```scheme
(not (memq (quote z) (list (quote a) (quote b))))
```
---
    #t

## assoc

### finds association

```scheme
(assoc (quote b) (list (list (quote a) 1) (list (quote b) 2)))
```
---
    (b 2)

### returns false when not found

```scheme
(not (assoc (quote z) (list (list (quote a) 1))))
```
---
    #t

## assq

### finds by symbol

```scheme
(assq (quote b) (list (list (quote a) 1) (list (quote b) 2)))
```
---
    (b 2)

### not found

```scheme
(not (assq (quote z) (list (list (quote a) 1))))
```
---
    #t

## apply

### apply with built-in

```scheme
(apply + (list 1 2 3))
```
---
    6

### apply with lambda

```scheme
(apply (lambda (x y) (* x y)) (list 3 4))
```
---
    12

