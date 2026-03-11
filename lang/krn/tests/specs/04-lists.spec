
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

== length

-- empty list
(length ())
---
0

-- non-empty list
(length (list 1 2 3))
---
3

== append

-- appends two lists
(append (list 1 2) (list 3 4))
---
(1 2 3 4)

-- append with empty
(append () (list 1 2))
---
(1 2)

== reverse

-- reverses a list
(reverse (list 1 2 3))
---
(3 2 1)

-- reverse empty
(null? (reverse ()))
---
t

== list-ref

-- gets element by index
(list-ref (list 10 20 30) 1)
---
20

-- first element
(list-ref (list 10 20 30) 0)
---
10

== map

-- maps function over list
($define! double ($lambda (x) (* x 2))) (map double (list 1 2 3))
---
(2 4 6)

-- maps lambda
(map ($lambda (x) (+ x 10)) (list 1 2 3))
---
(11 12 13)

== filter

-- filters elements
(filter ($lambda (x) (> x 2)) (list 1 2 3 4 5))
---
(3 4 5)

-- filter none match
(null? (filter ($lambda (x) (> x 10)) (list 1 2 3)))
---
t

== for-each

-- applies to each element
($define! sum 0) (for-each ($lambda (x) (set sum (+ sum x))) (list 1 2 3)) sum
---
6

== member

-- finds element
(member (quote b) (list (quote a) (quote b) (quote c)))
---
(b c)

-- returns false when not found
(null? (member (quote z) (list (quote a) (quote b))))
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
