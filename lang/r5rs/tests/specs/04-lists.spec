
== cons / car / cdr

-- cons creates dotted pair
(cons 1 2)
---
(1 . 2)

-- cons with list
(cons 1 (list 2 3))
---
(1 2 3)

-- car of cons
(car (cons 1 2))
---
1

-- cdr of cons
(cdr (cons 1 2))
---
2

-- car of list
(car (list 10 20 30))
---
10

-- cdr of list
(cdr (list 10 20 30))
---
(20 30)

== accessors

-- cadr
(cadr (list 1 2 3))
---
2

-- caddr
(caddr (list 1 2 3))
---
3

-- caar
(caar (list (list 1 2) 3))
---
1

-- cdar
(cdar (list (list 1 2) 3))
---
(2)

-- cddr
(cddr (list 1 2 3 4))
---
(3 4)

== list constructor

-- list creates list
(list 1 2 3)
---
(1 2 3)

-- list with single element
(list 42)
---
(42)

-- empty list
(null? (list))
---
t

== pair? / null?

-- pair? on list
(pair? (list 1 2))
---
t

-- pair? on cons
(pair? (cons 1 2))
---
t

-- pair? on number
(null? (pair? 42))
---
t

-- pair? on nil
(null? (pair? ()))
---
t

-- null? on empty
(null? ())
---
t

-- null? on non-empty
(null? (null? (list 1)))
---
t

== list?

-- proper list
(list? (list 1 2 3))
---
t

-- empty list
(list? ())
---
t

-- dotted pair
(null? (list? (cons 1 2)))
---
t

-- non-list
(null? (list? 42))
---
t

== length

-- empty list
(length ())
---
0

-- non-empty list
(length (list 1 2 3))
---
3

-- single element
(length (list 42))
---
1

== append

-- appends two lists
(append (list 1 2) (list 3 4))
---
(1 2 3 4)

-- append with empty
(append () (list 1 2))
---
(1 2)

-- append empty to empty
(null? (append () ()))
---
t

== reverse

-- reverses a list
(reverse (list 1 2 3))
---
(3 2 1)

-- reverse empty
(null? (reverse ()))
---
t

-- reverse single
(reverse (list 42))
---
(42)

== list-ref

-- gets element by index
(list-ref (list 10 20 30) 1)
---
20

-- first element
(list-ref (list 10 20 30) 0)
---
10

-- last element
(list-ref (list 10 20 30) 2)
---
30

== list-tail

-- gets tail from index
(list-tail (list 1 2 3 4) 2)
---
(3 4)

-- tail from zero
(list-tail (list 1 2 3) 0)
---
(1 2 3)

== map

-- maps function over list
(define (double x) (* x 2)) (map double (list 1 2 3))
---
(2 4 6)

-- maps lambda
(map (lambda (x) (+ x 10)) (list 1 2 3))
---
(11 12 13)

-- map over empty list
(null? (map (lambda (x) x) ()))
---
t

== filter

-- filters elements
(filter (lambda (x) (> x 2)) (list 1 2 3 4 5))
---
(3 4 5)

-- filter none match
(null? (filter (lambda (x) (> x 10)) (list 1 2 3)))
---
t

-- filter all match
(filter (lambda (x) (> x 0)) (list 1 2 3))
---
(1 2 3)

== for-each

-- applies to each element
(define sum 0) (for-each (lambda (x) (set! sum (+ sum x))) (list 1 2 3)) sum
---
6

== member

-- finds symbol
(member (quote b) (list (quote a) (quote b) (quote c)))
---
(b c)

-- finds number
(member 3 (list 1 2 3 4 5))
---
(3 4 5)

-- returns false when not found
(null? (member (quote z) (list (quote a) (quote b))))
---
t

== memq

-- finds symbol
(memq (quote b) (list (quote a) (quote b) (quote c)))
---
(b c)

-- not found
(null? (memq (quote z) (list (quote a) (quote b))))
---
t

== assoc

-- finds association
(assoc (quote b) (list (list (quote a) 1) (list (quote b) 2)))
---
(b 2)

-- returns false when not found
(null? (assoc (quote z) (list (list (quote a) 1))))
---
t

== assq

-- finds by symbol
(assq (quote b) (list (list (quote a) 1) (list (quote b) 2)))
---
(b 2)

-- not found
(null? (assq (quote z) (list (list (quote a) 1))))
---
t

== apply

-- apply with built-in
(apply + (list 1 2 3))
---
6

-- apply with lambda
(apply (lambda (x y) (* x y)) (list 3 4))
---
12
