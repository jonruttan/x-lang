## pair basics

### cons creates pair

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

### pair? on pair

```scheme
(pair? (cons 1 2))
```
---
    t

### pair? on list

```scheme
(pair? (list 1 2))
```
---
    t

### pair? on number

```scheme
(null? (pair? 42))
```
---
    t

### pair? on nil

```scheme
(null? (pair? ()))
```
---
    t

## list constructor

### list creates list

```scheme
(list 1 2 3)
```
---
    (1 2 3)

### list single element

```scheme
(list 42)
```
---
    (42)

### list empty

```scheme
(null? (list))
```
---
    t

## list predicates

### list? on proper list

```scheme
(list? (list 1 2 3))
```
---
    t

### list? on empty

```scheme
(list? ())
```
---
    t

### list? on dotted pair

```scheme
(null? (list? (cons 1 2)))
```
---
    t

### list? on atom

```scheme
(null? (list? 42))
```
---
    t

### null? on nil

```scheme
(null? ())
```
---
    t

### null? on list

```scheme
(null? (null? (list 1)))
```
---
    t

## make-list

### make-list with fill

```scheme
(make-list 3 0)
```
---
    (0 0 0)

### make-list with value

```scheme
(make-list 4 (quote x))
```
---
    (x x x x)

### make-list zero length

```scheme
(null? (make-list 0 1))
```
---
    t

## list operations

### length

```scheme
(length (list 1 2 3))
```
---
    3

### length empty

```scheme
(length ())
```
---
    0

### append two lists

```scheme
(append (list 1 2) (list 3 4))
```
---
    (1 2 3 4)

### append empty

```scheme
(null? (append () ()))
```
---
    t

### append nested

```scheme
(append (list 1) (append (list 2) (list 3)))
```
---
    (1 2 3)

### reverse

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
    t

## list access

### list-ref first

```scheme
(list-ref (list 10 20 30) 0)
```
---
    10

### list-ref last

```scheme
(list-ref (list 10 20 30) 2)
```
---
    30

### list-tail

```scheme
(list-tail (list 1 2 3 4) 2)
```
---
    (3 4)

### list-tail zero

```scheme
(list-tail (list 1 2 3) 0)
```
---
    (1 2 3)

## list-copy

### list-copy proper list

```scheme
(list-copy (list 1 2 3))
```
---
    (1 2 3)

### list-copy is equal

```scheme
(equal? (list-copy (list 1 2 3)) (list 1 2 3))
```
---
    t

### list-copy empty

```scheme
(null? (list-copy ()))
```
---
    t

## member

### member finds element

```scheme
(member 3 (list 1 2 3 4 5))
```
---
    (3 4 5)

### member not found

```scheme
(null? (member 6 (list 1 2 3)))
```
---
    t

## memq

### memq finds symbol

```scheme
(memq (quote b) (list (quote a) (quote b) (quote c)))
```
---
    (b c)

### memq not found

```scheme
(null? (memq (quote z) (list (quote a) (quote b))))
```
---
    t

## assoc

### assoc finds key

```scheme
(assoc (quote b) (list (list (quote a) 1) (list (quote b) 2) (list (quote c) 3)))
```
---
    (b 2)

### assoc not found

```scheme
(null? (assoc (quote z) (list (list (quote a) 1))))
```
---
    t

## assq

### assq finds key

```scheme
(assq (quote b) (list (list (quote a) 1) (list (quote b) 2)))
```
---
    (b 2)

### assq not found

```scheme
(null? (assq (quote z) (list (list (quote a) 1))))
```
---
    t

