## tail call in if

### tail-recursive countdown

```scheme
(do (def loop (fn (self n) (if (= n 0) 'done (self (- n 1))))) (loop 100000))
```
---
    'done

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
    'zero

## tail call in do

### last form of do is tail

```scheme
(do (def f (fn (self n) (do 1 2 (if (= n 0) 'ok (self (- n 1)))))) (f 50000))
```
---
    'ok

## tail call in let

### last form of let is tail

```scheme
(do (def f (fn (self n) (let ((m (- n 1))) (if (= m 0) 'done (self m))))) (f 50000))
```
---
    'done

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
    'done

## tail call in and

### and tail-evaluates last expression

```scheme
(do (def f (fn (self n) (if (and #t (> n 0)) (self (- n 1)) 'done))) (f 50000))
```
---
    'done

### and with fn call in recursive condition

```scheme
(do (def h (fn (_ n) (> n 0))) (def f (fn (self n) (if (and (h n) #t) (self (- n 1)) 'done))) (f 50000))
```
---
    'done

## tail call in or

### or tail-evaluates last expression

```scheme
(do (def f (fn (self n) (if (or () (= n 0)) 'done (self (- n 1))))) (f 50000))
```
---
    'done

### or with fn call in recursive condition

```scheme
(do (def h (fn (_ n) (= n 0))) (def f (fn (self n) (if (or () (h n)) 'done (self (- n 1))))) (f 50000))
```
---
    'done

