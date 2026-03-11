
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

-- returns a constant function
((const 5) 99)
---
5

== compose

-- composes two functions
((compose inc inc) 3)
---
5

-- applies right-to-left
((compose (fn (x) (* x 2)) inc) 3)
---
8

== pipe

-- pipes two functions left-to-right
((pipe inc (fn (x) (* x 2))) 3)
---
8

== curry

-- partially applies first argument
((curry + 10) 5)
---
15

== flip

-- swaps argument order
((flip -) 3 10)
---
7

== tap

-- returns original value
((tap identity) 42)
---
42

== complement

-- negates a predicate
((complement even?) 3)
---
t

-- negates a true result
(if ((complement even?) 4) "odd" "even")
---
"even"

== partial

-- partially applies one argument
((partial * 3) 4)
---
12

-- partially applies with subtract
((partial - 100) 30)
---
70

== juxt

-- applies multiple functions
((juxt inc dec) 5)
---
(6 4)

== both

-- returns t when both pass
((both positive? even?) 4)
---
t

-- returns nil when one fails
(if ((both positive? even?) 3) "y" "n")
---
"n"

== either

-- returns t when one passes
((either positive? even?) -2)
---
t

-- returns nil when both fail
(if ((either positive? even?) -3) "y" "n")
---
"n"

== all-pass

-- all predicates pass
((all-pass (list positive? even?)) 4)
---
t

-- fails when one fails
(if ((all-pass (list positive? even?)) 3) "y" "n")
---
"n"

== any-pass

-- one predicate passes
((any-pass (list negative? even?)) 4)
---
t

-- fails when all fail
(if ((any-pass (list negative? even?)) 3) "y" "n")
---
"n"
