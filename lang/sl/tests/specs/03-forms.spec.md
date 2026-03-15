## when

### executes body when true

```scheme
(define x 0) (when #t (set! x 42)) x
```
---
    42

### skips body when false

```scheme
(define x 0) (when #f (set! x 42)) x
```
---
    0

## unless

### executes body when false

```scheme
(define x 0) (unless #f (set! x 42)) x
```
---
    42

### skips body when true

```scheme
(define x 0) (unless #t (set! x 42)) x
```
---
    0

## let*

### sequential binding

```scheme
(let* ((x 1) (y (+ x 1))) (+ x y))
```
---
    3

### nested sequential

```scheme
(let* ((a 10) (b (* a 2)) (c (+ a b))) c)
```
---
    30

## letrec

### mutual recursion

```scheme
(letrec ((even? (lambda (n) (if (= n 0) #t (odd? (- n 1))))) (odd? (lambda (n) (if (= n 0) #f (even? (- n 1)))))) (even? 10))
```
---
    #t

## named let

### loop with named let

```scheme
(let loop ((i 0) (acc 0)) (if (= i 5) acc (loop (+ i 1) (+ acc i))))
```
---
    10

## case

### matches literal

```scheme
(case 2 ((1) 10) ((2) 20) ((3) 30))
```
---
    20

### matches else clause

```scheme
(case 99 ((1) 10) (else 0))
```
---
    0

## member

### finds element in list

```scheme
(member 3 (list 1 2 3 4 5))
```
---
    (3 4 5)

### returns false when not found

```scheme
(if (member 6 (list 1 2 3)) 1 0)
```
---
    0

## assoc

### finds key in alist

```scheme
(assoc 2 (list (list 1 10) (list 2 20) (list 3 30)))
```
---
    (2 20)

### returns false when not found

```scheme
(if (assoc 4 (list (list 1 10) (list 2 20))) 1 0)
```
---
    0

## list-ref / list-tail

### list-ref gets nth element

```scheme
(list-ref (list 10 20 30 40) 2)
```
---
    30

### list-tail drops first n

```scheme
(list-tail (list 10 20 30 40) 2)
```
---
    (30 40)

