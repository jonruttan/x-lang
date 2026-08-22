# Conformance: the iterator protocol (profile `core`)

An iterator is a boxed GENERATOR -- `[step . state]` -- not a cursor over a
container. `make` takes a PURE step function and a starting state; the step
answers `(value . next-state)`, and a nil next-state ends the iteration after
that value. x-lang's whole sequence layer is built on this, so an engine that
gets the next/step split wrong produces a library that silently drops or repeats
elements rather than failing.

Every case below builds the same list-walking step, because the protocol is about
the step's CONTRACT rather than about lists.

### next advances and yields elements in order

covers: iter/make iter/next

```scheme
(def %mk (%coord (lit iter) (lit make)))
(def %next (%coord (lit iter) (lit next)))
(def %step (fn (self st) (match ((eq? st ()) ()) (#t (pair (first st) (rest st))))))
(def it (%mk %step (pair 1 (pair 2 (pair 3 ())))))
(%ok (match ((= (%next it) 1) (match ((= (%next it) 2) (= (%next it) 3)) (#t ()))) (#t ())))
```
---
    *** ERROR: ok

### empty? is false before exhaustion and true after

covers: iter/empty? iter/next

```scheme
(def %mk (%coord (lit iter) (lit make)))
(def %next (%coord (lit iter) (lit next)))
(def %empty (%coord (lit iter) (lit empty?)))
(def %step (fn (self st) (match ((eq? st ()) ()) (#t (pair (first st) (rest st))))))
(def it (%mk %step (pair 1 ())))
(def before (%empty it))
(%next it)
(%next it)
(%ok (match (before ()) (#t (%empty it))))
```
---
    *** ERROR: ok

### step is the FUNCTIONAL door -- it yields a value and a next iterator

covers: iter/step

`next` mutates the box; `step` does not. An engine that made them synonyms would
pass every single-pass test and corrupt anything that iterates twice.

```scheme
(def %mk (%coord (lit iter) (lit make)))
(def %stepp (%coord (lit iter) (lit step)))
(def %step (fn (self st) (match ((eq? st ()) ()) (#t (pair (first st) (rest st))))))
(def it (%mk %step (pair 1 (pair 2 ()))))
(def a (%stepp it))
(def b (%stepp it))
(%ok (match ((= (first a) 1) (= (first b) 1)) (#t ())))
```
---
    *** ERROR: ok

### an iterator over the empty state is empty at once

covers: iter/make iter/empty?

```scheme
(def %mk (%coord (lit iter) (lit make)))
(def %empty (%coord (lit iter) (lit empty?)))
(def %step (fn (self st) (match ((eq? st ()) ()) (#t (pair (first st) (rest st))))))
(%ok (%empty (%mk %step ())))
```
---
    *** ERROR: ok
