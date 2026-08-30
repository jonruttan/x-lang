# Split from tco-stress.spec.md (#300): one engine batch of the whole
# file accumulated past the alloc ceiling (the and/or forms expand
# ~330 objects per evaluation, 50k-deep loops) and peaked 5.2GB;
# two files bound each process to ~2.5GB and stay under the default
# ceiling.
# @weight 1

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
    'done

### and with fn call in deep recursion preserves env

```scheme
(do (def h (fn (_ n) (> n 0))) (def g (fn (self n) (if (and (h n) #t) (self (- n 1)) 'done))) (g 50000))
```
---
    'done

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
    'done

### match with fn call in non-tail position

```scheme
(do (def h (fn (_ x) (* x 2))) (def f (fn (_ n m) (+ (match ((> n 0) (h n)) (#t 0)) m))) (f 5 100))
```
---
    110

