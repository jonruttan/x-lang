# @weight 1
## identity

### returns its argument

```x
(Fn identity 42)
```
---
    42

### returns a list

```x
(Fn identity (list 1 2))
```
---
    (1 2)

## const

### returns a constant function

```x
((Fn const 5) 99)
```
---
    5

## compose

### composes two functions

```x
((Fn compose (method-ref Num inc) (method-ref Num inc)) 3)
```
---
    5

### applies right-to-left

```x
((Fn compose (fn (_ x) (* x 2)) (method-ref Num inc)) 3)
```
---
    8

## pipe

### pipes two functions left-to-right

```x
((Fn pipe (method-ref Num inc) (fn (_ x) (* x 2))) 3)
```
---
    8

## curry

### partially applies first argument

```x
((Fn curry + 10) 5)
```
---
    15

## flip

### swaps argument order

```x
((Fn flip -) 3 10)
```
---
    7

## tap

### returns original value

```x
((Fn tap (fn (_ x) x)) 42)
```
---
    42

## complement

### negates a predicate

```x
((Fn complement (method-ref Num even?)) 3)
```
---
    #t

### negates a true result

```x
(if ((Fn complement (method-ref Num even?)) 4) "odd" "even")
```
---
    "even"

## partial

### partially applies one argument

```x
((Fn partial * 3) 4)
```
---
    12

### partially applies with subtract

```x
((Fn partial - 100) 30)
```
---
    70

## juxt

### applies multiple functions

```x
((Fn juxt (method-ref Num inc) (method-ref Num dec)) 5)
```
---
    (6 4)

## both

### returns #t when both pass

```x
((Fn both (method-ref Num positive?) (method-ref Num even?)) 4)
```
---
    #t

### returns nil when one fails

```x
(if ((Fn both (method-ref Num positive?) (method-ref Num even?)) 3) "y" "n")
```
---
    "n"

## either

### returns #t when one passes

```x
((Fn either (method-ref Num positive?) (method-ref Num even?)) -2)
```
---
    #t

### returns nil when both fail

```x
(if ((Fn either (method-ref Num positive?) (method-ref Num even?)) -3) "y" "n")
```
---
    "n"

## all-pass

### all predicates pass

```x
((Fn all-pass (list (method-ref Num positive?) (method-ref Num even?))) 4)
```
---
    #t

### fails when one fails

```x
(if ((Fn all-pass (list (method-ref Num positive?) (method-ref Num even?))) 3) "y" "n")
```
---
    "n"

## any-pass

### one predicate passes

```x
((Fn any-pass (list (method-ref Num negative?) (method-ref Num even?))) 4)
```
---
    #t

### fails when all fail

```x
(if ((Fn any-pass (list (method-ref Num negative?) (method-ref Num even?))) 3) "y" "n")
```
---
    "n"


## label

A callable is told by its type and, for a wrapped combiner, the wrap flag;
anything else answers nil, a value that is callable only through its type's
call handler included.

### tells a closure, an operative, a wrapped combiner and a primitive apart

```x
(list (Fn label (fn (_ x) x))
      (Fn label (op (x) e x))
      (Fn label (wrap (op (x) e x)))
      (Fn label first)
      (Fn label (unwrap (wrap (op (x) e x)))))
```
---
    ('fn 'op 'wrap 'prim 'op)

### answers () for a value that is none of them

```x
(list (Fn label 42) (Fn label "s") (Fn label (list 1)) (Fn label ()) (Fn label (Vector of 1 2)))
```
---
    (() () () () ())

## params

### a closure's formals, self first

```x
(Fn params (fn (self a b) (+ a b)))
```
---
    ('self 'a 'b)

### a variadic closure's single symbol

```x
(Fn params (fn args args))
```
---
    'args

### an operative's formals, dotted as written

```x
(Fn params (op (x . more) e x))
```
---
    ('x . 'more)

### () for a wrapped combiner, a primitive, or a non-callable

```x
(list (Fn params (wrap (op (x) e x))) (Fn params first) (Fn params 42))
```
---
    (() () ())

## body

### a closure's body forms, in order, as written

```x
(Fn body (fn (_ n) (+ n 1) (* n 2)))
```
---
    (('+ 'n 1) ('* 'n 2))

### an operative's body forms

```x
(Fn body (op (x) e (eval x e)))
```
---
    (('eval 'x 'e))

### () for a wrapped combiner or a primitive

```x
(list (Fn body (wrap (op () e 1))) (Fn body first))
```
---
    (() ())

## env

The environment a callable was made in is a first-class value, one pair
`(bindings . parent)`, so `eval` resolves names through it and `first`
reaches the frame's bindings.

### a closure resolves its free names through the environment it was made in

```x
(eval 'k (Fn env ((fn (_ k) (fn (_) k)) 7)))
```
---
    7

### the frame's bindings are the environment's first

```x
(let ((e (Fn env ((fn (_ k) (fn (_) k)) 7))))
  (list (first (first (first e))) (eval 'k e)))
```
---
    ('k 7)

### an operative answers its static environment

```x
(eval 'k (Fn env ((fn (_ k) (op () e k)) 9)))
```
---
    9

### () for a wrapped combiner or a primitive

```x
(list (Fn env (wrap (op () e 1))) (Fn env first))
```
---
    (() ())
