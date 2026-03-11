
== cond

-- cond first true
(cond ((> 3 2) (quote greater)) ((< 3 2) (quote less)))
---
greater

-- cond second clause
(cond ((> 3 3) (quote greater)) ((< 3 3) (quote less)) (#t (quote equal)))
---
equal

-- cond no match returns nil
(null? (cond (#f 1)))
---
t

== case

-- case matches symbol
(case (quote b) ((a) 1) ((b) 2) ((c) 3))
---
2

-- case matches number
(case (+ 1 1) ((1) (quote one)) ((2) (quote two)) ((3) (quote three)))
---
two

-- case else clause
(case 99 ((1) (quote one)) (else (quote other)))
---
other

-- case no match returns nil
(null? (case 5 ((1) (quote one)) ((2) (quote two))))
---
t

-- case matches in datum list
(case (quote c) ((a b) 1) ((c d) 2))
---
2

== and

-- and all true returns last
(and 1 2 3)
---
3

-- and short-circuits on false
(null? (and 1 #f 3))
---
t

-- and no args returns true
(and)
---
t

-- and single true arg
(and 42)
---
42

-- and returns first false value
(null? (and #t #f))
---
t

== or

-- or returns first true
(or 1 2 3)
---
1

-- or skips false values
(or #f #f 3)
---
3

-- or no args returns false
(null? (or))
---
t

-- or single false
(null? (or #f))
---
t

-- or single true
(or 7)
---
7

== when

-- when true evaluates body
(when (= 1 1) (+ 10 20))
---
30

-- when false returns nil
(null? (when (= 1 2) 42))
---
t

-- when multiple body forms
(when #t 1 2 3)
---
3

== unless

-- unless false evaluates body
(unless (= 1 2) 99)
---
99

-- unless true returns nil
(null? (unless (= 1 1) 42))
---
t

== let

-- basic let
(let ((x 2) (y 3)) (* x y))
---
6

-- let with shadowing
(define x 1) (let ((x 10)) (+ x 1))
---
11

-- let bindings are parallel
(define x 10) (let ((x 1) (y x)) y)
---
10

-- let body returns last form
(let ((x 1)) (+ x 1) (+ x 2) (+ x 3))
---
4

-- nested let
(let ((x 1)) (let ((x 2) (y x)) (+ x y)))
---
3

== let*

-- let* sequential bindings
(let* ((x 1) (y (+ x 1))) (+ x y))
---
3

-- let* many bindings
(let* ((a 1) (b (+ a 1)) (c (+ b 1)) (d (+ c 1))) d)
---
4

-- let* shadows outer
(define x 100) (let* ((x 1) (y (+ x 1))) (+ x y))
---
3

== letrec

-- letrec recursive function
(letrec ((fact (lambda (n) (if (= n 0) 1 (* n (fact (- n 1))))))) (fact 5))
---
120

-- letrec mutual recursion even
(letrec ((e (lambda (n) (if (= n 0) #t (o (- n 1))))) (o (lambda (n) (if (= n 0) #f (e (- n 1)))))) (e 10))
---
t

-- letrec mutual recursion odd
(letrec ((e (lambda (n) (if (= n 0) #t (o (- n 1))))) (o (lambda (n) (if (= n 0) #f (e (- n 1)))))) (o 7))
---
t

== named let

-- named let loop
(let loop ((i 0) (sum 0)) (if (= i 5) sum (loop (+ i 1) (+ sum i))))
---
10

-- named let countdown
(let count ((n 5) (acc ())) (if (= n 0) acc (count (- n 1) (cons n acc))))
---
(1 2 3 4 5)

-- named let fibonacci
(let fib ((n 10) (a 0) (b 1)) (if (= n 0) a (fib (- n 1) b (+ a b))))
---
55

== begin

-- begin returns last
(begin 1 2 3)
---
3

-- begin with side effects
(define x 0) (begin (set! x 1) (set! x 2) x)
---
2

== quasiquote

-- basic quasiquote
(define x 42) (quasiquote (a (unquote x) c))
---
(a 42 c)

-- quasiquote with expression
(quasiquote (a (unquote (+ 1 2)) c))
---
(a 3 c)

-- unquote-splicing
(quasiquote (a (unquote-splicing (list 1 2 3)) b))
---
(a 1 2 3 b)

-- nested quasiquote structure
(quasiquote (a (b (unquote (+ 1 2)))))
---
(a (b 3))

-- quasiquote without unquote
(quasiquote (a b c))
---
(a b c)

== case-lambda

-- case-lambda one arg
(define f (case-lambda ((x) (* x x)) ((x y) (+ x y)))) (f 5)
---
25

-- case-lambda two args
(define f (case-lambda ((x) (* x x)) ((x y) (+ x y)))) (f 3 4)
---
7

-- case-lambda three args
(define f (case-lambda ((x) x) ((x y) (+ x y)) ((x y z) (* x y z)))) (f 2 3 4)
---
24

-- case-lambda zero args
(define f (case-lambda (() 42) ((x) x))) (f)
---
42

-- case-lambda single clause
(define f (case-lambda ((x y) (- x y)))) (f 10 3)
---
7

-- case-lambda as procedure
(procedure? (case-lambda ((x) x)))
---
t
