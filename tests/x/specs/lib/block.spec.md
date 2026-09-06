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

```x
(guard (e "not-callable") (List filter (x) (> x 1) (list 1 2)))
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
