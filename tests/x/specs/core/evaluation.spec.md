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

## improper call forms (#69 ruled: error / echo split)

Calling an APPLICATIVE with an improper argument list raises -- the C
argument walk (x_eval_list) guards spine cells STRUCTURALLY, by the type's
declared pair units (the same contract the collector's payload walk trusts),
so any reader personality's spine type participates and no reader/evaluator
symmetry is assumed. A NON-callable head was never a call: the form is data
and echoes back unchanged, proper or dotted. Ops receive spines raw and a
dotted param spec binds an atom tail legitimately.

Before this, (list 1 . 5) and bare-x-core (f 1.5) -- where 1.5 reads as a
dotted pair with no float module -- killed the process.

### callable head with improper args raises, catchably

```scheme
(list (guard (e (lit R)) (list 1 . 5))
      (guard (e (lit R)) ((fn (_ a) a) 1 . 5))
      (guard (e (lit R)) (eval (pair list 5))))
```
---
    ('R 'R 'R)

### the error names the fault

```scheme
(guard (e (Str8 contains? "improper argument list" (Str8 append "" e))) (list 1 . 5))
```
---
    #t

### non-callable heads echo the data form, dotted or not

```scheme
(list (1 . 2) (1 2 . 3) (eval (pair 1 2)))
```
---
    ((1 . 2) (1 2 . 3) (1 . 2))

### ops still bind dotted tails through dotted param specs

```scheme
((op (o . a) e (list o a)) 1 . 5)
```
---
    (1 5)

### proper calls and proper data pass-throughs unchanged

```scheme
(list (list 1 2) ((fn (_ a b) (+ a b)) 3 4) (eval (lit (1 2 3))))
```
---
    ((1 2) 7 (1 2 3))
