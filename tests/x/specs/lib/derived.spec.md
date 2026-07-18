# Derived expression types

## when

### evaluates body when true

```x
(when (= 1 1) (+ 10 20))
```
---
    30

### returns nil when false

```x
(null? (when (= 1 2) 42))
```
---
    #t

### supports multiple body forms

```x
(when #t 1 2 3)
```
---
    3

## unless

### evaluates body when false

```x
(unless (= 1 2) 99)
```
---
    99

### returns nil when true

```x
(null? (unless (= 1 1) 42))
```
---
    #t

## let* is retired (#45 R6)

### sequential binding is nested let now

```x
(let ((x 1)) (let ((y (+ x 1))) (+ x y)))
```
---
    3

### let* no longer exists

```x
(guard (e "gone") (let* ((a 10)) a))
```
---
    "gone"

### nested let does not leak bindings

```x
(def x 1) (let ((x 99)) (let ((y x)) y)) x
```
---
    1

### many sequential bindings nest

```x
(let ((a 1)) (let ((b (+ a 1))) (let ((c (+ b 1))) (let ((d (+ c 1))) d))))
```
---
    4

### nested let shadows outer

```x
(def x 100) (let ((x 1)) (let ((y (+ x 1))) (+ x y)))
```
---
    3

## letrec

### binds recursive function

```x
(letrec ((fact (fn (self n) (if (= n 0) 1 (* n (self (- n 1))))))) (fact 5))
```
---
    120

### mutual recursion even

```x
(letrec ((e (fn (_ n) (if (= n 0) #t (o (- n 1))))) (o (fn (_ n) (if (= n 0) #f (e (- n 1)))))) (e 10))
```
---
    #t

### mutual recursion odd

```x
(letrec ((e (fn (_ n) (if (= n 0) #t (o (- n 1))))) (o (fn (_ n) (if (= n 0) #f (e (- n 1)))))) (o 7))
```
---
    #t

### two independent bindings

```x
(letrec ((x 1) (y 2)) (+ x y))
```
---
    3

## named let

### basic loop

```x
(let loop ((i 0) (sum 0)) (if (= i 5) sum (loop (+ i 1) (+ sum i))))
```
---
    10

### countdown to list

```x
(let count ((n 5) (acc ())) (if (= n 0) acc (count (- n 1) (pair n acc))))
```
---
    (1 2 3 4 5)

### fibonacci

```x
(let fib ((n 10) (a 0) (b 1)) (if (= n 0) a (fib (- n 1) b (+ a b))))
```
---
    55

### regular let still works

```x
(let ((x 1) (y 2)) (+ x y))
```
---
    3

## cond

### basic true clause

```x
(cond (#t 42))
```
---
    42

### skips false clause

```x
(cond (#f 1) (#t 2))
```
---
    2

### else clause

```x
(cond (#f 1) (else 99))
```
---
    99

### returns nil when no clause matches

```x
(null? (cond (#f 1)))
```
---
    #t

### cond => applies procedure to test value

```x
(cond (#f 'no) (42 => (fn (_ x) (* x 2))))
```
---
    84

### cond => skips false clauses

```x
(cond (#f => (fn (_ x) 'bad)) (#t 'good))
```
---
    'good

### cond clause with multiple expressions

```x
(let ((x 0))
  (cond (#t (set! x 10) (+ x 5))))
```
---
    15

### cond else with multiple expressions

```x
(let ((x 0))
  (cond (#f 'no) (else (set! x 1) (+ x 2))))
```
---
    3

## case

### basic case matching

```x
(case 2
  ((1) 'one)
  ((2) 'two)
  ((3) 'three))
```
---
    'two

### case with else

```x
(case 99
  ((1) 'one)
  (else 'other))
```
---
    'other

### case with datum lists

```x
(case (* 2 3)
  ((2 3 5 7) 'prime)
  ((1 4 6 8 9) 'composite))
```
---
    'composite

### case clause with multiple expressions

```x
(let ((x 0))
  (case 2
    ((1) 'one)
    ((2) (set! x 10) (+ x 5))
    ((3) 'three)))
```
---
    15

### case else with multiple expressions

```x
(let ((x 0))
  (case 99
    ((1) 'one)
    (else (set! x 1) (+ x 2))))
```
---
    3
