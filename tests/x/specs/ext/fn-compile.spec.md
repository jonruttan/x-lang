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

### an entry compiled again answers as before, called or applied

An entry is switched to interpreted before a state image is written and
compiled again after one is loaded.  The second compile pours what the first
kept.

```x
(def %fc-again (fn (_ a b) (list b a)))
(def %fc-again-e (compile-fn! (lit %fc-again) %fc-again))
(%fc-again-e interpret!)
(def %fc-again-mid (list (%fc-again-e state) (%fc-again 1 2)))
(%fc-again-e compile!)
(write (list %fc-again-mid (%fc-again-e state) (%fc-again 1 2) (apply %fc-again (list (lit x) (lit (y))))))
```
---
    (('interpreted (2 1)) 'compiled (2 1) (('y) 'x))

### a primitive and a closure are applied as before

```x
(write (list (apply first (list (lit (x y)))) (apply (fn (_ a) a) (list (lit (z)))) (apply + 1 (list 2 3))))
```
---
    ('x ('z) 6)

## an fvar's name says how its value is come by

The values a compiled function reads from outside itself are this
process's: a binding cell, the list a call site fills, a method.  Each
fvar's name says what it is, so the values are found again from the
closure and the names, with no rewrite.

### the names, and the values read back from them

```x
(def %fc-nm-m (module x/tool/fn-compile))
(def %fc-nm-g (fn (_ a b) (list a b)))
(def %fc-nm (fn (_ x) (if (symbol? x) (pair x "s") (%fc-nm-g x (lit tag)))))
(def %fc-nm-made ((eval (lit %fc-rewrite) %fc-nm-m) %fc-nm))
(def %fc-nm-names (List map first (rest %fc-nm-made)))
(def %fc-nm-vals ((eval (lit %fc-fvar-values) %fc-nm-m) %fc-nm %fc-nm-names))
(def %fc-nm-same
  (fn (self a b)
    (match ((null? a) (null? b))
           ((if (obj-same? (first a) (first b)) #t (equal? (first a) (first b))) (self (rest a) (rest b)))
           (#t #f))))
(write (list (List reverse %fc-nm-names) (%fc-nm-same %fc-nm-vals (List map rest (rest %fc-nm-made)))))
```
---
    (('%self '%y:symbol? '%x:pair '%t:2:1 '%l:0 '%c:%fc-nm-g '%t:2:2 '%q:tag) #t)

### a guard's closures have no name that says them

The two closures a guard is outlined into are made by the rewrite, so a
function with a guard has an fvar no name finds again.

```x
(def %fc-nm-gd (fn (_ x) (guard (e 0) (first x))))
(def %fc-nm-gd-made ((eval (lit %fc-rewrite) %fc-nm-m) %fc-nm-gd))
(write ((eval (lit %fc-fvar-values) %fc-nm-m) %fc-nm-gd (List map first (rest %fc-nm-gd-made))))
```
---
    #f

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

## a rest parameter

`(fn (self a . more) ...)` binds `more` to the list of every argument after
`a`'s.  Called, the arguments are expressions and each is evaluated once,
by the engine's own eval-list; applied, they are values and the list is
theirs.

### called, each argument is evaluated once

```x
(def %fc-rest (fn (_ a . more) (pair a more)))
(def %fc-rest-e (compile-fn! (lit %fc-rest) %fc-rest))
(def %fc-rest-n (list 0))
(def %fc-rest-tick (fn (_) (%set-first! %fc-rest-n (int+ (first %fc-rest-n) 1)) (first %fc-rest-n)))
(write (list (%fc-rest-e state) (%fc-rest 1 2 3) (%fc-rest 1) (%fc-rest (lit (a b)) (%fc-rest-tick) (lit z) (%fc-rest-tick))
             (first %fc-rest-n)))
```
---
    ('compiled (1 2 3) (1) (('a 'b) 1 'z 2) 2)

### applied, the values are taken as they are

```x
(write (list (apply %fc-rest (list 1 (lit (x y)) (lit z))) (apply %fc-rest (list (lit q)))
             (List map %fc-rest (list 1 2) (list (lit (a)) (lit b)))))
```
---
    ((1 ('x 'y) 'z) ('q) ((1 ('a)) (2 'b)))

### every argument in the rest parameter, and none

```x
(def %fc-all (fn (_ . all) all))
(compile-fn! (lit %fc-all) %fc-all)
(write (list (%fc-all) (%fc-all 1 (lit two) (lit (3))) (apply %fc-all (list (lit (a)) (lit b)))))
```
---
    (() (1 'two (3)) (('a) 'b))

### a self-call passes as many arguments as it likes, and the list survives a collect

```x
(def %fc-sum (fn (self acc . xs) (if (null? xs) acc (apply self (pair (int+ acc (first xs)) (rest xs))))))
(compile-fn! (lit %fc-sum) %fc-sum)
(def %fc-keep-rest (fn (_ a . more) (Heap collect) (List range 0 200) (pair a more)))
(compile-fn! (lit %fc-keep-rest) %fc-keep-rest)
(write (list (%fc-sum 0 1 2 3 4 5) (apply %fc-sum 0 (List range 1 101)) (%fc-keep-rest (list 1 2) (list 3) (lit z))))
```
---
    (15 5050 ((1 2) (3) 'z))

## a fn literal

### a literal that reads no local is one closure, compiled in turn

```x
(def %fc-outlined-count
  (fn (_ ) (%length (List filter (fn (_ en) (eq? (en name) (lit %fc-fn))) (Compiled all)))))
(def %fc-before (%fc-outlined-count))
(def %fc-inc-all (fn (_ l) (List map (fn (_ x) (int+ x 1)) l)))
(def %fc-e (compile-fn! (lit %fc-inc-all) %fc-inc-all))
(write (list (%fc-e state) (int- (%fc-outlined-count) %fc-before) (%fc-inc-all (list 1 2))))
```
---
    ('compiled 1 (2 3))

### a literal is handed the parameters and let locals it reads

```x
(def %fc-add-all (fn (_ l k) (List map (fn (_ x) (int+ x k)) l)))
(def %fc-add-ten (fn (_ l) (let ((k 10)) (List map (fn (_ x) (int+ x k)) l))))
(write (list ((compile-fn! (lit %fc-add-all) %fc-add-all) state)
             ((compile-fn! (lit %fc-add-ten) %fc-add-ten) state)
             (%fc-add-all (list 1 2) 5) (%fc-add-ten (list 1 2))))
```
---
    ('compiled 'compiled (6 7) (11 12))

### a closure over locals runs its body compiled, its self-calls the body's own

```x
(def %fc-outlined-count
  (fn (_ ) (%length (List filter (fn (_ en) (eq? (en name) (lit %fc-fn))) (Compiled all)))))
(def %fc-before (%fc-outlined-count))
(def %fc-leaves
  (fn (_ t k)
    (def walk (fn (self e) (if (pair? e) (int+ (self (first e)) (self (rest e))) (if (null? e) 0 k))))
    (walk t)))
(def %fc-steps (fn (_ k) (def f (fn (self n acc) (if (int< n 1) acc (self (int- n 1) (int+ acc k))))) (f 100000 0)))
(def %fc-itself (fn (_ k) (def f (fn (self n) (if (int< n 1) self (int+ k n)))) (list (eq? (f 0) f) (f 2))))
(def %fc-more (fn (_ k) (def f (fn (_ a . more) (list k a more))) (list (f 1) (f 1 2 3))))
(write (List map (fn (_ f) ((compile-fn! (lit f) f) state)) (list %fc-leaves %fc-steps %fc-itself %fc-more)))
(write (list (int- (%fc-outlined-count) %fc-before)
             (%fc-leaves (list 1 (list 2 3)) 7) (%fc-steps 2) (%fc-itself 4) (%fc-more 9)))
```
---
    ('compiled 'compiled 'compiled 'compiled)(4 21 200000 (#t 6) ((9 1 ()) (9 1 (2 3))))

### a loop written in place compiles, its self-call a jump

```x
(def %fc-sum-to (fn (_ n) ((fn (self i acc) (if (int< i 1) acc (self (int- i 1) (int+ acc i)))) n 0)))
(def %fc-times (fn (_ n k) ((fn (self i acc) (if (int< i 1) acc (self (int- i 1) (int+ acc k)))) n 0)))
(write (list ((compile-fn! (lit %fc-sum-to) %fc-sum-to) state)
             ((compile-fn! (lit %fc-times) %fc-times) state)
             (%fc-sum-to 10000) (%fc-times 1000 3)))
```
---
    ('compiled 'compiled 50005000 3000)

### loops and literals nest, and an inner self is its own

```x
(def %fc-total
  (fn (_ rows)
    ((fn (self rs acc)
       (if (null? rs) acc
         (self (rest rs) ((fn (self l a) (if (null? l) a (self (rest l) (int+ a (first l))))) (first rs) acc))))
     rows 0)))
(def %fc-doubled (fn (_ ls) (List map (fn (_ l) (List map (fn (_ x) (int* x 2)) l)) ls)))
(write (list ((compile-fn! (lit %fc-total) %fc-total) state)
             ((compile-fn! (lit %fc-doubled) %fc-doubled) state)
             (%fc-total (list (list 1 2) (list 3) ())) (%fc-doubled (list (list 1) (list 2 3)))))
```
---
    ('compiled 'compiled 6 ((2) (4 6)))

### a loop that hands itself on is a closure

```x
(def %fc-rev
  (fn (_ l) ((fn (self l acc) (if (null? l) acc (apply self (list (rest l) (pair (first l) acc))))) l ())))
(write (list ((compile-fn! (lit %fc-rev) %fc-rev) state) (%fc-rev (list 1 2 3))))
```
---
    ('compiled (3 2 1))

### a literal that sets a local, or reads one written after it, is refused

```x
(def %fc-count-up (fn (_ l) (def n 0) (List map (fn (_ x) (set! n (int+ n 1))) l) n))
(def %fc-late-set (fn (_ k) (def g (fn (_ ) k)) (set! k 5) (g)))
(def %fc-late-def (fn (_ ) (def g (fn (_ ) (h))) (def h (fn (_ ) 1)) (g)))
(write (List map (fn (_ f) (def e (compile-fn! (lit f) f)) (list (e state) (Fn label f)))
         (list %fc-count-up %fc-late-set %fc-late-def)))
(write (list (%fc-count-up (list 1 2 3)) (%fc-late-set 1) (%fc-late-def)))
```
---
    (('failed 'fn) ('failed 'fn) ('failed 'fn))(3 5 1)

## refusals

### a body the rewrite cannot carry stays interpreted, with the reason

```x
(def %fc-computed (fn (_ fs x) ((first fs) x)))
(def %fc-e (compile-fn! (lit %fc-computed) %fc-computed))
(write (list (%fc-e state) (Fn label %fc-computed) (%fc-computed (list (fn (_ y) (int+ y 1))) 2)
             (not (null? (Str index-of "head is not a name" (%fc-e reason))))))
```
---
    ('failed 'fn 3 #t)

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

### a value that is not a closure raises and keeps what it holds

```x
(def %fc-table (list 1 2 3))
(write (list (guard (e (Err label e)) (compile-fn! (lit %fc-table) %fc-table)) %fc-table))
```
---
    ('type (1 2 3))

## tail calls

A call in tail position of a closure other than F is a tail call, as it is
interpreted: F leaves the filled call for whoever called it to make, the
evaluator or an apply, so a chain of them runs in constant stack.

### a tail call of another compiled closure is a tail call

```x
(def %fc-ping (fn (_ n acc) (if (int= n 0) acc (%fc-pong (int- n 1) (int+ acc 1)))))
(def %fc-pong (fn (_ n acc) (if (int= n 0) acc (%fc-ping (int- n 1) (int+ acc 2)))))
(def %fc-e1 (compile-fn! (lit %fc-ping) %fc-ping))
(def %fc-e2 (compile-fn! (lit %fc-pong) %fc-pong))
(write (list (%fc-e1 state) (%fc-e2 state) (%fc-ping 1000000 0)))
```
---
    ('compiled 'compiled 1500000)

### an apply of a compiled closure makes the tail call it leaves

```x
(write (list (apply %fc-ping (list 1000000 0)) (List map (fn (_ n) (%fc-pong n 0)) (list 0 1 2 3))))
```
---
    (1500000 (0 2 3 5))

### a tail call inside a guard is made inside it

```x
(def %fc-raiser (fn (_ x) (if (int= x 0) (error "zero") x)))
(def %fc-guarded (fn (_ x) (guard (e (lit caught)) (%fc-raiser x))))
(def %fc-e (compile-fn! (lit %fc-guarded) %fc-guarded))
(write (list (%fc-e state) (%fc-guarded 0) (%fc-guarded 4)))
```
---
    ('compiled 'caught 4)

### a tail call of an interpreted closure, and back

```x
(def %fc-even? (fn (_ n) (if (int= n 0) #t (%fc-odd? (int- n 1)))))
(def %fc-odd? (fn (_ n) (if (int= n 0) #f (%fc-even? (int- n 1)))))
(def %fc-e (compile-fn! (lit %fc-even?) %fc-even?))
(write (list (%fc-e state) (%fc-even? 1000001) (%fc-odd? 1000001)))
```
---
    ('compiled #f #t)

### a call not in tail position answers its value to the code after it

```x
(def %fc-inc (fn (_ n) (int+ n 1)))
(def %fc-twice (fn (_ n) (int+ (%fc-inc n) (%fc-inc n))))
(def %fc-e (compile-fn! (lit %fc-twice) %fc-twice))
(write (list (%fc-e state) (%fc-twice 4)))
```
---
    ('compiled 10)
