# @weight 1
## self-evaluation

### evaluates positive integers

```x
99
```
---
    99

### evaluates negative integers

```x
-99
```
---
    -99

### evaluates string literals

```x
"hello"
```
---
    "hello"

### evaluates empty strings

```x
""
```
---
    ""

### evaluates nil

```x
()
```
---

### evaluates character literals

```x
#\a
```
---
    #\a

### evaluates #t

```x
#t
```
---
    #t

## symbol lookup

### binds and looks up a value

```x
(do (def x 42) x)
```
---
    42

### looks up in expression

```x
(do (def x 5) (+ x 1))
```
---
    6

### unbound symbol signals error

```x
(guard (e 'caught) no-such-var)
```
---
    'caught

### the error names the offending symbol

```x
(guard (e (symbol->str e)) no-such-var)
```
---
    "Unbound SYMBOL 'no-such-var'"

### an engine-raised error writes bare

The engine raises the base's error ATOM, and write shows an atom's
text without quotes -- one identity, one representation, both engines
(x-engine-rust#23 caught the rust side carrying strings).

```x
(write (guard (e e) (+ () 1)))
```
---
    +: operand is nil

### a program-raised string writes quoted

`(error "...")` raises the string itself -- guard binds a real STRING,
and write shows it quoted, distinguishable from the engine's atom.

```x
(write (guard (e e) (error "a lib error")))
```
---
    "a lib error"

## recursive definitions

### computes fact(0)

```x
(do (def fact (fn (self n) (if (= n 0) 1 (* n (self (- n 1)))))) (fact 0))
```
---
    1

### computes fact(5)

```x
(do (def fact (fn (self n) (if (= n 0) 1 (* n (self (- n 1)))))) (fact 5))
```
---
    120

### computes fact(10)

```x
(do (def fact (fn (self n) (if (= n 0) 1 (* n (self (- n 1)))))) (fact 10))
```
---
    3628800

## recursive list operations

### computes length of a list

```x
(do (def len (fn (self xs) (if (null? xs) 0 (+ 1 (self (rest xs)))))) (len (list 1 2 3 4 5)))
```
---
    5

### computes length of empty list

```x
(do (def len (fn (self xs) (if (null? xs) 0 (+ 1 (self (rest xs)))))) (len (list)))
```
---
    0

### maps over a list

```x
(do (def map (fn (self f xs) (if (null? xs) xs (pair (f (first xs)) (self f (rest xs)))))) (List map (fn (_ x) (* x x)) (list 1 2 3)))
```
---
    (1 4 9)

### appends two lists

```x
(do (def append (fn (self a b) (if (null? a) b (pair (first a) (self (rest a) b))))) (List append (list 1 2) (list 3 4)))
```
---
    (1 2 3 4)

## higher-order recursion

### folds a list

```x
(do (def fold (fn (self f acc xs) (if (null? xs) acc (self f (f acc (first xs)) (rest xs))))) (List fold (fn (_ a b) (+ a b)) 0 (list 1 2 3 4 5)))
```
---
    15

### filters a list

```x
(do (def filter (fn (self p xs) (if (null? xs) xs (if (p (first xs)) (pair (first xs) (self p (rest xs))) (self p (rest xs)))))) (List filter (fn (_ x) (= x 3)) (list 1 2 3 4 3)))
```
---
    (3 3)

## improper call forms (#69 ruled: error / echo split)

Calling an APPLICATIVE with an improper argument list raises -- the C
argument walk (x_eval_list) guards spine cells STRUCTURALLY, by the type's
declared pair units (the same contract the collector's payload walk trusts),
so any reader lang's spine type participates and no reader/evaluator
symmetry is assumed. A NON-callable head was never a call: the form is data
and echoes back unchanged, proper or dotted. Ops receive spines raw and a
dotted param spec binds an atom tail legitimately.

Before this, (list 1 . 5) and bare-x-core (f 1.5) -- where 1.5 reads as a
dotted pair with no float module -- killed the process.

### callable head with improper args raises, catchably

```x
(list (guard (e (lit R)) (list 1 . 5))
      (guard (e (lit R)) ((fn (_ a) a) 1 . 5))
      (guard (e (lit R)) (eval (pair list 5))))
```
---
    ('R 'R 'R)

### the error names the fault

```x
(guard (e (Str8 includes? "improper argument list" (Str8 str "" e))) (list 1 . 5))
```
---
    #t

### non-callable heads echo the data form, dotted or not

```x
(list (1 . 2) (1 2 . 3) (eval (pair 1 2)))
```
---
    ((1 . 2) (1 2 . 3) (1 . 2))

### ops still bind dotted tails through dotted param specs

```x
((op (o . a) e (list o a)) 1 . 5)
```
---
    (1 5)

### proper calls and proper data pass-throughs unchanged

```x
(list (list 1 2) ((fn (_ a b) (+ a b)) 3 4) (eval (lit (1 2 3))))
```
---
    ((1 2) 7 (1 2 3))
