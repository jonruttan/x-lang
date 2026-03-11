
== $define! simple

-- binds a value
($define! x 42) x
---
42

-- binds a string
($define! greeting "hello") greeting
---
"hello"

-- binds an expression result
($define! sum (+ 1 2)) sum
---
3

== $define! function sugar

-- defines and calls operative-style function
($define! (square x) (* x x)) (square 5)
---
25

-- multi-body function
($define! (f x) ($define! y (+ x 1)) (* x y)) (f 3)
---
12

== $vau

-- is an alias for op
(def my-op ($vau (x) e (+ 1 (eval x e)))) (my-op (+ 2 3))
---
6

== $lambda

-- creates an applicative
($define! double ($lambda (x) (* x 2))) (double 5)
---
10

-- applicative evaluates args
($define! add1 ($lambda (x) (+ x 1))) (add1 (+ 2 3))
---
6

== $sequence

-- evaluates in order
($sequence ($define! a 1) ($define! b 2) (+ a b))
---
3

== boolean constants

-- #t is t
#t
---
t

-- #f is nil
(null? #f)
---
t
