## cond

### cond first true

```scheme
(cond ((> 3 2) (quote greater)) ((< 3 2) (quote less)))
```
---
    greater

### cond second clause

```scheme
(cond ((> 3 3) (quote greater)) ((< 3 3) (quote less)) (#t (quote equal)))
```
---
    equal

### cond no match returns nil

```scheme
(null? (cond (#f 1)))
```
---
    #t

## case

### case matches symbol

```scheme
(case (quote b) ((a) 1) ((b) 2) ((c) 3))
```
---
    2

### case matches number

```scheme
(case (+ 1 1) ((1) (quote one)) ((2) (quote two)) ((3) (quote three)))
```
---
    two

### case else clause

```scheme
(case 99 ((1) (quote one)) (else (quote other)))
```
---
    other

### case no match returns nil

```scheme
(null? (case 5 ((1) (quote one)) ((2) (quote two))))
```
---
    #t

### case matches in datum list

```scheme
(case (quote c) ((a b) 1) ((c d) 2))
```
---
    2

## and

### and all true returns last

```scheme
(and 1 2 3)
```
---
    3

### and short-circuits on false

```scheme
(not (and 1 #f 3))
```
---
    #t

### and no args returns true

```scheme
(and)
```
---
    #t

### and single true arg

```scheme
(and 42)
```
---
    42

### and returns first false value

```scheme
(not (and #t #f))
```
---
    #t

## or

### or returns first true

```scheme
(or 1 2 3)
```
---
    1

### or skips false values

```scheme
(or #f #f 3)
```
---
    3

### or no args returns false

```scheme
(not (or))
```
---
    #t

### or single false

```scheme
(not (or #f))
```
---
    #t

### or single true

```scheme
(or 7)
```
---
    7

## when

### when true evaluates body

```scheme
(when (= 1 1) (+ 10 20))
```
---
    30

### when false returns nil

```scheme
(null? (when (= 1 2) 42))
```
---
    #t

### when multiple body forms

```scheme
(when #t 1 2 3)
```
---
    3

## unless

### unless false evaluates body

```scheme
(unless (= 1 2) 99)
```
---
    99

### unless true returns nil

```scheme
(null? (unless (= 1 1) 42))
```
---
    #t

## let

### basic let

```scheme
(let ((x 2) (y 3)) (* x y))
```
---
    6

### let with shadowing

```scheme
(define x 1) (let ((x 10)) (+ x 1))
```
---
    11

### let bindings are parallel

```scheme
(define x 10) (let ((x 1) (y x)) y)
```
---
    10

### let body returns last form

```scheme
(let ((x 1)) (+ x 1) (+ x 2) (+ x 3))
```
---
    4

### nested let

```scheme
(let ((x 1)) (let ((x 2) (y x)) (+ x y)))
```
---
    3

## let*

### let* sequential bindings

```scheme
(let* ((x 1) (y (+ x 1))) (+ x y))
```
---
    3

### let* many bindings

```scheme
(let* ((a 1) (b (+ a 1)) (c (+ b 1)) (d (+ c 1))) d)
```
---
    4

### let* shadows outer

```scheme
(define x 100) (let* ((x 1) (y (+ x 1))) (+ x y))
```
---
    3

## letrec

### letrec recursive function

```scheme
(letrec ((fact (lambda (n) (if (= n 0) 1 (* n (fact (- n 1))))))) (fact 5))
```
---
    120

### letrec mutual recursion even

```scheme
(letrec ((e (lambda (n) (if (= n 0) #t (o (- n 1))))) (o (lambda (n) (if (= n 0) #f (e (- n 1)))))) (e 10))
```
---
    #t

### letrec mutual recursion odd

```scheme
(letrec ((e (lambda (n) (if (= n 0) #t (o (- n 1))))) (o (lambda (n) (if (= n 0) #f (e (- n 1)))))) (o 7))
```
---
    #t

## named let

### named let loop

```scheme
(let loop ((i 0) (sum 0)) (if (= i 5) sum (loop (+ i 1) (+ sum i))))
```
---
    10

### named let countdown

```scheme
(let count ((n 5) (acc ())) (if (= n 0) acc (count (- n 1) (cons n acc))))
```
---
    (1 2 3 4 5)

### named let fibonacci

```scheme
(let fib ((n 10) (a 0) (b 1)) (if (= n 0) a (fib (- n 1) b (+ a b))))
```
---
    55

## begin

### begin returns last

```scheme
(begin 1 2 3)
```
---
    3

### begin with side effects

```scheme
(define x 0) (begin (set! x 1) (set! x 2) x)
```
---
    2

## quasiquote

### basic quasiquote

```scheme
(define x 42) (quasiquote (a (unquote x) c))
```
---
    (a 42 c)

### quasiquote with expression

```scheme
(quasiquote (a (unquote (+ 1 2)) c))
```
---
    (a 3 c)

### unquote-splicing

```scheme
(quasiquote (a (unquote-splicing (list 1 2 3)) b))
```
---
    (a 1 2 3 b)

### nested quasiquote structure

```scheme
(quasiquote (a (b (unquote (+ 1 2)))))
```
---
    (a (b 3))

### quasiquote without unquote

```scheme
(quasiquote (a b c))
```
---
    (a b c)

## case-lambda

### case-lambda one arg

```scheme
(define f (case-lambda ((x) (* x x)) ((x y) (+ x y)))) (f 5)
```
---
    25

### case-lambda two args

```scheme
(define f (case-lambda ((x) (* x x)) ((x y) (+ x y)))) (f 3 4)
```
---
    7

### case-lambda three args

```scheme
(define f (case-lambda ((x) x) ((x y) (+ x y)) ((x y z) (* x y z)))) (f 2 3 4)
```
---
    24

### case-lambda zero args

```scheme
(define f (case-lambda (() 42) ((x) x))) (f)
```
---
    42

### case-lambda single clause

```scheme
(define f (case-lambda ((x y) (- x y)))) (f 10 3)
```
---
    7

### case-lambda as procedure

```scheme
(procedure? (case-lambda ((x) x)))
```
---
    #t

