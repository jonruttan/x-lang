
== vector

-- creates a vector from arguments
(write (vector 1 2 3))
---
#(1 2 3)

-- creates a single-element vector
(write (vector 42))
---
#(42)

-- creates an empty vector
(write (vector))
---
#()

== vector indexing

-- indexes from the start
((vector 10 20 30) 1)
---
20

-- indexes first element
((vector 10 20 30) 0)
---
10

-- indexes last element
((vector 10 20 30) 2)
---
30

-- indexes from the end with negative
((vector 10 20 30) -1)
---
30

== vector?

-- returns t for a vector
(vector? (vector 1))
---
t

-- returns nil for a list
(if (vector? (list 1)) "yes" "no")
---
"no"

-- returns nil for an integer
(if (vector? 42) "yes" "no")
---
"no"

== vector-ref

-- retrieves element by index
(vector-ref (vector 10 20 30) 1)
---
20

== vector-length

-- returns the length of a vector
(vector-length (vector 1 2 3))
---
3

-- returns 0 for empty vector
(vector-length (vector))
---
0

== vector->list

-- converts a vector to a list
(vector->list (vector 1 2 3))
---
(1 2 3)

== list->vector

-- converts a list to a vector
(write (list->vector (list 4 5 6)))
---
#(4 5 6)

== make-vector

-- creates a vector of repeated values
(write (make-vector 3 0))
---
#(0 0 0)

-- creates a vector with custom fill
(write (make-vector 2 7))
---
#(7 7)
