## TCO regression

### countdown 100k does not blow stack

```scheme
(do (def loop (fn (self n) (if (= n 0) #t (self (- n 1))))) (loop 100000))
```
---
    #t

### countdown 200k does not blow stack

```scheme
(do (def loop (fn (self n) (if (= n 0) #t (self (- n 1))))) (loop 200000))
```
---
    #t

### accumulator 100k is correct

```scheme
(do (def sum (fn (self n acc) (if (= n 0) acc (self (- n 1) (+ acc n))))) (sum 100000 0))
```
---
    5000050000

## allocation regression

### TCO loop does not leak allocations

```scheme
(import x/tool/profile)
(profile-reset)
(do (def loop (fn (self n) (if (= n 0) #t (self (- n 1))))) (loop 10000))
(< (alloc-count) 200000)
```
---
    #t

### fold over list stays bounded

```scheme
(import x/tool/profile)
(profile-reset)
(List fold (fn (_ acc x) (+ acc x)) 0 (List range 1 1001))
(< (alloc-count) 500000)
```
---
    #t

## GC regression

### forced GC frees discarded objects

```scheme
(import x/tool/profile)
(def before (Heap count))
(do (def waste (fn (self n) (if (= n 0) () (do (list 1 2 3) (self (- n 1)))))) (waste 1000))
(def after-waste (Heap count))
(heap-collect-force)
(def after-gc (Heap count))
(< after-gc after-waste)
```
---
    #t

### GC reduces heap after waste

```scheme
(import x/tool/profile)
(def before (Heap count))
(do (def waste (fn (self n) (if (= n 0) () (do (list 1 2 3) (self (- n 1)))))) (waste 1000))
(def after-waste (Heap count))
(heap-collect-force)
(< (Heap count) after-waste)
```
---
    #t

## time regression

### map 5000 elements completes

```scheme
(= (List length (List map (method-ref Num inc) (List range 1 5001))) 5000)
```
---
    #t

### fold 10000 elements completes

```scheme
(= (List fold (fn (_ acc x) (+ acc x)) 0 (List range 1 10001)) 50005000)
```
---
    #t

### deep recursion 50k with match

```scheme
(do (def f (fn (self n) (match ((= n 0) #t) (#t (self (- n 1)))))) (f 50000))
```
---
    #t
