# @lib ../tests/x/lib/compile.x
# @requires native/jit
# @weight 2

`(compile-fn! NAME F)` (lib/x/tool/fn-compile.x) compiles a program's
closure F where it stands: F becomes the compiled version, every holder of
F calls it, and the interpreted version stays on Compiled's list.  A body
the rewrite cannot carry leaves F interpreted, with the reason on the entry.

## compiled where it stands

### the closure answers as before, compiled

```x
(import x/tool/fn-compile compile-fn!)
(import x/core/doors int+ int- int* int< int= int& obj-ref obj-set!)
(def %fc-tri (fn (self n acc) (if (int< n 1) acc (self (int- n 1) (int+ acc n)))))
(def %fc-tri-before (%fc-tri 1000 0))
(def %fc-e (compile-fn! (lit %fc-tri) %fc-tri))
(write (list (%fc-e state) (Fn label %fc-tri) %fc-tri-before (%fc-tri 1000 0) (%fc-tri 100000 0)))
```
---
    ('compiled 'prim 500500 500500 5000050000)

### recursion by the function's own name is a call of itself

```x
(def %fc-fib (fn (_ n) (if (int< n 2) n (int+ (%fc-fib (int- n 1)) (%fc-fib (int- n 2))))))
(def %fc-e (compile-fn! (lit %fc-fib) %fc-fib))
(write (list (%fc-e state) (%fc-fib 20) ((%fc-e interpreted) 20)))
```
---
    ('compiled 6765 6765)

### a holder bound before the compile calls the compiled version

```x
(def %fc-sq (fn (_ n) (int* n n)))
(def %fc-held (list %fc-sq))
(compile-fn! (lit %fc-sq) %fc-sq)
(write (list (Fn label (first %fc-held)) ((first %fc-held) 12)))
```
---
    ('prim 144)

## values

### a symbol and a list pass through calls as themselves

```x
(def %fc-id (fn (_ x) x))
(def %fc-two (fn (_ a b) (pair (%fc-id a) (%fc-id b))))
(compile-fn! (lit %fc-two) %fc-two)
(write (%fc-two (lit pid) (list (lit use) 1)))
```
---
    ('pid 'use 1)

### pair, first, rest, eq?, null? and not answer as the interpreter does

```x
(def %fc-objs
  (fn (_ x y)
    (list (pair x y) (first (pair x y)) (rest (pair x y))
          (eq? x x) (eq? x y) (null? y) (null? ()) (not x) (not #f)
          (pair? (pair x y)))))
(def %fc-objs-before (%fc-objs 1 ()))
(compile-fn! (lit %fc-objs) %fc-objs)
(write (list (equal? %fc-objs-before (%fc-objs 1 ())) (%fc-objs 1 ())))
```
---
    (#t ((1) 1 () #t #f #t #t #f #t #t))

### obj-ref and obj-set! read and write an object's words

```x
(def %fc-swap!
  (fn (_ o i j)
    (def a (obj-ref o i))
    (obj-set! o i (obj-ref o j))
    (obj-set! o j a)
    o))
(def %fc-o1 (%fc-swap! (pair 10 (lit x)) 0 1))
(compile-fn! (lit %fc-swap!) %fc-swap!)
(def %fc-o2 (%fc-swap! (pair 10 (lit x)) 0 1))
(Heap collect)
(write (list %fc-o1 %fc-o2))
```
---
    (('x . 10) ('x . 10))

### integers, comparisons and match

```x
(def %fc-ints
  (fn (_ a b)
    (match
      ((int< a b) (list (lit lt) (int- b a) (int& a 7) (int< b a) (int= a a)))
      ((int= a b) (lit same))
      (#t (list (lit gt) (int* a b))))))
(def %fc-ints-before (list (%fc-ints 3 10) (%fc-ints 4 4) (%fc-ints 9 2)))
(compile-fn! (lit %fc-ints) %fc-ints)
(write (list (equal? %fc-ints-before (list (%fc-ints 3 10) (%fc-ints 4 4) (%fc-ints 9 2)))
             (%fc-ints 3 10)))
```
---
    (#t ('lt 7 3 #f #t))

## free names are read when the code runs

### a global set! after the compile is seen

```x
(def %fc-k 5)
(def %fc-add-k (fn (_ n) (int+ n %fc-k)))
(compile-fn! (lit %fc-add-k) %fc-add-k)
(def %fc-a (%fc-add-k 1))
(set! %fc-k 100)
(write (list %fc-a (%fc-add-k 1)))
```
---
    (6 101)

### set! of a free name writes its binding

```x
(def %fc-count 0)
(def %fc-bump! (fn (_ n) (set! %fc-count (int+ %fc-count n))))
(compile-fn! (lit %fc-bump!) %fc-bump!)
(%fc-bump! 3)
(%fc-bump! 4)
(write %fc-count)
```
---
    7

### a callee rebound after the compile is the one called

```x
(def %fc-inner (fn (_ x) (int+ x 1)))
(def %fc-outer (fn (_ x) (int* 2 (%fc-inner x))))
(compile-fn! (lit %fc-outer) %fc-outer)
(def %fc-o1 (%fc-outer 5))
(set! %fc-inner (fn (_ x) (int+ x 10)))
(write (list %fc-o1 (%fc-outer 5)))
```
---
    (12 30)

## the frame across a collect

### a collect inside a callee keeps every object the frame holds

```x
(def %fc-churn (fn (_ x) (Heap collect) (List range 0 200) x))
(def %fc-keep
  (fn (_ a)
    (def p (pair a a))
    (def q (pair (%fc-churn p) p))
    (pair (%fc-churn q) p)))
(compile-fn! (lit %fc-keep) %fc-keep)
(write (%fc-keep (list 1 2)))
```
---
    ((((1 2) 1 2) (1 2) 1 2) (1 2) 1 2)

## refusals

### a body the rewrite cannot carry stays interpreted, with the reason

```x
(def %fc-nested (fn (_ l) (List map (fn (_ x) (int+ x 1)) l)))
(def %fc-e (compile-fn! (lit %fc-nested) %fc-nested))
(write (list (%fc-e state) (Fn label %fc-nested) (%fc-nested (list 1 2))
             (not (null? (Str index-of "List" (%fc-e reason))))))
```
---
    ('failed 'fn (2 3) #t)

### a free name unbound when the closure is compiled is refused

```x
(def %fc-later (fn (_ x) (%fc-not-yet x)))
(write ((compile-fn! (lit %fc-later) %fc-later) state))
```
---
    'failed

### a value that is not a closure raises and keeps what it holds

```x
(def %fc-table (list 1 2 3))
(write (list (guard (e (Err label e)) (compile-fn! (lit %fc-table) %fc-table)) %fc-table))
```
---
    ('type (1 2 3))
