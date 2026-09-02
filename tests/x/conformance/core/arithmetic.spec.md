# Conformance: machine arithmetic (profile `core`)

THIS IS THE ENGINE LEVEL, AND IT IS NOT WHAT `docs/spec.md` §5 DESCRIBES. That
section says "all arithmetic operators are variadic", and it is right about the
LANGUAGE -- variadic `+` is `lib/x/core/arithmetic.x` sitting on top of a binary
primitive, and the numeric tower's promotion, the type-refusal handlers and the
error messages are all library code. None of it is present here. An engine must
provide the machine operation; everything above it is x-lang's job.

The `covers:` labels below name the BARE bindings (`+`, `-`, ...) rather than the
catalog coordinates (`int/+`, ...), because that is what these cases call. The same
primitive is reachable both ways -- bare, and through the catalog -- and the library
uses both doors, so they are tracked as separate coverage.

That distinction is the reason this suite loads nothing: a test that reaches `+`
through the library is testing the library, and would pass against an engine whose
primitive was subtly wrong.

### addition is the machine operation on two integers

covers: +

```x
(%ok (= (+ 2 3) 5))
```
---
    *** ERROR: ok

### subtraction, multiplication

covers: - *

```x
(%ok (match ((= (- 10 4) 6) (= (* 6 7) 42)) (#t ())))
```
---
    *** ERROR: ok

### division truncates toward zero

covers: /

Truncation, not floor: an engine that floors would answer -4 for the second.

```x
(%ok (match ((= (/ 7 2) 3) (= (/ -7 2) -3)) (#t ())))
```
---
    *** ERROR: ok

### modulo takes the sign of the DIVIDEND

covers: %

C remainder semantics, not Euclidean: `(% -7 2)` is -1, not 1. An engine
implementing a mathematical modulo would answer 1 and pass every positive-operand
test ever written, which is why the negative case is the one asserted.

```x
(%ok (match ((= (% 7 2) 1) (= (% -7 2) -1)) (#t ())))
```
---
    *** ERROR: ok

### comparison answers something a conditional accepts

covers: < =

The suite deliberately does NOT pin WHICH truthy value a comparison yields -- the
engine's `eq?` answers with a `t` symbol rather than `#t`, and pinning that would
freeze a representation detail. What an engine must guarantee is that the answer
works as a test.

```x
(%ok (match ((< 1 2) (match ((= 2 2) 1) (#t ()))) (#t ())))
```
---
    *** ERROR: ok

### a false comparison is falsy

covers: <

```x
(%ok (match ((< 2 1) ()) (#t 1)))
```
---
    *** ERROR: ok

### the bitwise family

covers: & | ^ ~ << >>

Complement is asserted as `(~ 0)` = -1, which is two's complement and not merely
"some bits flipped" -- an engine using a sign-magnitude or ones-complement integer
would answer differently.

```x
(%ok (match ((= (& 12 10) 8) (match ((= (| 12 10) 14) (match ((= (^ 12 10) 6) (match ((= (<< 1 4) 16) (match ((= (>> 16 4) 1) (= (~ 0) -1)) (#t ()))) (#t ()))) (#t ()))) (#t ()))) (#t ())))
```
---
    *** ERROR: ok

### arity beyond two is UNSPECIFIED -- deliberately untested

This engine takes the first two arguments and silently ignores the rest, so
`(+ 1 2 3)` is 3. That is an accident of the C implementation, not a contract:
requiring it would bind every future engine to reproduce a wart, and forbidding it
would fail the only engine that exists. The library never calls a primitive that
way -- `lib/x/core/arithmetic.x` folds pairwise -- so nothing depends on the
answer. An engine may ignore the extras, raise, or accept them variadically.

Recorded here rather than left silent, because "no case exists" and "no case
should exist" look identical in a coverage report.
