
== fn

-- creates a procedure
(fn (x) x)
---
#<fn>

-- creates a procedure with empty params
(fn () 42)
---
#<fn>

-- applies identity
((fn (x) x) 7)
---
7

-- applies with two params
((fn (x y) (+ x y)) 3 4)
---
7

-- applies with empty params
((fn () 42))
---
42

-- supports multiple body forms
((fn (x) (+ x 1) (+ x 2)) 10)
---
12

== closures

-- captures enclosing environment
(do (def make-adder (fn (x) (fn (y) (+ x y)))) ((make-adder 5) 3))
---
8

-- captures and returns value
(do (def f (do (def a 10) (fn () a))) (f))
---
10

== counter (closure + mutation)

-- increments on each call
(do (def counter (do (def n 0) (fn () (do (set n (+ n 1)) n)))) (do (counter) (counter) (counter)))
---
3

== op

-- creates an operative
(def my-op (op (x) e x)) my-op
---
#<op>

-- receives unevaluated args
(do (def my-op (op (x) e x)) (def a 42) (my-op a))
---
a

-- can eval args explicitly
(do (def my-op (op (x) e (eval x))) (def a 42) (my-op a))
---
42

-- binds env-param to caller env
(do (def my-op (op (x) e (eval x e))) (def a 42) (my-op a))
---
42

-- supports variadic args
(do (def my-op (op args e (first args))) (my-op 1 2 3))
---
1

-- supports dotted formals
(do (def my-op (op (x . rest) e (list x rest))) (my-op 1 2 3))
---
(1 (2 3))

== op special forms

-- implements when
(do (def when (op (test . body) e (if (eval test e) (eval (pair (lit do) body) e)))) (when (= 1 1) (+ 10 20)))
---
30

-- when returns nil on false
(do (def when (op (test . body) e (if (eval test e) (eval (pair (lit do) body) e)))) (when (= 1 2) (+ 10 20)))
---


-- implements define sugar
(do (def define (op (name-or-form . body) e (if (pair? name-or-form) (eval (list (lit def) (first name-or-form) (pair (lit fn) (pair (rest name-or-form) body)))) (eval (list (lit def) name-or-form (first body)))))) (define (square x) (* x x)) (square 5))
---
25

-- define sugar with simple binding
(do (def define (op (name-or-form . body) e (if (pair? name-or-form) (eval (list (lit def) (first name-or-form) (pair (lit fn) (pair (rest name-or-form) body)))) (eval (list (lit def) name-or-form (first body)))))) (define pi 314) pi)
---
314

== wrap

-- wraps an operative into an applicative
(procedure? (wrap (op (x) e x)))
---
t

-- wrapped operative evaluates args
(do (def my-op (op (x) e x)) (def my-fn (wrap my-op)) (my-fn (+ 1 2)))
---
3

-- wrapped fn stays applicative
((wrap (fn (x) (* x 2))) 5)
---
10

== unwrap

-- extracts underlying combiner
(do (def my-op (op (x) e x)) (def my-fn (wrap my-op)) ((unwrap my-fn) (+ 1 2)))
---
(+ 1 2)

-- unwrapped applicative receives unevaluated args
(do (def my-op (op (x) e x)) ((unwrap (wrap my-op)) (+ 1 2)))
---
(+ 1 2)

== apply

-- applies a function to a list of args
(apply (fn (x y) (+ x y)) (list 3 4))
---
7

-- applies with empty args
(apply (fn () 42) (list))
---
42

-- applies a named function
(do (def add (fn (a b) (+ a b))) (apply add (list 10 20)))
---
30

-- applies with computed arg list
(do (def f (fn (x) (* x x))) (apply f (list (+ 2 3))))
---
25

-- applies a recursive function
(do (def fact (fn (n) (if (= n 0) 1 (* n (fact (- n 1)))))) (apply fact (list 5)))
---
120

== eval

-- evaluates a quoted expression
(eval (lit (+ 1 2)))
---
3

-- evaluates a self-evaluating form
(eval 42)
---
42

-- evaluates in current environment
(do (def x 10) (eval (lit (+ x 1))))
---
11

-- evaluates a constructed expression
(eval (pair (lit +) (list 3 4)))
---
7

-- evaluates nested eval
(eval (lit (eval (lit 99))))
---
99

-- evaluates in given environment
(do (def x 10) (let ((x 20)) (eval (lit x))))
---
20

-- eval without env uses current env
(eval (lit (+ 1 2)))
---
3
