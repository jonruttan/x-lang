# Primitives catalog: the registry protocol

## prim-ref

### fetches a C prim by identity

```scheme
((prim-ref 'int '+) 2 3)
```
---
    5

### absent entry is nil

```scheme
(null? (prim-ref 'no-such-ns 'nothing))
```
---
    #t

## prim-reg!

### registers an x-lang fn under a new namespace

```scheme
(do
  (prim-reg! 'spec-reg 'double (fn (_ n) (* n 2)))
  ((prim-ref 'spec-reg 'double) 21))
```
---
    42

### registers into an existing namespace

```scheme
(do
  (prim-reg! 'spec-reg2 'a (fn (_ n) (+ n 1)))
  (prim-reg! 'spec-reg2 'b (fn (_ n) (+ n 2)))
  (+ ((prim-ref 'spec-reg2 'a) 10)
     ((prim-ref 'spec-reg2 'b) 10)))
```
---
    23

### holds any value, not just callables

```scheme
(do
  (prim-reg! 'spec-val 'answer 42)
  (prim-ref 'spec-val 'answer))
```
---
    42

### re-registration shadows the older entry

```scheme
(do
  (prim-reg! 'spec-shadow 'v 1)
  (prim-reg! 'spec-shadow 'v 2)
  (prim-ref 'spec-shadow 'v))
```
---
    2

### returns nil (side-effecting)

```scheme
(null? (prim-reg! 'spec-ret 'x 9))
```
---
    #t

## prim-domain

### nil for an unknown namespace

```scheme
(null? (prim-domain 'no-such-ns))
```
---
    #t

### non-nil after a registration

```scheme
(do
  (prim-reg! 'spec-dom 'm 1)
  (null? (prim-domain 'spec-dom)))
```
---
    #f
