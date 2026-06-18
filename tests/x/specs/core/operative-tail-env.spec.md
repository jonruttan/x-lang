# Operative tail-position env integrity

An operative (`op`) evaluated in tail position must restore the caller's
environment on exit, so the next form the caller evaluates sees the correct
scope. The tricky case is an operative whose body runs a nested TCO recursion
inside `(eval expr e)` -- the `$"..."` string-interpolation operative parses its
holes that way -- evaluated in **if-tail (simple-TCO)** position: its tail can
leave the env-alist head on a frame that is neither the op's formals nor the
caller. `x_op_restore` (src/x-eval.c) must detect that the head no longer chains
to the caller and restore it, rather than leaking the foreign frame.

Without the fix, a second interpolation (or any closure-variable reference) after
an if-tail interpolation reads its variable as Unbound.

## env survives an if-tail operative

### a closure var is still bound after an if-tail interpolation

```scheme
((fn (_ x) (do (if #t $"a{x}" "") x)) 9)
```
---
    9

### an expression over a closure var is still evaluable afterward

```scheme
((fn (_ x) (do (if #t $"a{x}" "") (+ x 1))) 9)
```
---
    10

### a let-frame interpolation likewise leaves scope intact

```scheme
((fn (_ x) (do (let ((q 0)) $"a{x}") x)) 9)
```
---
    9

## two interpolations in one form

### both in if-tail position resolve their holes

```scheme
((fn (_ x) (str (if #t $"a{x}" "") (if #t $"b{x}" ""))) 9)
```
---
    "a9b9"

### a leading if-tail interpolation does not corrupt a following direct one

```scheme
((fn (_ x) (str (if #t $"a{x}" "") $"b{x}")) 9)
```
---
    "a9b9"
