# Primitives catalog: the registry protocol

## prim-ref

### fetches a C prim by identity

```scheme
((prim-ref (lit int) (lit +)) 2 3)
```
---
    5

### absent entry is nil

```scheme
(null? (prim-ref (lit no-such-ns) (lit nothing)))
```
---
    #t

## prim-reg!

### registers an x-lang fn under a new namespace

```scheme
(do
  (prim-reg! (lit spec-reg) (lit double) (fn (_ n) (* n 2)))
  ((prim-ref (lit spec-reg) (lit double)) 21))
```
---
    42

### registers into an existing namespace

```scheme
(do
  (prim-reg! (lit spec-reg2) (lit a) (fn (_ n) (+ n 1)))
  (prim-reg! (lit spec-reg2) (lit b) (fn (_ n) (+ n 2)))
  (+ ((prim-ref (lit spec-reg2) (lit a)) 10)
     ((prim-ref 'spec-reg2 'b) 10)))
```
---
    23

### holds any value, not just callables

```scheme
(do
  (prim-reg! (lit spec-val) (lit answer) 42)
  (prim-ref (lit spec-val) (lit answer)))
```
---
    42

### re-registration shadows the older entry

```scheme
(do
  (prim-reg! (lit spec-shadow) (lit v) 1)
  (prim-reg! (lit spec-shadow) (lit v) 2)
  (prim-ref (lit spec-shadow) (lit v)))
```
---
    2

### returns nil (side-effecting)

```scheme
(null? (prim-reg! (lit spec-ret) (lit x) 9))
```
---
    #t

## prim-domain

### nil for an unknown namespace

```scheme
(null? (prim-domain (lit no-such-ns)))
```
---
    #t

### non-nil after a registration

```scheme
(do
  (prim-reg! (lit spec-dom) (lit m) 1)
  (null? (prim-domain (lit spec-dom))))
```
---
    #f
