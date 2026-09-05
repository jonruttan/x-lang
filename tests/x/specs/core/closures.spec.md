# @weight 1
## fn

### creates a procedure

```x
(fn (_ x) x)
```
---
    #<fn>

### creates a procedure with empty params

```x
(fn (_ ) 42)
```
---
    #<fn>

### applies identity

```x
((fn (_ x) x) 7)
```
---
    7

### applies with two params

```x
((fn (_ x y) (+ x y)) 3 4)
```
---
    7

### applies with empty params

```x
((fn (_ ) 42))
```
---
    42

### supports multiple body forms

```x
((fn (_ x) (+ x 1) (+ x 2)) 10)
```
---
    12

## closures

### captures enclosing environment

```x
(do (def make-adder (fn (_ x) (fn (_ y) (+ x y)))) ((make-adder 5) 3))
```
---
    8

### captures and returns value

```x
(do (def f (do (def a 10) (fn (_ ) a))) (f))
```
---
    10

## counter (closure + mutation)

### increments on each call

```x
(do (def counter (do (def n 0) (fn (_ ) (do (set! n (+ n 1)) n)))) (do (counter) (counter) (counter)))
```
---
    3

### binds variadic args as the self-passed list

```x
(rest ((fn args args) 1 2))
```
---
    (1 2)

### variadic args survive the binding frame

```x
(rest (((fn args (fn (_) args)) 7)))
```
---
    (7)

## op

### creates an operative

```x
(def my-op (op (x) e x)) my-op
```
---
    #<op>

### receives unevaluated args

```x
(do (def my-op (op (x) e x)) (def a 42) (my-op a))
```
---
    'a

### can eval args explicitly

```x
(do (def my-op (op (x) e (eval x e))) (def a 42) (my-op a))
```
---
    42

### binds env-param to caller env

```x
(do (def my-op (op (x) e (eval x e))) (def a 42) (my-op a))
```
---
    42

### supports variadic args

```x
(do (def my-op (op args e (first args))) (my-op 1 2 3))
```
---
    1

### supports dotted formals

```x
(do (def my-op (op (x . rest) e (list x rest))) (my-op 1 2 3))
```
---
    (1 (2 3))

## op special forms

### implements when

```x
(do (def %when (op (test . body) e (if (eval test e) (eval (pair 'do body) e)))) (%when (= 1 1) (+ 10 20)))
```
---
    30

### when returns nil on false

```x
(do (def %when (op (test . body) e (if (eval test e) (eval (pair 'do body) e)))) (%when (= 1 2) (+ 10 20)))
```
---

### implements define sugar

```x
(do (def define (op (name-or-form . body) e (if (pair? name-or-form) (tail-eval (list 'def (first name-or-form) (pair 'fn (pair (pair '_ (rest name-or-form)) body))) e) (tail-eval (list 'def name-or-form (first body)) e)))) (define (square x) (* x x)) (square 5))
```
---
    25

### define sugar with simple binding

```x
(do (def define (op (name-or-form . body) e (if (pair? name-or-form) (tail-eval (list 'def (first name-or-form) (pair 'fn (pair (rest name-or-form) body))) e) (tail-eval (list 'def name-or-form (first body)) e)))) (define pi 314) pi)
```
---
    314

## wrap

### wraps an operative into an applicative

```x
(procedure? (wrap (op (x) e x)))
```
---
    #t

### wrapped operative evaluates args

```x
(do (def my-op (op (x) e x)) (def my-fn (wrap my-op)) (my-fn (+ 1 2)))
```
---
    3

### wrapped fn stays applicative

```x
((wrap (fn (_ x) (* x 2))) 5)
```
---
    10

## unwrap

### extracts underlying combiner

```x
(do (def my-op (op (x) e x)) (def my-fn (wrap my-op)) ((unwrap my-fn) (+ 1 2)))
```
---
    ('+ 1 2)

### unwrapped applicative receives unevaluated args

```x
(do (def my-op (op (x) e x)) ((unwrap (wrap my-op)) (+ 1 2)))
```
---
    ('+ 1 2)

## apply

### applies a function to a list of args

```x
(apply (fn (_ x y) (+ x y)) (list 3 4))
```
---
    7

### applies with empty args

```x
(apply (fn (_ ) 42) (list))
```
---
    42

### applies a named function

```x
(do (def add (fn (_ a b) (+ a b))) (apply add (list 10 20)))
```
---
    30

### applies with computed arg list

```x
(do (def f (fn (_ x) (* x x))) (apply f (list (+ 2 3))))
```
---
    25

### applies a recursive function

```x
(do (def fact (fn (self n) (if (= n 0) 1 (* n (self (- n 1)))))) (apply fact (list 5)))
```
---
    120

## eval

### evaluates a quoted expression

```x
(eval (lit (+ 1 2)))
```
---
    3

### evaluates a self-evaluating form

```x
(eval 42)
```
---
    42

### evaluates in current environment

```x
(do (def x 10) (eval (lit (+ x 1))))
```
---
    11

### evaluates a constructed expression

```x
(eval (pair '+ (list 3 4)))
```
---
    7

### evaluates nested eval

```x
(eval (lit (eval '99)))
```
---
    99

### evaluates in given environment

```x
(do (def x 10) (let ((x 20)) (eval 'x)))
```
---
    20

### eval without env uses current env

```x
(eval (lit (+ 1 2)))
```
---
    3

## arity

### too few args: missing params bind to nil (not a crash)

```x
((fn (_ a b) (list a b)) 1)
```
---
    (1 ())

### a missing param is usable as nil

```x
((fn (_ a b) (null? b)) 1)
```
---
    #t

### surplus args are ignored once params run out

```x
((fn (_ a) a) 1 2 3)
```
---
    1

