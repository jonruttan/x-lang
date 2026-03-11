
== lit

-- returns a symbol
(lit a)
---
a

-- returns a list
(lit (a b c))
---
(a b c)

-- returns a nested list
(lit (1 (2 3)))
---
(1 (2 3))

== pair

-- creates a dotted pair
(pair 1 2)
---
(1 . 2)

-- creates a list when rest is nil
(pair 1 (lit ()))
---
(1)

-- prepends to a list
(pair 1 (lit (2 3)))
---
(1 2 3)

== first

-- returns first of a pair
(first (pair 1 2))
---
1

-- returns first of a list
(first (lit (a b c)))
---
a

== rest

-- returns second of a pair
(rest (pair 1 2))
---
2

-- returns rest of a list
(rest (lit (a b c)))
---
(b c)

== list

-- creates a list
(list 1 2 3)
---
(1 2 3)

-- evaluates arguments
(list (+ 1 2) (* 3 4))
---
(3 12)

-- returns nil for empty list
(list)
---


== def

-- binds a value
(do (def x 42) x)
---
42

-- binds and uses in expression
(do (def x 5) (+ x 1))
---
6

== set

-- mutates a binding
(do (def x 1) (set x 2) x)
---
2

-- returns the new value
(do (def x 1) (set x 42))
---
42

== if

-- takes then branch for non-nil
(if (lit t) 1 2)
---
1

-- takes else branch for nil
(if (lit ()) 1 2)
---
2

-- works with eq? true case
(if (eq? (lit a) (lit a)) 10 20)
---
10

-- returns nil when false and no else
(if (= 1 2) 42)
---


-- returns then when true and no else
(if (= 1 1) 42)
---
42

== do

-- returns last form
(do 1 2 3)
---
3

-- evaluates all forms
(do (def a 1) (def b 2) (+ a b))
---
3

-- returns nil for empty do
(do)
---


== match

-- returns first matching branch
(match ((= 1 1) 10) ((= 2 2) 20))
---
10

-- returns later matching branch
(match ((= 1 2) 10) ((= 2 2) 20))
---
20

-- supports else with t
(match ((= 1 2) 10) (t 30))
---
30

-- returns nil when no match
(match ((= 1 2) 10) ((= 3 4) 20))
---


-- works with comparisons
(do (def x 5) (match ((< x 0) (lit neg)) ((= x 0) (lit zero)) (t (lit pos))))
---
pos

== let

-- binds a single variable
(let ((x 42)) x)
---
42

-- binds multiple variables
(let ((x 3) (y 4)) (+ x y))
---
7

-- evaluates binding expressions
(let ((x (+ 1 2)) (y (* 3 4))) (+ x y))
---
15

-- does not pollute outer scope
(do (def x 1) (let ((x 2)) x) x)
---
1

-- supports multiple body forms
(let ((x 1)) (+ x 1) (+ x 2))
---
3

-- nests correctly
(let ((x 1)) (let ((y 2)) (+ x y)))
---
3

== apply

-- applies to arg list
(apply + (list 1 2 3))
---
6

-- with one prefix arg
(apply + 10 (list 1 2))
---
13

-- with two prefix args
(apply + 1 2 (list 3 4))
---
10

-- with closure
(apply (fn (a b c) (+ a (* b c))) (list 2 3 4))
---
14

-- with prefix and closure
(apply (fn (a b c) (+ a (* b c))) 2 (list 3 4))
---
14

-- with empty tail list
(apply + 1 2 ())
---
3

== list call

-- indexes first element
((list 1 2 3) 0)
---
1

-- indexes last element
((list 1 2 3) 2)
---
3

-- indexes via binding
(do (def l (list 10 20 30)) (l 1))
---
20

-- negative index from end
((list 1 2 3) -1)
---
3

-- slices from middle
((list 1 2 3 4 5) 1 3)
---
(2 3 4)

-- slices from start
((list 1 2 3 4 5) 0 2)
---
(1 2)
