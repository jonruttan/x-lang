# Conformance: pairs, nil and identity (profile `core`)

The data substrate. `first` and `rest` are UNCHECKED by contract -- reading them
off a non-pair is undefined, and x-lang guards its own call sites rather than
asking the engine to. So the cases below never probe that edge: an engine is free
to crash there, and a suite that pinned a behaviour would be inventing a
requirement the language deliberately declined.

### pair constructs, first and rest project

covers: pair first rest

```scheme
(def p (pair 1 2))
(%ok (match ((= (first p) 1) (= (rest p) 2)) (#t ())))
```
---
    *** ERROR: ok

### nil is the empty list and is falsy

covers: pair

`()` is nil is NULL -- one value, not three. An engine with a distinct empty-list
object would pass the first arm and fail the second.

```scheme
(%ok (match (() ()) (#t 1)))
```
---
    *** ERROR: ok

### eq? on nil answers truthy

covers: eq?

The nil==nil case is why `eq?` answers with a `t` SYMBOL rather than a boolean:
returning nil-for-false and nil-for-nil-equals-nil would be indistinguishable.

```scheme
(%ok (eq? () ()))
```
---
    *** ERROR: ok

### eq? distinguishes distinct integers

covers: eq?

```scheme
(%ok (match ((eq? 1 1) (match ((eq? 1 2) ()) (#t 1))) (#t ())))
```
---
    *** ERROR: ok

### interned symbols are pointer-identical

covers: eq? lit

Symbol interning is what lets the catalog compare by pointer; an engine that
allocated a fresh symbol per occurrence would fail here and would make every
catalog lookup in the library quietly linear-and-wrong.

```scheme
(%ok (eq? (lit alpha) (lit alpha)))
```
---
    *** ERROR: ok

### distinct symbols are distinguishable

covers: eq?

```scheme
(%ok (match ((eq? (lit alpha) (lit beta)) ()) (#t 1)))
```
---
    *** ERROR: ok

### a list is a spine of pairs ending in nil

covers: pair first rest

```scheme
(def l (pair 1 (pair 2 (pair 3 ()))))
(%ok (match ((= (first l) 1) (match ((= (first (rest l)) 2) (match ((= (first (rest (rest l))) 3) (eq? (rest (rest (rest l))) ())) (#t ()))) (#t ()))) (#t ())))
```
---
    *** ERROR: ok

### same? is identity, distinct from eq?

covers: same?

```scheme
(def p (pair 1 2))
(%ok (same? p p))
```
---
    *** ERROR: ok
