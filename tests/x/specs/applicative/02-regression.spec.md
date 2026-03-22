## TCO regression

### countdown 100k does not blow stack

```scheme
(do (def loop (fn (_ n) (if (= n 0) #t (loop (- n 1))))) (loop 100000))
```
---
    #t

### countdown 200k does not blow stack

```scheme
(do (def loop (fn (_ n) (if (= n 0) #t (loop (- n 1))))) (loop 200000))
```
---
    #t

### accumulator 100k is correct

```scheme
(do (def sum (fn (_ n acc) (if (= n 0) acc (sum (- n 1) (+ acc n))))) (sum 100000 0))
```
---
    5000050000

## allocation regression

### TCO loop does not leak allocations

```scheme
(include "lib/x/profile.x")
(profile-reset)
(do (def loop (fn (_ n) (if (= n 0) #t (loop (- n 1))))) (loop 10000))
(< (alloc-count) 200000)
```
---
    #t

### fold over list stays bounded

```scheme
(include "lib/x/profile.x")
(profile-reset)
(fold (fn (_ acc x) (+ acc x)) 0 (range 1 1001))
(< (alloc-count) 500000)
```
---
    #t

## GC regression

### forced GC frees discarded objects

```scheme
(include "lib/x/profile.x")
(def before (heap-count))
(do (def waste (fn (_ n) (if (= n 0) () (do (list 1 2 3) (waste (- n 1)))))) (waste 1000))
(def after-waste (heap-count))
(heap-collect-force)
(def after-gc (heap-count))
(< after-gc after-waste)
```
---
    #t

### GC reduces heap after waste

```scheme
(include "lib/x/profile.x")
(def before (heap-count))
(do (def waste (fn (_ n) (if (= n 0) () (do (list 1 2 3) (waste (- n 1)))))) (waste 1000))
(def after-waste (heap-count))
(heap-collect-force)
(< (heap-count) after-waste)
```
---
    #t

## time regression

### map 5000 elements completes

```scheme
(= (length (map inc (range 1 5001))) 5000)
```
---
    #t

### fold 10000 elements completes

```scheme
(= (fold (fn (_ acc x) (+ acc x)) 0 (range 1 10001)) 50005000)
```
---
    #t

### deep recursion 50k with match

```scheme
(do (def f (fn (_ n) (match ((= n 0) #t) (#t (f (- n 1)))))) (f 50000))
```
---
    #t
