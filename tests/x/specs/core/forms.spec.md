# @weight 1
## lit

### returns a symbol

```x
(lit a)
```
---
    'a

### returns a list

```x
(lit (a b c))
```
---
    ('a 'b 'c)

### returns a nested list

```x
(lit (1 (2 3)))
```
---
    (1 (2 3))

## pair

### creates a dotted pair

```x
(pair 1 2)
```
---
    (1 . 2)

### creates a list when rest is nil

```x
(pair 1 (lit ()))
```
---
    (1)

### prepends to a list

```x
(pair 1 (lit (2 3)))
```
---
    (1 2 3)

## first

### returns first of a pair

```x
(first (pair 1 2))
```
---
    1

### returns first of a list

```x
(first (lit (a b c)))
```
---
    'a

## rest

### returns second of a pair

```x
(rest (pair 1 2))
```
---
    2

### returns rest of a list

```x
(rest (lit (a b c)))
```
---
    ('b 'c)

## list

### creates a list

```x
(list 1 2 3)
```
---
    (1 2 3)

### evaluates arguments

```x
(list (+ 1 2) (* 3 4))
```
---
    (3 12)

### returns nil for empty list

```x
(list)
```
---

## def

### binds a value

```x
(do (def x 42) x)
```
---
    42

### binds and uses in expression

```x
(do (def x 5) (+ x 1))
```
---
    6

## set

### mutates a binding

```x
(do (def x 1) (set! x 2) x)
```
---
    2

### returns the new value

```x
(do (def x 1) (set! x 42))
```
---
    42

## if

### takes then branch for non-nil

```x
(if #t 1 2)
```
---
    1

### takes else branch for nil

```x
(if #f 1 2)
```
---
    2

### works with eq? true case

```x
(if (eq? (lit a) (lit a)) 10 20)
```
---
    10

### returns nil when false and no else

```x
(if (= 1 2) 42)
```
---

### returns then when true and no else

```x
(if (= 1 1) 42)
```
---
    42

## do

### returns last form

```x
(do 1 2 3)
```
---
    3

### rejects a dotted body instead of walking it

```x
(do 1 2 . 3)
```
---
    Error: do: improper body (dotted tail)

### rejects a non-list body

```x
(begin . 3)
```
---
    Error: do: improper body (dotted tail)

### evaluates all forms

```x
(do (def a 1) (def b 2) (+ a b))
```
---
    3

### returns nil for empty do

```x
(do)
```
---

## match

### returns first matching branch

```x
(match ((= 1 1) 10) ((= 2 2) 20))
```
---
    10

### returns later matching branch

```x
(match ((= 1 2) 10) ((= 2 2) 20))
```
---
    20

### supports else with #t

```x
(match ((= 1 2) 10) (#t 30))
```
---
    30

### returns nil when no match

```x
(match ((= 1 2) 10) ((= 3 4) 20))
```
---

### works with comparisons

```x
(do (def x 5) (match ((< x 0) (lit neg)) ((= x 0) (lit zero)) (#t (lit pos))))
```
---
    'pos

## let

### binds a single variable

```x
(let ((x 42)) x)
```
---
    42

### binds multiple variables

```x
(let ((x 3) (y 4)) (+ x y))
```
---
    7

### evaluates binding expressions

```x
(let ((x (+ 1 2)) (y (* 3 4))) (+ x y))
```
---
    15

### does not pollute outer scope

```x
(do (def x 1) (let ((x 2)) x) x)
```
---
    1

### supports multiple body forms

```x
(let ((x 1)) (+ x 1) (+ x 2))
```
---
    3

### nests correctly

```x
(let ((x 1)) (let ((y 2)) (+ x y)))
```
---
    3

## apply

### applies to arg list

```x
(apply + (list 1 2 3))
```
---
    6

### with one prefix arg

```x
(apply + 10 (list 1 2))
```
---
    13

### with two prefix args

```x
(apply + 1 2 (list 3 4))
```
---
    10

### with closure

```x
(apply (fn (_ a b c) (+ a (* b c))) (list 2 3 4))
```
---
    14

### with prefix and closure

```x
(apply (fn (_ a b c) (+ a (* b c))) 2 (list 3 4))
```
---
    14

### with empty tail list

```x
(apply + 1 2 ())
```
---
    3

## list call

### indexes first element

```x
((list 1 2 3) 0)
```
---
    1

### indexes last element

```x
((list 1 2 3) 2)
```
---
    3

### indexes via binding

```x
(do (def l (list 10 20 30)) (l 1))
```
---
    20

### negative index from end

```x
((list 1 2 3) -1)
```
---
    3

### slices from middle

```x
((list 1 2 3 4 5) 1 3)
```
---
    (2 3 4)

### slices from start

```x
((list 1 2 3 4 5) 0 2)
```
---
    (1 2)

