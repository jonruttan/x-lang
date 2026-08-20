# generic functions: def-generic and on

Open, multi-argument, type-directed dispatch beside message passing.
Signature keys are values: a CLASS matches its instances (subclasses
included, nearer wins), a TYPE HANDLE matches that runtime type exactly,
a bare name is the wildcard. Selection is pointwise (no scalar rank, by
ruling); incomparable candidates fall to the cvt from-lattice, and a
silent lattice is an error naming both.

## definition and dispatch

### a generic is defined empty and called as a value

```x
(do
  (import x/type/generic)
  (def-generic f)
  (on f (x) 'hit)
  (f 99))
```
---
    'hit

### class keys dispatch on the receiver's class

```x
(do
  (import x/type/generic)
  (def-generic area)
  (def-class Circle () r)
  (def-class Square () s)
  (on area ((c Circle)) (* 3 (* (c r) (c r))))
  (on area ((sq Square)) (* (sq s) (sq s)))
  (list (area (new Circle r 2)) (area (new Square s 3))))
```
---
    (12 9)

### a subclass instance takes the nearest class method

```x
(do
  (import x/type/generic)
  (def-generic kind)
  (def-class A ())
  (def-class B (extends A))
  (on kind ((a A)) 'a)
  (on kind ((b B)) 'b)
  (list (kind (new B)) (kind (new A))))
```
---
    ('b 'a)

### type handles are exact; wildcards are last

```x
(do
  (import x/type/generic)
  (def-generic pick)
  (def int-h ((prim-ref 'type 'of) 0))
  (on pick ((a int-h) (b int-h)) 'both-int)
  (on pick ((a int-h) b) 'int-any)
  (on pick (a b) 'any-any)
  (list (pick 1 2) (pick 1 "x") (pick "x" "y")))
```
---
    ('both-int 'int-any 'any-any)

### a generic passes as a value (map over it)

```x
(do
  (import x/type/generic)
  (def-generic twice)
  (on twice (x) (* 2 x))
  (%map (fn (_ v) (twice v)) (list 1 2 3)))
```
---
    (2 4 6)

## misses and ambiguity

### a total miss is a teaching error; guard sees it

```x
(do
  (import x/type/generic)
  (def-generic lonely)
  (guard (e 'missed) (lonely 5)))
```
---
    'missed

### the miss handler intercepts, seeing the generic and the args

```x
(do
  (import x/type/generic)
  (def-generic g)
  (Generic miss! g (fn (_ gg args) (list 'caught args)))
  (g 5 6))
```
---
    ('caught (5 6))

### incomparable candidates without a lattice relation error, naming both

```x
(do
  (import x/type/generic)
  (def-generic amb)
  (def int-h ((prim-ref 'type 'of) 0))
  (on amb ((a int-h) b) 1)
  (on amb (a (b int-h)) 2)
  (guard (e 'ambiguous) (amb 1 2)))
```
---
    'ambiguous

### arity is part of applicability

```x
(do
  (import x/type/generic)
  (def-generic n-ary)
  (on n-ary (a) 'one)
  (on n-ary (a b) 'two)
  (list (n-ary 1) (n-ary 1 2) (guard (e 'none) (n-ary 1 2 3))))
```
---
    ('one 'two 'none)

### the newest identical signature wins

```x
(do
  (import x/type/generic)
  (def-generic f)
  (on f (x) 'first)
  (on f (x) 'second)
  (f 1))
```
---
    'second
