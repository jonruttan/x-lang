
== quotation

-- quote symbol
(quote a)
---
a

-- quote list
(quote (+ 1 2))
---
(+ 1 2)

-- quote number is identity
(quote 42)
---
42

-- quote string is identity
(quote "hello")
---
"hello"

== lambda

-- lambda application
((lambda (x) (+ x x)) 4)
---
8

-- lambda with rest args
((lambda x x) 3 4 5 6)
---
(3 4 5 6)

-- lambda with required and rest
((lambda (x y . z) z) 3 4 5 6)
---
(5 6)

-- lambda no args
((lambda () 42))
---
42

-- lambda multiple body forms
((lambda (x) (+ x 1) (+ x 2)) 10)
---
12

-- nested lambda
(((lambda (x) (lambda (y) (+ x y))) 3) 4)
---
7

== if

-- if true branch
(if (> 3 2) (quote yes) (quote no))
---
yes

-- if false branch
(if (> 2 3) (quote yes) (quote no))
---
no

-- if no else returns nil
(null? (if #f 1))
---
t

-- if non-false is true
(if 0 (quote yes) (quote no))
---
yes

-- if nil is false
(if () (quote yes) (quote no))
---
no

== define

-- define variable
(define x 28) x
---
28

-- define function shorthand
(define (f x) (+ x 1)) (f 10)
---
11

-- define with expression body
(define x (* 3 4)) x
---
12

-- redefine variable
(define x 1) (define x 2) x
---
2

== set!

-- set! mutates binding
(define x 1) (set! x 2) x
---
2

-- set! in nested scope
(define x 10) (let ((y 0)) (set! x 20)) x
---
20
