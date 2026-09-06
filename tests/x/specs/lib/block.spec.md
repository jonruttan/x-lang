# @weight 2
## block-form methods (`x/type/block`): (subject sel (names ...) body ...)

### one name binds the element

```x
(List map (x) (* x 10) (list 1 2 3))
```
---
    (10 20 30)

### a second name binds the 0-based index, element first

```x
(List map (x i) (list i x) (list 7 8 9))
```
---
    ((0 7) (1 8) (2 9))

### the body closes over the call site

```x
(let ((k 100)) (List map (x) (+ x k) (list 1 2)))
```
---
    (101 102)

### the block sees a binding made after the wrap

```x
(do (def %blk-mult 3) (List map (x) (* x %blk-mult) (list 1 2)))
```
---
    (3 6)

### an index counter is per send, not shared

```x
(List map (x i) (List map (y j) (list i j x y) (list "a")) (list "p" "q"))
```
---
    (((0 0 "p" "a")) ((1 0 "q" "a")))

## the applicative form is untouched

### an explicit fn still works

```x
(List map (fn (_ x) (* x 2)) (list 1 2 3))
```
---
    (2 4 6)

### the variadic multi-list form still works

```x
(List map (fn (_ a b) (+ a b)) (list 1 2) (list 10 20))
```
---
    (11 22)

### a bare callable name still works

```x
(List map first (list (list 1 2) (list 3 4)))
```
---
    (1 3)

### a computed callable is still a call, not a binding list

```x
(do (def %blk-mk (fn (_) (fn (_ x) (* x 5)))) (List map (%blk-mk) (list 1 2)))
```
---
    (5 10)

## arity is checked per shape

### three names is an error for the element shape

```x
(guard (e "raised") (List map (a b c) a (list 1)))
```
---
    "raised"

### the error names the accepted shapes

```x
(guard (e e) (List map (a b c) a (list 1)))
```
---
    "block takes (element) or (element index), got names: 3"

## wrapping is per selector

### an unwrapped selector still reads its first argument as a callable

`drop-while` is deliberately not wrapped, so `(x)` there is a call, not a
binding list.

```x
(guard (e "not-callable") (List drop-while (x) (> x 1) (list 1 2)))
```
---
    "not-callable"

### Block method! refuses a selector the class does not have

```x
(guard (e e) (Block method! List 'no-such-selector))
```
---
    "Block method!: no such method no-such-selector"

## documentation survives the wrap

### help still reports the applicative signature

```x
(help List/map)
```
---
      => LIST -- New list

## the element shape across the wrapped selectors

### filter

```x
(List filter (x) (> x 1) (list 3 1 2))
```
---
    (3 2)

### for-each returns nil and runs for effect

```x
(let ((acc (list ()))) (List for-each (x) (%set-first! acc (pair x (first acc))) (list 1 2 3)) (first acc))
```
---
    (3 2 1)

### find

```x
(List find (x) (> x 1) (list 1 2 3))
```
---
    2

### any? and all?

```x
(list (List any? (x) (> x 2) (list 1 2 3)) (List all? (x) (> x 0) (list 1 2 3)))
```
---
    (#t #t)

### sort-by, with the index available

```x
(List sort-by (x i) (- 0 x) (list 1 3 2))
```
---
    (3 2 1)

## the fold shape: (acc element)

### fold threads the accumulator

```x
(List fold (acc x) (+ acc x) 0 (list 1 2 3))
```
---
    6

### a third name is the index

```x
(List fold (acc x i) (+ acc (* x i)) 0 (list 5 5 5))
```
---
    15

### the init is evaluated, not treated as body

```x
(List fold (acc x) (+ acc x) (* 10 10) (list 1))
```
---
    101

## the binary shape: (a b)

### sort takes a comparator block

```x
(List sort (a b) (< a b) (list 3 1 2))
```
---
    (1 2 3)

### reduce takes a combiner block

```x
(List reduce (a b) (+ a b) (list 1 2 3))
```
---
    6

## Vector carries the same forms

### map with an index

```x
(#(1 2 3) map (x i) (* x i))
```
---
    #(0 2 6)

### fold, value form

```x
(#(1 2 3) fold (acc x) (+ acc x) 0)
```
---
    6

## Seq wraps once and every subclass inherits it

### a string iterates through Seq's block form

```x
(Str8 fold (acc c i) (+ acc i) 0 "abcd")
```
---
    6

## instance-method classes use the same surface

### Gen is an instance method -- the receiver is self, not a trailing argument

```x
(((Gen range 0 4) map (x i) (list i x)) ->list)
```
---
    ((0 0) (1 1) (2 2) (3 3))

### Gen fold carries its init after the body

```x
((Gen range 1 5) fold (acc x) (+ acc x) 0)
```
---
    10

### Dict uses the pair shape: two names are key and value

```x
(do (import x/type/dict)
    (let ((d (Dict from-alist (list (pair 'a 1)))))
      (let ((acc (list ()))) (d for-each (k v) (%set-first! acc (list k v))) (first acc))))
```
---
    ('a 1)

### Dict with one name still receives the pair

```x
(do (import x/type/dict)
    (let ((d (Dict from-alist (list (pair 'a 1)))))
      (let ((acc (list ()))) (d for-each (p) (%set-first! acc p)) (first acc))))
```
---
    ('a . 1)

### Set fold takes its init after the body

```x
(do (import x/type/set) ((Set of 1 2 3) fold (acc x) (+ acc x) 0))
```
---
    6
