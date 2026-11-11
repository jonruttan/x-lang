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
(write (list (%fc-e state) (Fn label %fc-tri) %fc-tri-before (%fc-tri 1000 0) (%fc-tri 65535 0)))
```
---
    ('compiled 'prim 500500 500500 2147450880)

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

### eq? compares value words as the interpreter does

```x
(def %fc-eqs
  (fn (_ n c)
    (list (eq? 0 (int- n n)) (eq? 1000000 (int* n 1000000)) (eq? 97 c)
          (eq? (lit x) (lit x)) (eq? "a" "a") (eq? (pair (lit x) 1) (pair (lit x) 9))
          (eq? () ()) (eq? () 0) (eq? 0 ()) (eq? () #f))))
(def %fc-eqs-before (%fc-eqs 1 #\a))
(def %fc-e (compile-fn! (lit %fc-eqs) %fc-eqs))
(def %fc-streq (fn (_ a b) (str=? a b)))
(def %fc-mem-cmp (prim-ref (lit mem) (lit cmp)))
(def %fc-str->ptr (prim-ref (lit str) (lit ->ptr)))
(def %fc-str=
  (fn (_ a b)
    (if (int= (str-byte-len a) (str-byte-len b))
      (eq? 0 (%fc-mem-cmp (%fc-str->ptr a) (%fc-str->ptr b) (str-byte-len a)))
      #f)))
(def %fc-s (compile-fn! (lit %fc-str=) %fc-str=))
(write (list (%fc-e state) (equal? %fc-eqs-before (%fc-eqs 1 #\a)) (%fc-eqs 1 #\a)
             (%fc-s state) (%fc-str= "abc" "abc") (%fc-str= "abc" "abd")))
```
---
    ('compiled #t (#t #t #t #t #f #t #t #f #f #f) 'compiled #t #f)

### pair? and symbol? answer as the interpreter does

```x
(def %fc-kind
  (fn (_ x)
    (match
      ((pair? x) (lit pair))
      ((symbol? x) (lit symbol))
      (#t (list (pair? x) (symbol? x))))))
(def %fc-kinds (fn (_ l) (List map %fc-kind l)))
(def %fc-vals (list (pair 1 2) (lit (1 2)) (lit a) () 7 "s" #f (Type alist)))
(def %fc-kind-before (%fc-kinds %fc-vals))
(def %fc-e (compile-fn! (lit %fc-kind) %fc-kind))
(write (list (%fc-e state) (equal? %fc-kind-before (%fc-kinds %fc-vals)) (%fc-kinds %fc-vals)))
```
---
    ('compiled #t ('pair 'pair 'symbol (#f #f) (#f #f) (#f #f) (#f #f) (#f #f)))

### a tree walk that tests pair? and symbol? on every node

```x
(def %fc-syms
  (fn (self t n)
    (match
      ((pair? t) (self (rest t) (self (first t) n)))
      ((symbol? t) (int+ n 1))
      (#t n))))
(def %fc-tree (lit (a (b c) (1 (d "e" (f))) g)))
(def %fc-syms-before (%fc-syms %fc-tree 0))
(def %fc-e (compile-fn! (lit %fc-syms) %fc-syms))
(write (list (%fc-e state) %fc-syms-before (%fc-syms %fc-tree 0)))
```
---
    ('compiled 6 6)

### a C primitive head is called with values

```x
(def %fc-sym-of (prim-ref (lit str) (lit ->sym)))
(def %fc-name-of (prim-ref (lit sym) (lit ->str)))
(def %fc-cat (prim-ref (lit str) (lit append)))
(def %fc-tag
  (fn (_ s) (%fc-sym-of (%fc-cat "tag-" (%fc-name-of s)))))
(def %fc-tag-before (%fc-tag (lit a)))
(def %fc-e (compile-fn! (lit %fc-tag) %fc-tag))
(write (list (%fc-e state) %fc-tag-before (%fc-tag (lit b))))
```
---
    ('compiled 'tag-a 'tag-b)

### let binds in parallel, in a scope of its own

```x
(def %fc-lets
  (fn (_ a b)
    (def r (let ((a b) (b a)) (list a b)))
    (def s (let ((a 10)) (let ((a (int+ a 1)) (q a)) (list a q))))
    (let ((c (int+ a 1)))
      (def d (int* c 2))
      (set! c (int+ c d))
      (list r s c d a b))))
(def %fc-lets-before (%fc-lets 1 2))
(def %fc-e (compile-fn! (lit %fc-lets) %fc-lets))
(write (list (%fc-e state) (equal? %fc-lets-before (%fc-lets 1 2)) (%fc-lets 1 2)))
```
---
    ('compiled #t ((2 1) (11 10) 6 4 1 2))

### a let across a call keeps its values

```x
(def %fc-lnext (fn (_ x) (int+ x 1)))
(def %fc-lcall
  (fn (self n acc)
    (if (int= n 0) acc
      (let ((m (int- n 1)) (cell (pair n acc)))
        (self m (pair (%fc-lnext (first cell)) (rest cell)))))))
(def %fc-e (compile-fn! (lit %fc-lcall) %fc-lcall))
(write (list (%fc-e state) (%fc-lcall 3 ())))
```
---
    ('compiled (2 3 4))

### a send to a class's static method is a call of the method

```x
(def-class FcSends ()
  (static
    (limit 7 "A static field")
    (method twice (self n) (int* n 2))
    (method both (self a b) (pair a b))))
(def %fc-sends (fn (_ x) (FcSends both (FcSends twice x) (FcSends (lit twice) (int+ x 1)))))
(def %fc-sends-before (%fc-sends 3))
(def %fc-e (compile-fn! (lit %fc-sends) %fc-sends))
(write (list (%fc-e state) %fc-sends-before (%fc-sends 3)))
```
---
    ('compiled (6 . 8) (6 . 8))

### a send to a class's public static field reads and writes it where it lives

```x
(def-class FcFields ()
  (static
    (limit 7 "A static field")
    (private (held 3))))
(def %fc-field (fn (_ d) (int+ (FcFields limit) d)))
(def %fc-f (compile-fn! (lit %fc-field) %fc-field))
(def %fc-setf (fn (_ v) (FcFields limit v)))
(def %fc-s (compile-fn! (lit %fc-setf) %fc-setf))
(def %fc-before (%fc-field 1))
(%fc-setf 40)
(def %fc-held (fn (_) (FcFields held)))
(def %fc-h (compile-fn! (lit %fc-held) %fc-held))
(write (list (%fc-f state) (%fc-s state) %fc-before (%fc-field 2) (FcFields limit) (%fc-h state)))
```
---
    ('compiled 'compiled 8 42 40 'failed)

### a guard runs its body and its handler as the interpreter does

```x
(def %fc-gcheck (fn (_ l y) (if (null? l) (error "empty") (pair y l))))
(def %fc-gd
  (fn (_ x l)
    (def k (int+ x 1))
    (let ((y (int* k 2)))
      (list (guard (_ (list (lit caught) y)) (%fc-gcheck l y))
            (if (guard (_ #f) (%fc-gcheck l y)) (int+ k y) k)))))
(def %fc-gd-before (list (%fc-gd 1 ()) (%fc-gd 1 (lit (a)))))
(def %fc-e (compile-fn! (lit %fc-gd) %fc-gd))
(write (list (%fc-e state) (equal? %fc-gd-before (list (%fc-gd 1 ()) (%fc-gd 1 (lit (a)))))
             (%fc-gd 1 ()) (%fc-gd 1 (lit (a)))))
```
---
    ('compiled #t (('caught 4) 2) ((4 'a) 6))

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

## applied, a compiled function takes values

A call hands a function expressions and an apply hands it values.  The
engine's apply routine, in the base's slot, is stood in for by one that
tells a compiled function which it is being given.

### apply, map and a call each give the arguments once

```x
(def %fc-ap (fn (_ o k) (list k o)))
(def %fc-ap-via (fn (_ o) (%fc-ap o 1)))
(compile-fn! (lit %fc-ap) %fc-ap)
(compile-fn! (lit %fc-ap-via) %fc-ap-via)
(write (list (apply %fc-ap (list (lit (a b)) (lit zebra)))
             (apply %fc-ap (lit q) (list (lit (c))))
             (List map %fc-ap (list (lit a) (lit (b))) (list (lit c) (lit d)))
             (%fc-ap (lit (d e)) (+ 1 2))
             (apply %fc-ap-via (list (lit (g))))))
```
---
    (('zebra ('a 'b)) (('c) 'q) (('c 'a) ('d ('b))) (3 ('d 'e)) (1 ('g)))

### a type's write handler is handed the value being written

The printer applies a write handler from C.  A list handed over is the
value, not a form to call.

```x
(import x/core/doors type-push-write)
(def %fc-wh-type ((prim-ref (lit type) (lit by-atom)) ((prim-ref (lit type) (lit of)) (list 1))))
(def %fc-wh-seen (list ()))
(def %fc-wh (fn (_ o) (%set-first! %fc-wh-seen (pair o (first %fc-wh-seen))) ()))
(def %fc-wh-e (compile-fn! (lit %fc-wh) %fc-wh))
(type-push-write %fc-wh-type %fc-wh)
(def %fc-wh-out (io-write-to-str (lit (quux zebra))))
((prim-ref (lit type) (lit pop-write)) %fc-wh-type)
(write (list (%fc-wh-e state) %fc-wh-out (first %fc-wh-seen)))
```
---
    ('compiled "" (('quux 'zebra)))

### a primitive and a closure are applied as before

```x
(write (list (apply first (list (lit (x y)))) (apply (fn (_ a) a) (list (lit (z)))) (apply + 1 (list 2 3))))
```
---
    ('x ('z) 6)

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
             (not (null? (Str index-of "head fn" (%fc-e reason))))))
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

### a head the ISA labels spine is refused

```x
(def %fc-evals (fn (_ x) (eval x)))
(def %fc-e (compile-fn! (lit %fc-evals) %fc-evals))
(write (list (%fc-e state) (%fc-evals (lit (int+ 4 1)))))
```
---
    ('failed 5)

### a guard that sets a local of the function is refused

```x
(def %fc-gset (fn (_ x) (guard (_ 0) (set! x 5)) x))
(def %fc-e (compile-fn! (lit %fc-gset) %fc-gset))
(write (list (%fc-e state) (%fc-gset 1)))
```
---
    ('failed 5)

### a named let is refused

```x
(def %fc-nlet (fn (_ n) (let loop ((i n) (acc 0)) (if (int= i 0) acc (loop (int- i 1) (int+ acc i))))))
(def %fc-e (compile-fn! (lit %fc-nlet) %fc-nlet))
(write (list (%fc-e state) (%fc-nlet 4)))
```
---
    ('failed 10)

### a rest parameter is refused

```x
(def %fc-rest (fn (_ a . more) (pair a more)))
(def %fc-e (compile-fn! (lit %fc-rest) %fc-rest))
(write (list (%fc-e state) (%fc-rest 1 2 3)))
```
---
    ('failed (1 2 3))

### a value that is not a closure raises and keeps what it holds

```x
(def %fc-table (list 1 2 3))
(write (list (guard (e (Err label e)) (compile-fn! (lit %fc-table) %fc-table)) %fc-table))
```
---
    ('type (1 2 3))
