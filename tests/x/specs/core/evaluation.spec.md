## self-evaluation

### evaluates positive integers

```scheme
99
```
---
    99

### evaluates negative integers

```scheme
-99
```
---
    -99

### evaluates string literals

```scheme
"hello"
```
---
    "hello"

### evaluates empty strings

```scheme
""
```
---
    ""

### evaluates nil

```scheme
()
```
---

### evaluates character literals

```scheme
#\a
```
---
    #\a

### evaluates #t

```scheme
#t
```
---
    #t

## symbol lookup

### binds and looks up a value

```scheme
(do (def x 42) x)
```
---
    42

### looks up in expression

```scheme
(do (def x 5) (+ x 1))
```
---
    6

### unbound symbol signals error

```scheme
(guard (e 'caught) no-such-var)
```
---
    'caught

### the error names the offending symbol

```scheme
(guard (e (symbol->str e)) no-such-var)
```
---
    "Unbound SYMBOL 'no-such-var'"

## recursive definitions

### computes fact(0)

```scheme
(do (def fact (fn (self n) (if (= n 0) 1 (* n (self (- n 1)))))) (fact 0))
```
---
    1

### computes fact(5)

```scheme
(do (def fact (fn (self n) (if (= n 0) 1 (* n (self (- n 1)))))) (fact 5))
```
---
    120

### computes fact(10)

```scheme
(do (def fact (fn (self n) (if (= n 0) 1 (* n (self (- n 1)))))) (fact 10))
```
---
    3628800

## recursive list operations

### computes length of a list

```scheme
(do (def len (fn (self xs) (if (null? xs) 0 (+ 1 (self (rest xs)))))) (len (list 1 2 3 4 5)))
```
---
    5

### computes length of empty list

```scheme
(do (def len (fn (self xs) (if (null? xs) 0 (+ 1 (self (rest xs)))))) (len (list)))
```
---
    0

### maps over a list

```scheme
(do (def map (fn (self f xs) (if (null? xs) xs (pair (f (first xs)) (self f (rest xs)))))) (map (fn (_ x) (* x x)) (list 1 2 3)))
```
---
    (1 4 9)

### appends two lists

```scheme
(do (def append (fn (self a b) (if (null? a) b (pair (first a) (self (rest a) b))))) (append (list 1 2) (list 3 4)))
```
---
    (1 2 3 4)

## higher-order recursion

### folds a list

```scheme
(do (def fold (fn (self f acc xs) (if (null? xs) acc (self f (f acc (first xs)) (rest xs))))) (fold (fn (_ a b) (+ a b)) 0 (list 1 2 3 4 5)))
```
---
    15

### filters a list

```scheme
(do (def filter (fn (self p xs) (if (null? xs) xs (if (p (first xs)) (pair (first xs) (self p (rest xs))) (self p (rest xs)))))) (filter (fn (_ x) (= x 3)) (list 1 2 3 4 3)))
```
---
    (3 3)
