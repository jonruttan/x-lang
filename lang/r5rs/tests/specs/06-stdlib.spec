
== identity

-- returns its argument
(identity 42)
---
42

-- returns a list
(identity (list 1 2))
---
(1 2)

== const

-- returns a function that ignores its argument
((const 5) 99)
---
5

-- works with symbols
((const (quote hello)) 0)
---
hello

== compose

-- composes two functions
(define (double x) (* x 2)) (define (inc x) (+ x 1)) ((compose double inc) 3)
---
8

-- applies right function first
((compose (lambda (x) (+ x 10)) (lambda (x) (* x 2))) 5)
---
20

== curry

-- partially applies a function
(define (add a b) (+ a b)) (define add5 (curry add 5)) (add5 3)
---
8

-- works with built-in operators
(define mul (curry * 10)) (mul 7)
---
70

== fold

-- left-folds a list
(fold + 0 (list 1 2 3 4))
---
10

-- accumulates from the left
(fold - 10 (list 1 2 3))
---
4

-- returns init for empty list
(fold + 0 ())
---
0

== reduce

-- reduces a list with no init
(reduce + (list 1 2 3 4))
---
10

-- works with subtraction
(reduce - (list 10 3 2))
---
5

== range

-- generates a range
(range 0 5)
---
(0 1 2 3 4)

-- returns empty for start >= end
(null? (range 5 5))
---
t

-- works with non-zero start
(range 3 6)
---
(3 4 5)

== zip

-- pairs elements from two lists
(zip (list 1 2 3) (list 4 5 6))
---
((1 4) (2 5) (3 6))

-- stops at shorter list
(zip (list 1 2) (list 3))
---
((1 3))

-- returns empty for empty input
(null? (zip () (list 1)))
---
t

== any?

-- returns t when predicate matches
(any? (lambda (x) (> x 3)) (list 1 2 3 4 5))
---
t

-- returns nil when none match
(null? (any? (lambda (x) (> x 10)) (list 1 2 3)))
---
t

-- returns nil for empty list
(null? (any? (lambda (x) t) ()))
---
t

== every?

-- returns t when all match
(every? (lambda (x) (> x 0)) (list 1 2 3))
---
t

-- returns nil when one fails
(null? (every? (lambda (x) (> x 2)) (list 1 2 3)))
---
t

-- returns t for empty list
(every? (lambda (x) (> x 0)) ())
---
t
