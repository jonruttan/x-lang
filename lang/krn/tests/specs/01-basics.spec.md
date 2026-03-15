## $define! simple

### binds a value

```scheme
($define! x 42) x
```
---
    42

### binds a string

```scheme
($define! greeting "hello") greeting
```
---
    "hello"

### binds an expression result

```scheme
($define! sum (+ 1 2)) sum
```
---
    3

## $define! function sugar

### defines and calls operative-style function

```scheme
($define! (square x) (* x x)) (square 5)
```
---
    25

### multi-body function

```scheme
($define! (f x) ($define! y (+ x 1)) (* x y)) (f 3)
```
---
    12

## $vau

### is an alias for op

```scheme
(def my-op ($vau (x) e (+ 1 (eval x e)))) (my-op (+ 2 3))
```
---
    6

## $lambda

### creates an applicative

```scheme
($define! double ($lambda (x) (* x 2))) (double 5)
```
---
    10

### applicative evaluates args

```scheme
($define! add1 ($lambda (x) (+ x 1))) (add1 (+ 2 3))
```
---
    6

## $sequence

### evaluates in order

```scheme
($sequence ($define! a 1) ($define! b 2) (+ a b))
```
---
    3

## boolean constants

### #t is t

```scheme
#t
```
---
    #t

### #f is distinct from nil

```scheme
(not (null? #f))
```
---
    #t

