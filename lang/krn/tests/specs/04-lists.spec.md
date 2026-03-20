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

## map

### maps function over list

```scheme
($define! double ($lambda (x) (* x 2))) (map double (list 1 2 3))
```
---
    (2 4 6)

### maps lambda

```scheme
(map ($lambda (x) (+ x 10)) (list 1 2 3))
```
---
    (11 12 13)

## filter

### filters elements

```scheme
(filter ($lambda (x) (> x 2)) (list 1 2 3 4 5))
```
---
    (3 4 5)

### filter none match

```scheme
(null? (filter ($lambda (x) (> x 10)) (list 1 2 3)))
```
---
    #t

## for-each

### applies to each element

```scheme
($define! sum 0) (for-each ($lambda (x) (set! sum (+ sum x))) (list 1 2 3)) sum
```
---
    6

## member

### finds element

```scheme
(member (quote b) (list (quote a) (quote b) (quote c)))
```
---
    (b c)

### returns false when not found

```scheme
(not (member (quote z) (list (quote a) (quote b))))
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

