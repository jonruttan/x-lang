# traits and delegation
# @weight 1

Traits are named method bundles mixed in at class definition; `delegates`
generates forwarders to a field's value. Conflict rules are explicit, no
linearization: own method > trait method > inherited; two traits on one
selector with no own override refuse at definition time.

## mixing

### trait methods arrive on the host, instance and static sides

```x
(do
  (import x/type/trait)
  (def-trait Greets
    (method hi (self) 'hi)
    (static (method banner (self) 'banner)))
  (def-class H () (with Greets))
  (list ((new H) hi) (H banner)))
```
---
    ('hi 'banner)

### a trait body closes over its definition site

```x
(do
  (import x/type/trait)
  (def secret 42)
  (def-trait Sees (method peek (self) secret))
  (def-class S () (with Sees))
  ((new S) peek))
```
---
    42

### super inside a trait method resolves on the HOST's chain

```x
(do
  (import x/type/trait)
  (def-trait Wraps (method who (self) (list 'wrapped (super self who))))
  (def-class P () (method who (self) 'parent))
  (def-class C (extends P) (with Wraps))
  ((new C) who))
```
---
    ('wrapped 'parent)

## precedence and conflicts

### the class's own method beats a trait's

```x
(do
  (import x/type/trait)
  (def-trait T (method who (self) 'trait))
  (def-class W () (with T) (method who (self) 'own))
  ((new W) who))
```
---
    'own

### a trait's method beats an inherited one

```x
(do
  (import x/type/trait)
  (def-trait T (method who (self) 'trait))
  (def-class P () (method who (self) 'parent))
  (def-class C (extends P) (with T))
  ((new C) who))
```
---
    'trait

### two traits on one selector refuse without an own override

```x
(do
  (import x/type/trait)
  (def-trait TA (method x (self) 1))
  (def-trait TB (method x (self) 2))
  (guard (e 'collide) (eval! '(def-class Bad () (with TA TB)))))
```
---
    'collide

### an own override resolves the collision

```x
(do
  (import x/type/trait)
  (def-trait TA (method x (self) 1))
  (def-trait TB (method x (self) 2))
  (def-class Good () (with TA TB) (method x (self) 3))
  ((new Good) x))
```
---
    3

## requirements

### an unmet (require ...) refuses at the host's definition

```x
(do
  (import x/type/trait)
  (def-trait Needs (require cmp) (method ok? (self) (self cmp)))
  (guard (e 'unmet) (eval! '(def-class Bare () (with Needs)))))
```
---
    'unmet

### a requirement met anywhere on the chain satisfies

```x
(do
  (import x/type/trait)
  (def-trait Needs (require cmp) (method ok? (self) 'ok))
  (def-class P () (method cmp (self) 0))
  (def-class C (extends P) (with Needs))
  ((new C) ok?))
```
---
    'ok

## delegates

### forwarders reach the field's methods, rename pairs included

```x
(do
  (import x/type/dict)
  (def-class Bag ()
    (d)
    (delegates d (has? length (keys names)))
    (method %init (self) (self d (Dict make)))
    (method add! (self k) ((self d) set! k #t) self))
  (def g (new Bag))
  (g add! 'apple)
  (g add! 'pear)
  (list (g length) (g has? 'apple) (g names)))
```
---
    (2 #t ('apple 'pear))

### the forwarder resolves per call (a swapped delegate is honoured)

```x
(do
  (import x/type/dict)
  (def-class Box ()
    (d)
    (delegates d (length))
    (method %init (self) (self d (Dict make))))
  (def b (new Box))
  ((b d) set! 'k 1)
  (b d (Dict from-alist (list (pair 'x 1) (pair 'y 2) (pair 'z 3))))
  (b length))
```
---
    3
