## tail call in if

### tail-recursive countdown

```scheme
(do (def loop (fn (self n) (if (= n 0) 'done (self (- n 1))))) (loop 100000))
```
---
    done

### tail-recursive accumulator

```scheme
(do (def sum (fn (self n acc) (if (= n 0) acc (self (- n 1) (+ acc n))))) (sum 10000 0))
```
---
    50005000

## tail call in match

### tail-recursive with match

```scheme
(do (def f (fn (self n) (match ((= n 0) 'zero) (#t (self (- n 1)))))) (f 50000))
```
---
    zero

## tail call in do

### last form of do is tail

```scheme
(do (def f (fn (self n) (do 1 2 (if (= n 0) 'ok (self (- n 1)))))) (f 50000))
```
---
    ok

## tail call in let

### last form of let is tail

```scheme
(do (def f (fn (self n) (let ((m (- n 1))) (if (= m 0) 'done (self m))))) (f 50000))
```
---
    done

## mutual tail recursion

### even?/odd? mutual recursion via set

```scheme
(do (def odd? ()) (def even? (fn (_ n) (if (= n 0) #t (odd? (- n 1))))) (set! odd? (fn (_ n) (if (= n 0) () (even? (- n 1))))) (even? 10000))
```
---
    #t

## tail call in apply

### apply with deep recursion

```scheme
(do (def f (fn (self n) (if (= n 0) 'done (apply self (list (- n 1)))))) (f 50000))
```
---
    done

## tail call in and

### and tail-evaluates last expression

```scheme
(do (def f (fn (self n) (if (and #t (> n 0)) (self (- n 1)) 'done))) (f 50000))
```
---
    done

### and with fn call in recursive condition

```scheme
(do (def h (fn (_ n) (> n 0))) (def f (fn (self n) (if (and (h n) #t) (self (- n 1)) 'done))) (f 50000))
```
---
    done

## tail call in or

### or tail-evaluates last expression

```scheme
(do (def f (fn (self n) (if (or () (= n 0)) 'done (self (- n 1))))) (f 50000))
```
---
    done

### or with fn call in recursive condition

```scheme
(do (def h (fn (_ n) (= n 0))) (def f (fn (self n) (if (or () (h n)) 'done (self (- n 1))))) (f 50000))
```
---
    done

## and/or env restoration

### and with fn call preserves env across iterations

```scheme
(do (def h (fn (_ n) (> n 0))) (def f (fn (_ n) (if (and (h n) #t) n "no"))) (f 5))
```
---
    5

### or with fn call preserves env across iterations

```scheme
(do (def h (fn (_ n) (= n 0))) (def f (fn (_ n) (if (or () (h n)) "yes" "no"))) (f 0))
```
---
    "yes"

### or with fn call in deep recursion preserves env

```scheme
(do (def h (fn (_ n) (= n 0))) (def g (fn (self n) (if (or () (h n)) 'done (self (- n 1))))) (g 50000))
```
---
    done

### and with fn call in deep recursion preserves env

```scheme
(do (def h (fn (_ n) (> n 0))) (def g (fn (self n) (if (and (h n) #t) (self (- n 1)) 'done))) (g 50000))
```
---
    done

## TCO env safety in non-tail position

### if in arg position preserves env

```scheme
(do (def h (fn (_ x) (+ x 10))) (def f (fn (_ n m) (+ (if #t (h n) 0) m))) (f 5 100))
```
---
    115

### do in arg position preserves env

```scheme
(do (def h (fn (_ x) (+ x 10))) (def f (fn (_ n m) (+ (do 1 (h n)) m))) (f 5 100))
```
---
    115

### match in arg position preserves env

```scheme
(do (def h (fn (_ x) (+ x 10))) (def f (fn (_ n m) (+ (match (#t (h n))) m))) (f 5 100))
```
---
    115

### nested if with fn calls preserves env

```scheme
(do (def h (fn (_ n) (> n 0))) (def g (fn (self n m) (if (if #t (h n) ()) (self (- n 1) m) m))) (g 100 42))
```
---
    42

### if with fn call in deep recursive condition

```scheme
(do (def h (fn (_ n) (= n 0))) (def g (fn (self n m) (if (if #t (h n) ()) m (self (- n 1) m)))) (g 50000 99))
```
---
    99

### do with fn call in recursive condition

```scheme
(do (def h (fn (_ n) (= n 0))) (def g (fn (self n) (if (do (h n)) 'done (self (- n 1))))) (g 50000))
```
---
    done

### match with fn call in non-tail position

```scheme
(do (def h (fn (_ x) (* x 2))) (def f (fn (_ n m) (+ (match ((> n 0) (h n)) (#t 0)) m))) (f 5 100))
```
---
    110

## combined TCO forms

### let inside or inside recursive fn

```scheme
(do (def f (fn (self n) (if (or () (let ((m (- n 1))) (= m 0))) 'done (self (- n 1))))) (f 50000))
```
---
    done

### do inside and inside recursive fn

```scheme
(do (def f (fn (self n) (if (and #t (do (> n 0))) (self (- n 1)) 'done))) (f 50000))
```
---
    done

### match with and guard in recursive fn

```scheme
(do (def h (fn (_ n) (> n 0))) (def f (fn (self n) (match ((and (h n) #t) (self (- n 1))) (#t 'done)))) (f 50000))
```
---
    done

### nested fn calls in or condition preserve env through recursion

```scheme
(do (def p (fn (_ n) (= (% n 2) 0))) (def q (fn (_ n) (= n 0))) (def f (fn (self n) (if (or (q n) (p n)) (if (q n) 'done (self (- n 1))) (self (- n 1))))) (f 50000))
```
---
    done

## non-tail recursion still works

### factorial via non-tail recursion

```scheme
(do (def fact (fn (self n) (if (= n 0) 1 (* n (self (- n 1)))))) (fact 10))
```
---
    3628800

### map with higher-order function

```scheme
(do (def map (fn (self f xs) (if (null? xs) xs (pair (f (first xs)) (self f (rest xs)))))) (map (fn (_ x) (* x x)) (list 1 2 3)))
```
---
    (1 4 9)
