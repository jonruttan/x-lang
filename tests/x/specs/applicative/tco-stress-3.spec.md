# Split 3 of tco-stress (#300): see tco-stress-2's header -- the
# combined-forms and non-tail sections carry their own multi-GB
# churn, bounded here in a process of their own.
# @weight 1

## combined TCO forms

### let inside or inside recursive fn

```scheme
(do (def f (fn (self n) (if (or () (let ((m (- n 1))) (= m 0))) 'done (self (- n 1))))) (f 50000))
```
---
    'done

### do inside and inside recursive fn

```scheme
(do (def f (fn (self n) (if (and #t (do (> n 0))) (self (- n 1)) 'done))) (f 50000))
```
---
    'done

### match with and guard in recursive fn

```scheme
(do (def h (fn (_ n) (> n 0))) (def f (fn (self n) (match ((and (h n) #t) (self (- n 1))) (#t 'done)))) (f 50000))
```
---
    'done

### nested fn calls in or condition preserve env through recursion

```scheme
(do (def p (fn (_ n) (= (% n 2) 0))) (def q (fn (_ n) (= n 0))) (def f (fn (self n) (if (or (q n) (p n)) (if (q n) 'done (self (- n 1))) (self (- n 1))))) (f 50000))
```
---
    'done

## non-tail recursion still works

### factorial via non-tail recursion

```scheme
(do (def fact (fn (self n) (if (= n 0) 1 (* n (self (- n 1)))))) (fact 10))
```
---
    3628800

### map with higher-order function

```scheme
(do (def map (fn (self f xs) (if (null? xs) xs (pair (f (first xs)) (self f (rest xs)))))) (List map (fn (_ x) (* x x)) (list 1 2 3)))
```
---
    (1 4 9)
