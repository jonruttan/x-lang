# Conformance: the evaluation model (profile `core`)

The normative behaviours of `docs/spec.md` §1, asserted against the ENGINE with no
library present. Every case reads `(%ok EXPR)`, which the runner's prelude turns
into `*** ERROR: ok` when EXPR is truthy and `*** ERROR: no` when it is not.

x-lang's model is the inverse of most Lisps: operatives are the default and
applicatives are the special case. An engine that evaluates arguments by default
would pass a surprising number of naive tests, so the operative cases below are
written so that evaluating an argument is an ERROR, not merely a different answer.

### a symbol evaluates to its binding

covers: def

```x
(def x 42)
(%ok (= x 42))
```
---
    *** ERROR: ok

### set! rebinds an existing name

covers: set!

```x
(def x 1)
(set! x 2)
(%ok (= x 2))
```
---
    *** ERROR: ok

### fn is applicative -- arguments arrive evaluated

covers: fn

```x
(def f (fn (self a) a))
(%ok (= (f (+ 1 2)) 3))
```
---
    *** ERROR: ok

### fn receives itself as argument zero

covers: fn

```x
(def count (fn (self n) (match ((= n 0) 0) (#t (+ 1 (self (- n 1)))))))
(%ok (= (count 5) 5))
```
---
    *** ERROR: ok

### op is operative -- arguments arrive UNEVALUATED

covers: op

An unbound symbol is passed. If the engine evaluated it the case would die with
`Unbound SYMBOL`, so this distinguishes the two models rather than just observing
a value.

```x
(def q (op (x) e x))
(%ok (eq? (q no-such-binding-anywhere) (lit no-such-binding-anywhere)))
```
---
    *** ERROR: ok

### an operative can evaluate an argument in the CALLER's environment

covers: op eval

```x
(def deref (op (x) e (eval x e)))
(def y 9)
(%ok (= (deref y) 9))
```
---
    *** ERROR: ok

### lit returns its argument unevaluated

covers: lit

```x
(%ok (eq? (lit foo) (lit foo)))
```
---
    *** ERROR: ok

### match takes the first truthy arm

covers: match

```x
(%ok (= (match ((= 1 2) 10) ((= 2 2) 20) (#t 30)) 20))
```
---
    *** ERROR: ok

### match falls through to the default arm

covers: match

```x
(%ok (= (match ((= 1 2) 10) ((= 3 4) 20) (#t 30)) 30))
```
---
    *** ERROR: ok

### guard catches an error and yields the handler's value

covers: guard error

```x
(%ok (eq? (guard (e (lit caught)) (error "boom")) (lit caught)))
```
---
    *** ERROR: ok

### guard is transparent when nothing is raised

covers: guard

```x
(%ok (= (guard (e 0) (+ 20 22)) 42))
```
---
    *** ERROR: ok

### call/cc gives an escape continuation

covers: call/cc

```x
(%ok (= (call/cc (fn (self k) (k 7))) 7))
```
---
    *** ERROR: ok

### call/cc returns its body's value when the continuation is unused

covers: call/cc

```x
(%ok (= (call/cc (fn (self k) 5)) 5))
```
---
    *** ERROR: ok

### apply spreads a list as the argument spine

covers: apply

```x
(def add (fn (self a b) (+ a b)))
(%ok (= (apply add (pair 1 (pair 2 ()))) 3))
```
---
    *** ERROR: ok

### tail position does not grow the stack

covers: fn match

60000 frames is far past any C stack -- the same depth crashes this engine
outright when the recursion is NOT in tail position, which is what makes this a
test of tail calls rather than of patience.

```x
(def loop (fn (self n) (match ((= n 0) (lit done)) (#t (self (- n 1))))))
(%ok (eq? (loop 60000) (lit done)))
```
---
    *** ERROR: ok
