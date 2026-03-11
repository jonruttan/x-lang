
== define

-- defines a variable
(define x 42) x
---
42

-- defines a function
(define (square x) (* x x)) (square 5)
---
25

-- defines multi-body function
(define (f x) (+ x 1) (+ x 2)) (f 10)
---
12

-- defines recursive function
(define (fact n) (if (= n 0) 1 (* n (fact (- n 1))))) (fact 5)
---
120

-- redefines top-level variable
(define x 1) (define x 2) x
---
2

-- defines with expression body
(define x (+ 1 2)) x
---
3

-- interior define in lambda body
((lambda () (define x 42) x))
---
42

-- interior define does not leak
(define x 1) ((lambda () (define x 99) x)) x
---
1

== lambda

-- creates anonymous function
((lambda (x) (* x x)) 4)
---
16

-- lambda is fn alias
(define f (lambda (x y) (+ x y))) (f 3 4)
---
7

-- lambda with multiple body forms
((lambda (x) (+ x 1) (+ x 2)) 10)
---
12

-- lambda with no args
((lambda () 42))
---
42

-- nested lambda (currying)
(((lambda (x) (lambda (y) (+ x y))) 3) 4)
---
7

-- lambda as value in list
(define fs (list (lambda (x) (+ x 1)) (lambda (x) (* x 2)))) ((car fs) 5)
---
6

== begin

-- sequences expressions
(begin 1 2 3)
---
3

-- begin is do alias
(begin (define x 10) (+ x 5))
---
15

-- begin with side effects
(define x 0) (begin (set! x 1) (set! x 2) x)
---
2

== set!

-- mutates binding
(define x 10) (set! x 20) x
---
20

-- set! in nested scope
(define x 10) (let ((y 0)) (set! x 20)) x
---
20

== boolean constants

-- #t is truthy
(if #t 1 2)
---
1

-- #f is falsy
(if #f 1 2)
---
2

== quote shorthand

-- quote symbol
(write 'a)
---
a

-- quote list
(write '(1 2 3))
---
(1 2 3)

-- quote nil
(null? '())
---
t

-- nested quote
(write ''a)
---
(lit a)

-- quote in list context
(write (list 'a 'b))
---
(a b)

== tail recursion

-- tail-recursive factorial
(define (fact n acc) (if (= n 0) acc (fact (- n 1) (* n acc)))) (fact 10 1)
---
3628800

-- tail recursion does not overflow
(define (loop n) (if (= n 0) (quote done) (loop (- n 1)))) (loop 50000)
---
done
