
== define

-- defines a variable
(define x 42) x
---
42

-- defines a function with sugar
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

== lambda

-- creates anonymous function
((lambda (x) (* x x)) 4)
---
16

-- lambda is fn alias
(define f (lambda (x y) (+ x y))) (f 3 4)
---
7

== begin

-- sequences expressions
(begin 1 2 3)
---
3

-- begin is do alias
(begin (define x 10) (+ x 5))
---
15

== set!

-- mutates binding
(define x 10) (set! x 20) x
---
20

== cons/car/cdr

-- cons builds a pair
(cons 1 2)
---
(1 . 2)

-- car returns first element
(car (cons 1 2))
---
1

-- cdr returns rest element
(cdr (cons 1 2))
---
2

-- cons builds a list
(cons 1 (cons 2 (cons 3 ())))
---
(1 2 3)

-- car of list
(car (list 1 2 3))
---
1

-- cdr of list
(cdr (list 1 2 3))
---
(2 3)

== boolean constants

-- #t is truthy
(if #t 1 2)
---
1

-- #f is falsy
(if #f 1 2)
---
2

== composition accessors

-- caar
(caar (list (list 1 2) (list 3 4)))
---
1

-- cadr
(cadr (list 1 2 3))
---
2

-- cdar
(cdar (list (list 1 2) 3))
---
(2)

-- cddr
(cddr (list 1 2 3))
---
(3)

-- caddr
(caddr (list 1 2 3))
---
3

== convenience aliases

-- first returns car
(first (list 10 20 30))
---
10

-- second returns cadr
(second (list 10 20 30))
---
20

-- third returns caddr
(third (list 10 20 30))
---
30

-- rest returns cdr
(rest (list 10 20 30))
---
(20 30)

-- modulo alias
(modulo 10 3)
---
1

== I/O constants

-- stdin is 0
stdin
---
0

-- stdout is 1
stdout
---
1

-- stderr is 2
stderr
---
2
