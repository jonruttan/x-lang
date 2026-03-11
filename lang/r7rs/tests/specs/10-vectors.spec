
== vector basics

-- vector constructor
(vector 1 2 3)
---
#(1 2 3)

-- vector? on vector
(vector? (vector 1 2))
---
t

-- vector? on list
(null? (vector? (list 1 2)))
---
t

-- vector? on number
(null? (vector? 42))
---
t

-- vector empty
(vector)
---
#()

== vector access

-- vector-ref first
(vector-ref (vector 10 20 30) 0)
---
10

-- vector-ref middle
(vector-ref (vector 10 20 30) 1)
---
20

-- vector-ref last
(vector-ref (vector 10 20 30) 2)
---
30

-- vector-length three
(vector-length (vector 1 2 3))
---
3

-- vector-length empty
(vector-length (vector))
---
0

-- vector-length one
(vector-length (vector 42))
---
1

== make-vector

-- make-vector with fill
(vector->list (make-vector 3 0))
---
(0 0 0)

-- make-vector with value
(vector-ref (make-vector 5 42) 3)
---
42

-- make-vector length
(vector-length (make-vector 4 0))
---
4

== vector conversion

-- vector->list
(vector->list (vector 1 2 3))
---
(1 2 3)

-- vector->list empty
(null? (vector->list (vector)))
---
t

-- list->vector
(list->vector (list 1 2 3))
---
#(1 2 3)

-- list->vector empty
(list->vector ())
---
#()

-- roundtrip list->vector->list
(vector->list (list->vector (list 4 5 6)))
---
(4 5 6)

== vector-copy

-- vector-copy basic
(vector-copy (vector 1 2 3))
---
#(1 2 3)

-- vector-copy is equal
(equal? (vector->list (vector-copy (vector 1 2))) (list 1 2))
---
t

== vector-append

-- vector-append two
(vector-append (vector 1 2) (vector 3 4))
---
#(1 2 3 4)

-- vector-append empty
(vector-append (vector) (vector 1 2))
---
#(1 2)

-- vector-append nested
(vector-append (vector 1) (vector-append (vector 2) (vector 3)))
---
#(1 2 3)

== vector-map

-- vector-map double
(vector-map (lambda (x) (* x 2)) (vector 1 2 3))
---
#(2 4 6)

-- vector-map increment
(vector-map (lambda (x) (+ x 10)) (vector 1 2 3))
---
#(11 12 13)

== vector-for-each

-- vector-for-each accumulates
(define sum 0) (vector-for-each (lambda (x) (set! sum (+ sum x))) (vector 1 2 3)) sum
---
6
