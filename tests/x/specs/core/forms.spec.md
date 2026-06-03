## lit

### returns a symbol

```scheme
(lit a)
```
---
    (lit a)

### returns a list

```scheme
(lit (a b c))
```
---
    ((lit a) (lit b) (lit c))

### returns a nested list

```scheme
(lit (1 (2 3)))
```
---
    (1 (2 3))

## pair

### creates a dotted pair

```scheme
(pair 1 2)
```
---
    (1 . 2)

### creates a list when rest is nil

```scheme
(pair 1 (lit ()))
```
---
    (1)

### prepends to a list

```scheme
(pair 1 (lit (2 3)))
```
---
    (1 2 3)

## first

### returns first of a pair

```scheme
(first (pair 1 2))
```
---
    1

### returns first of a list

```scheme
(first (lit (a b c)))
```
---
    (lit a)

## rest

### returns second of a pair

```scheme
(rest (pair 1 2))
```
---
    2

### returns rest of a list

```scheme
(rest (lit (a b c)))
```
---
    ((lit b) (lit c))

## list

### creates a list

```scheme
(list 1 2 3)
```
---
    (1 2 3)

### evaluates arguments

```scheme
(list (+ 1 2) (* 3 4))
```
---
    (3 12)

### returns nil for empty list

```scheme
(list)
```
---

## def

### binds a value

```scheme
(do (def x 42) x)
```
---
    42

### binds and uses in expression

```scheme
(do (def x 5) (+ x 1))
```
---
    6

## set

### mutates a binding

```scheme
(do (def x 1) (set! x 2) x)
```
---
    2

### returns the new value

```scheme
(do (def x 1) (set! x 42))
```
---
    42

## if

### takes then branch for non-nil

```scheme
(if #t 1 2)
```
---
    1

### takes else branch for nil

```scheme
(if #f 1 2)
```
---
    2

### works with eq? true case

```scheme
(if (eq? (lit a) (lit a)) 10 20)
```
---
    10

### returns nil when false and no else

```scheme
(if (= 1 2) 42)
```
---

### returns then when true and no else

```scheme
(if (= 1 1) 42)
```
---
    42

## do

### returns last form

```scheme
(do 1 2 3)
```
---
    3

### evaluates all forms

```scheme
(do (def a 1) (def b 2) (+ a b))
```
---
    3

### returns nil for empty do

```scheme
(do)
```
---

## match

### returns first matching branch

```scheme
(match ((= 1 1) 10) ((= 2 2) 20))
```
---
    10

### returns later matching branch

```scheme
(match ((= 1 2) 10) ((= 2 2) 20))
```
---
    20

### supports else with #t

```scheme
(match ((= 1 2) 10) (#t 30))
```
---
    30

### returns nil when no match

```scheme
(match ((= 1 2) 10) ((= 3 4) 20))
```
---

### works with comparisons

```scheme
(do (def x 5) (match ((< x 0) (lit neg)) ((= x 0) (lit zero)) (#t (lit pos))))
```
---
    (lit pos)

## let

### binds a single variable

```scheme
(let ((x 42)) x)
```
---
    42

### binds multiple variables

```scheme
(let ((x 3) (y 4)) (+ x y))
```
---
    7

### evaluates binding expressions

```scheme
(let ((x (+ 1 2)) (y (* 3 4))) (+ x y))
```
---
    15

### does not pollute outer scope

```scheme
(do (def x 1) (let ((x 2)) x) x)
```
---
    1

### supports multiple body forms

```scheme
(let ((x 1)) (+ x 1) (+ x 2))
```
---
    3

### nests correctly

```scheme
(let ((x 1)) (let ((y 2)) (+ x y)))
```
---
    3

## apply

### applies to arg list

```scheme
(apply + (list 1 2 3))
```
---
    6

### with one prefix arg

```scheme
(apply + 10 (list 1 2))
```
---
    13

### with two prefix args

```scheme
(apply + 1 2 (list 3 4))
```
---
    10

### with closure

```scheme
(apply (fn (_ a b c) (+ a (* b c))) (list 2 3 4))
```
---
    14

### with prefix and closure

```scheme
(apply (fn (_ a b c) (+ a (* b c))) 2 (list 3 4))
```
---
    14

### with empty tail list

```scheme
(apply + 1 2 ())
```
---
    3

## list call

### indexes first element

```scheme
((list 1 2 3) 0)
```
---
    1

### indexes last element

```scheme
((list 1 2 3) 2)
```
---
    3

### indexes via binding

```scheme
(do (def l (list 10 20 30)) (l 1))
```
---
    20

### negative index from end

```scheme
((list 1 2 3) -1)
```
---
    3

### slices from middle

```scheme
((list 1 2 3 4 5) 1 3)
```
---
    (2 3 4)

### slices from start

```scheme
((list 1 2 3 4 5) 0 2)
```
---
    (1 2)

