## tail call in if

### tail-recursive countdown

```scheme
(do (def loop (fn (_ n) (if (= n 0) (lit done) (loop (- n 1))))) (loop 1000))
```
---
    (lit done)

### tail-recursive accumulator

```scheme
(do (def sum (fn (_ n acc) (if (= n 0) acc (sum (- n 1) (+ acc n))))) (sum 1000 0))
```
---
    500500

## tail call in match

### tail-recursive with match

```scheme
(do (def f (fn (_ n) (match ((= n 0) (lit zero)) (#t (f (- n 1)))))) (f 1000))
```
---
    (lit zero)

## tail call in do

### last form of do is tail

```scheme
(do (def f (fn (_ n) (do 1 2 (if (= n 0) (lit ok) (f (- n 1)))))) (f 1000))
```
---
    (lit ok)

## tail call in let

### last form of let is tail

```scheme
(do (def f (fn (_ n) (let ((m (- n 1))) (if (= m 0) (lit done) (f m))))) (f 1000))
```
---
    (lit done)

## mutual tail recursion

### even?/odd? mutual recursion via set

```scheme
(do (def odd? ()) (def even? (fn (_ n) (if (= n 0) #t (odd? (- n 1))))) (set! odd? (fn (_ n) (if (= n 0) () (even? (- n 1))))) (even? 1000))
```
---
    #t

## tail call in apply

### apply with deep recursion

```scheme
(do (def f (fn (_ n) (if (= n 0) (lit done) (apply f (list (- n 1)))))) (f 1000))
```
---
    (lit done)

## tail call in and

### and tail-evaluates last expression

```scheme
(do (def f (fn (_ n) (if (and #t (> n 0)) (f (- n 1)) (lit done)))) (f 1000))
```
---
    (lit done)

## tail call in or

### or tail-evaluates last expression

```scheme
(do (def f (fn (_ n) (if (or () (= n 0)) (lit done) (f (- n 1))))) (f 1000))
```
---
    (lit done)

## and/or env restoration

### and with fn call preserves env

```scheme
(do (def h (fn (_ n) (> n 0))) (def f (fn (_ n) (if (and (h n) #t) n "no"))) (f 5))
```
---
    5

### or with fn call preserves env

```scheme
(do (def h (fn (_ n) (= n 0))) (def f (fn (_ n) (if (or () (h n)) "yes" "no"))) (f 0))
```
---
    "yes"

## TCO env safety in non-tail position

### if in arg position preserves env

```scheme
(do (def h (fn (_ x) (+ x 10))) (def f (fn (_ n m) (+ (if #t (h n) 0) m))) (f 5 100))
```
---
    115

### nested if with fn calls preserves env

```scheme
(do (def h (fn (_ n) (> n 0))) (def g (fn (_ n m) (if (if #t (h n) ()) (g (- n 1) m) m))) (g 100 42))
```
---
    42

## combined TCO forms

### let inside or inside recursive fn

```scheme
(do (def f (fn (_ n) (if (or () (let ((m (- n 1))) (= m 0))) (lit done) (f (- n 1))))) (f 1000))
```
---
    (lit done)

### do inside and inside recursive fn

```scheme
(do (def f (fn (_ n) (if (and #t (do (> n 0))) (f (- n 1)) (lit done)))) (f 1000))
```
---
    (lit done)

## non-tail recursion still works

### factorial via non-tail recursion

```scheme
(do (def fact (fn (_ n) (if (= n 0) 1 (* n (fact (- n 1)))))) (fact 10))
```
---
    3628800

### map with higher-order function

```scheme
(do (def mymap (fn (_ f xs) (if (null? xs) xs (pair (f (first xs)) (mymap f (rest xs)))))) (mymap (fn (_ x) (* x x)) (list 1 2 3)))
```
---
    (1 4 9)
