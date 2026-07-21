# Dialect entry points (smoke)

The shipped dialects had **zero** end-to-end coverage until this file (#70).
Every numeric spec runs against a bespoke `@lib` harness, which passes -- so the
tower is well covered while the launchers users actually run were covered
not at all. That is how #49 shipped: a dialect that cannot add two numbers.

These run each entry point **as the README documents it** -- `@lib <dialect>`
is exactly `cat lib/<dialect> program.x | ./x`. That distinction is the whole
point: `x-base.x` has no `(repl)`, so its forms reach the C read-eval loop,
while the dialect entries (`he.x`, `xe.x`, `rn.x`) end with `(repl)` and go
through the x-lang REPL reader instead. #49 lives on the second path only.

The noble-gas rename (#95) named the entries he/xe/rn; `x.x` is the
default pointer (bare `sh x.sh` boots helium), and its group proves the
pointer path itself boots -- `check-dialect-cover` demands a group per
`lib/*.x` file. (The transitional `x-and.x`/`x-or.x` shims and their
groups are gone; dialect-cover's reverse check enforced the removal.)

Keep one taste-level form per dialect feature here. This file is a smoke test,
not a tower suite -- depth belongs in `e2e/numeric-tower.spec.md`.

# @lib he.x

## he.x -- helium, the light dialect

### arithmetic

```scheme
(+ 2 3)
```
---
    5

### the standard library is loaded

```scheme
(List length (list 1 2 3))
```
---
    3

### strings

```scheme
(Str upcase "abc")
```
---
    "ABC"

# @lib x.x

## x.x -- the default pointer (boots helium)

### arithmetic through the pointer

```scheme
(+ 2 3)
```
---
    5

### the standard library is loaded through the pointer

```scheme
(List length (list 1 2 3))
```
---
    3

# @lib x-core.x

## x-core.x -- the core library (no tower, no banner)

### arithmetic

```scheme
(+ 2 3)
```
---
    5

### classes are available

```scheme
(List length (list 1 2 3))
```
---
    3

# @lib x-base.x

## x-base.x -- the tower, no repl

### rationals

```scheme
(+ 1/3 1/6)
```
---
    1/2

### complex

```scheme
(* 1+2i 3+4i)
```
---
    -5+10i

### integers still work

```scheme
(* 2 3)
```
---
    6

# @lib xe.x

## xe.x -- xenon, the stable tower dialect

### multiplication

```scheme
(* 2 3)
```
---
    6

### complex multiplication -- the README's own snippet

```scheme
(* 1+2i 3+4i)
```
---
    -5+10i

### rationals -- the README's other tower snippet (#49)

Crashed until #49: the compiled rational analyser captured an unrooted
anonymous closure for its sign state, so a collect freed the code the next
leading `+`/`-` jumped into.

```scheme
(+ 1/3 1/6)
```
---
    1/2

### a leading sign no longer crashes the repl reader (#49)

```scheme
(- 5 3)
```
---
    2

### signed literals read correctly (#49)

```scheme
(+ -7 2)
```
---
    -5

# @lib rn.x

## rn.x -- radon, the experimental tower dialect

### multiplication

```scheme
(* 2 3)
```
---
    6

### complex multiplication

```scheme
(* 1+2i 3+4i)
```
---
    -5+10i

### rationals (#49)

```scheme
(+ 1/3 1/6)
```
---
    1/2

### a leading sign no longer crashes the repl reader (#49)

```scheme
(- 5 3)
```
---
    2
