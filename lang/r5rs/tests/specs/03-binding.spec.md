## let

### creates local bindings

```scheme
(let ((x 10) (y 20)) (+ x y))
```
---
    30

### does not leak bindings

```scheme
(define x 1) (let ((x 99)) x) x
```
---
    1

### shadowing outer variable

```scheme
(define x 1) (let ((x 10)) (+ x 1))
```
---
    11

### body returns last form

```scheme
(let ((x 1)) (+ x 1) (+ x 2) (+ x 3))
```
---
    4

### bindings are parallel

```scheme
(define x 10) (let ((x 1) (y x)) y)
```
---
    10

### nested let

```scheme
(let ((x 1)) (let ((x 2) (y x)) (+ x y)))
```
---
    3

## let*

### creates sequential bindings

```scheme
(let* ((x 1) (y (+ x 1))) (+ x y))
```
---
    3

### later bindings see earlier ones

```scheme
(let* ((a 10) (b (* a 2)) (c (+ b 5))) c)
```
---
    25

### does not leak bindings

```scheme
(define x 1) (let* ((x 99) (y x)) y) x
```
---
    1

### many sequential bindings

```scheme
(let* ((a 1) (b (+ a 1)) (c (+ b 1)) (d (+ c 1))) d)
```
---
    4

### shadows outer

```scheme
(define x 100) (let* ((x 1) (y (+ x 1))) (+ x y))
```
---
    3

## letrec

### binds recursive function

```scheme
(letrec ((fact (lambda (n) (if (= n 0) 1 (* n (fact (- n 1))))))) (fact 5))
```
---
    120

### mutual recursion even

```scheme
(letrec ((e (lambda (n) (if (= n 0) #t (o (- n 1))))) (o (lambda (n) (if (= n 0) #f (e (- n 1)))))) (e 10))
```
---
    t

### mutual recursion odd

```scheme
(letrec ((e (lambda (n) (if (= n 0) #t (o (- n 1))))) (o (lambda (n) (if (= n 0) #f (e (- n 1)))))) (o 7))
```
---
    t

### two independent bindings

```scheme
(letrec ((x 1) (y 2)) (+ x y))
```
---
    3

## named let

### basic loop

```scheme
(let loop ((i 0) (sum 0)) (if (= i 5) sum (loop (+ i 1) (+ sum i))))
```
---
    10

### countdown to list

```scheme
(let count ((n 5) (acc ())) (if (= n 0) acc (count (- n 1) (cons n acc))))
```
---
    (1 2 3 4 5)

### fibonacci

```scheme
(let fib ((n 10) (a 0) (b 1)) (if (= n 0) a (fib (- n 1) b (+ a b))))
```
---
    55

### regular let still works

```scheme
(let ((x 1) (y 2)) (+ x y))
```
---
    3

