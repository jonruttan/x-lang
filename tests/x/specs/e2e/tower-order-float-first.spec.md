# Numeric tower load order: float first, bigint later
# @weight 3

The tower's members must load in any order under plain x-core (the bundles
pre-load everything in one fixed order, so only these specs exercise the
others). This file is the order the REPL repro used: `(import x/num/rational)`
pulls in float with NO bigint loaded -- which used to raise
`Unbound SYMBOL '%bigint'` from float.x's load-order guard -- and bigint
arrives later, at which point the pact installs the bigint->float conversion.
The reverse order lives in tower-order-bigint-first.spec.md; each order needs
its own file because a spec file is one interpreter batch.

PARSE-BEFORE-EVAL RULE: a literal is tokenized when its enclosing top-level
form is READ, so a type's literal syntax works from the form AFTER the
import, never inside the same form as the import (there, e.g. a pre-float
`x.y` tokenizes as `x . y` -- a dotted pair). Each test below is its own
top-level form, so literal tests simply follow their import's test.

## before bigint

### rational imports without bigint (the repro)

```x
(import x/num/rational)
(Rational rational? (Rational / 1 3))
```
---
    #t

### rational literals parse from the next form on

```x
(Rational rational? 1/3)
```
---
    #t

### float literals and arithmetic work without bigint

```x
(+ 0.5 0.25)
```
---
    0.75

## after bigint

### bigint joins later; the pact installs bigint->float

```x
(import x/num/bigint)
(import x/sys/pact)
(def %t-big1 (Bigint + 9223372036854775807 1))
(def %t-f1 ((prim-ref 'convert 'to) %t-big1 (Pact get 'float)))
(Float float? %t-f1)
```
---
    #t

### bigint literals parse from the next form on

```x
(Bigint bigint? 10000000000000000000)
```
---
    #t

### mixed literal arithmetic across the whole tower

```x
(= (+ 0.0 10000000000000000000) 10000000000000000000.0)
```
---
    #t

### the conversion is value-correct (2^63 is float-exact, and doubling agrees)

```x
(def %t-cv2 (prim-ref 'convert 'to))
(def %t-fh2 (Pact get 'float))
(def %t-big2 (Bigint + 9223372036854775807 1))
(def %t-f2 (%t-cv2 %t-big2 %t-fh2))
(= (+ %t-f2 %t-f2) (%t-cv2 (Bigint + %t-big2 %t-big2) %t-fh2))
```
---
    #t

### the converter honours the sign

```x
(def %t-cv3 (prim-ref 'convert 'to))
(def %t-fh3 (Pact get 'float))
(def %t-big3 (Bigint + 9223372036854775807 1))
(= (+ (%t-cv3 %t-big3 %t-fh3) (%t-cv3 (Bigint - 0 %t-big3) %t-fh3))
   (%t-cv3 0 %t-fh3))
```
---
    #t
