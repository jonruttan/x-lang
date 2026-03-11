
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

-- vector? on non-vector
(null? (vector? 42))
---
t

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

-- vector-length
(vector-length (vector 1 2 3))
---
3

-- vector-length empty
(vector-length (vector))
---
0

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

== make-vector

-- make-vector with fill
(vector->list (make-vector 3 0))
---
(0 0 0)

-- make-vector with value
(vector-ref (make-vector 5 42) 3)
---
42
