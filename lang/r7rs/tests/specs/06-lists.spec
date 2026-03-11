
== pair basics

-- cons creates pair
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

-- pair? on pair
(pair? (cons 1 2))
---
t

-- pair? on list
(pair? (list 1 2))
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

== list constructor

-- list creates list
(list 1 2 3)
---
(1 2 3)

-- list single element
(list 42)
---
(42)

-- list empty
(null? (list))
---
t

== list predicates

-- list? on proper list
(list? (list 1 2 3))
---
t

-- list? on empty
(list? ())
---
t

-- list? on dotted pair
(null? (list? (cons 1 2)))
---
t

-- list? on atom
(null? (list? 42))
---
t

-- null? on nil
(null? ())
---
t

-- null? on list
(null? (null? (list 1)))
---
t

== make-list

-- make-list with fill
(make-list 3 0)
---
(0 0 0)

-- make-list with value
(make-list 4 (quote x))
---
(x x x x)

-- make-list zero length
(null? (make-list 0 1))
---
t

== list operations

-- length
(length (list 1 2 3))
---
3

-- length empty
(length ())
---
0

-- append two lists
(append (list 1 2) (list 3 4))
---
(1 2 3 4)

-- append empty
(null? (append () ()))
---
t

-- append nested
(append (list 1) (append (list 2) (list 3)))
---
(1 2 3)

-- reverse
(reverse (list 1 2 3))
---
(3 2 1)

-- reverse empty
(null? (reverse ()))
---
t

== list access

-- list-ref first
(list-ref (list 10 20 30) 0)
---
10

-- list-ref last
(list-ref (list 10 20 30) 2)
---
30

-- list-tail
(list-tail (list 1 2 3 4) 2)
---
(3 4)

-- list-tail zero
(list-tail (list 1 2 3) 0)
---
(1 2 3)

== list-copy

-- list-copy proper list
(list-copy (list 1 2 3))
---
(1 2 3)

-- list-copy is equal
(equal? (list-copy (list 1 2 3)) (list 1 2 3))
---
t

-- list-copy empty
(null? (list-copy ()))
---
t

== member

-- member finds element
(member 3 (list 1 2 3 4 5))
---
(3 4 5)

-- member not found
(null? (member 6 (list 1 2 3)))
---
t

== memq

-- memq finds symbol
(memq (quote b) (list (quote a) (quote b) (quote c)))
---
(b c)

-- memq not found
(null? (memq (quote z) (list (quote a) (quote b))))
---
t

== assoc

-- assoc finds key
(assoc (quote b) (list (list (quote a) 1) (list (quote b) 2) (list (quote c) 3)))
---
(b 2)

-- assoc not found
(null? (assoc (quote z) (list (list (quote a) 1))))
---
t

== assq

-- assq finds key
(assq (quote b) (list (list (quote a) 1) (list (quote b) 2)))
---
(b 2)

-- assq not found
(null? (assq (quote z) (list (list (quote a) 1))))
---
t
