## tail call in if

### tail-recursive countdown

```scheme
(do (def loop (fn (n) (if (= n 0) (lit done) (loop (- n 1))))) (loop 100000))
```
---
    done

### tail-recursive accumulator

```scheme
(do (def sum (fn (n acc) (if (= n 0) acc (sum (- n 1) (+ acc n))))) (sum 10000 0))
```
---
    50005000

## tail call in match

### tail-recursive with match

```scheme
(do (def f (fn (n) (match ((= n 0) (lit zero)) (#t (f (- n 1)))))) (f 50000))
```
---
    zero

## tail call in do

### last form of do is tail

```scheme
(do (def f (fn (n) (do 1 2 (if (= n 0) (lit ok) (f (- n 1)))))) (f 50000))
```
---
    ok

## tail call in let

### last form of let is tail

```scheme
(do (def f (fn (n) (let ((m (- n 1))) (if (= m 0) (lit done) (f m))))) (f 50000))
```
---
    done

## mutual tail recursion

### even?/odd? mutual recursion via set

```scheme
(do (def odd? ()) (def even? (fn (n) (if (= n 0) #t (odd? (- n 1))))) (set odd? (fn (n) (if (= n 0) () (even? (- n 1))))) (even? 10000))
```
---
    #t

## tail call in apply

### apply with deep recursion

```scheme
(do (def f (fn (n) (if (= n 0) (lit done) (apply f (list (- n 1)))))) (f 50000))
```
---
    done

## tail call in and

### and tail-evaluates last expression

```scheme
(do (def f (fn (n) (if (and #t (> n 0)) (f (- n 1)) (lit done)))) (f 50000))
```
---
    done

### and with fn call in recursive condition

```scheme
(do (def h (fn (n) (> n 0))) (def f (fn (n) (if (and (h n) #t) (f (- n 1)) (lit done)))) (f 50000))
```
---
    done

## tail call in or

### or tail-evaluates last expression

```scheme
(do (def f (fn (n) (if (or () (= n 0)) (lit done) (f (- n 1))))) (f 50000))
```
---
    done

### or with fn call in recursive condition

```scheme
(do (def h (fn (n) (= n 0))) (def f (fn (n) (if (or () (h n)) (lit done) (f (- n 1))))) (f 50000))
```
---
    done

## and/or env restoration

### and with fn call preserves env across iterations

```scheme
(do (def h (fn (n) (> n 0))) (def f (fn (n) (if (and (h n) #t) n "no"))) (f 5))
```
---
    5

### or with fn call preserves env across iterations

```scheme
(do (def h (fn (n) (= n 0))) (def f (fn (n) (if (or () (h n)) "yes" "no"))) (f 0))
```
---
    "yes"

### or with fn call in deep recursion preserves env

```scheme
(do (def h (fn (n) (= n 0))) (def g (fn (n) (if (or () (h n)) (lit done) (g (- n 1))))) (g 50000))
```
---
    done

### and with fn call in deep recursion preserves env

```scheme
(do (def h (fn (n) (> n 0))) (def g (fn (n) (if (and (h n) #t) (g (- n 1)) (lit done)))) (g 50000))
```
---
    done

## TCO env safety in non-tail position

### if in arg position preserves env

```scheme
(do (def h (fn (x) (+ x 10))) (def f (fn (n m) (+ (if #t (h n) 0) m))) (f 5 100))
```
---
    115

### do in arg position preserves env

```scheme
(do (def h (fn (x) (+ x 10))) (def f (fn (n m) (+ (do 1 (h n)) m))) (f 5 100))
```
---
    115

### match in arg position preserves env

```scheme
(do (def h (fn (x) (+ x 10))) (def f (fn (n m) (+ (match (#t (h n))) m))) (f 5 100))
```
---
    115

### nested if with fn calls preserves env

```scheme
(do (def h (fn (n) (> n 0))) (def g (fn (n m) (if (if #t (h n) ()) (g (- n 1) m) m))) (g 100 42))
```
---
    42

### if with fn call in deep recursive condition

```scheme
(do (def h (fn (n) (= n 0))) (def g (fn (n m) (if (if #t (h n) ()) m (g (- n 1) m)))) (g 50000 99))
```
---
    99

### do with fn call in recursive condition

```scheme
(do (def h (fn (n) (= n 0))) (def g (fn (n) (if (do (h n)) (lit done) (g (- n 1))))) (g 50000))
```
---
    done

### match with fn call in non-tail position

```scheme
(do (def h (fn (x) (* x 2))) (def f (fn (n m) (+ (match ((> n 0) (h n)) (#t 0)) m))) (f 5 100))
```
---
    110

## combined TCO forms

### let inside or inside recursive fn

```scheme
(do (def f (fn (n) (if (or () (let ((m (- n 1))) (= m 0))) (lit done) (f (- n 1))))) (f 50000))
```
---
    done

### do inside and inside recursive fn

```scheme
(do (def f (fn (n) (if (and #t (do (> n 0))) (f (- n 1)) (lit done)))) (f 50000))
```
---
    done

### match with and guard in recursive fn

```scheme
(do (def h (fn (n) (> n 0))) (def f (fn (n) (match ((and (h n) #t) (f (- n 1))) (#t (lit done))))) (f 50000))
```
---
    done

### nested fn calls in or condition preserve env through recursion

```scheme
(do (def p (fn (n) (= (% n 2) 0))) (def q (fn (n) (= n 0))) (def f (fn (n) (if (or (q n) (p n)) (if (q n) (lit done) (f (- n 1))) (f (- n 1))))) (f 50000))
```
---
    done

## non-tail recursion still works

### factorial via non-tail recursion

```scheme
(do (def fact (fn (n) (if (= n 0) 1 (* n (fact (- n 1)))))) (fact 10))
```
---
    3628800

### map with higher-order function

```scheme
(do (def map (fn (f xs) (if (null? xs) xs (pair (f (first xs)) (map f (rest xs)))))) (map (fn (x) (* x x)) (list 1 2 3)))
```
---
    (1 4 9)
