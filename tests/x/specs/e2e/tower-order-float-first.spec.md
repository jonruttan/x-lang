# Numeric tower load order: float first, bignum later

The tower's members must load in any order under plain x-core (the bundles
pre-load everything in one fixed order, so only these specs exercise the
others). This file is the order the REPL repro used: `(import x/num/rational)`
pulls in float with NO bignum loaded -- which used to raise
`Unbound SYMBOL '%bignum'` from float.x's load-order guard -- and bignum
arrives later, at which point the pact installs the bignum->float conversion.
The reverse order lives in tower-order-bignum-first.spec.md; each order needs
its own file because a spec file is one interpreter batch.

PARSE-BEFORE-EVAL RULE: a literal is tokenized when its enclosing top-level
form is READ, so a type's literal syntax works from the form AFTER the
import, never inside the same form as the import (there, e.g. a pre-float
`x.y` tokenizes as `x . y` -- a dotted pair). Each test below is its own
top-level form, so literal tests simply follow their import's test.

## before bignum

### rational imports without bignum (the repro)

```scheme
(import x/num/rational)
(Rational rational? (Rational / 1 3))
```
---
    #t

### rational literals parse from the next form on

```scheme
(Rational rational? 1/3)
```
---
    #t

### float literals and arithmetic work without bignum

```scheme
(+ 0.5 0.25)
```
---
    0.75

## after bignum

### bignum joins later; the pact installs bignum->float

```scheme
(import x/num/bignum)
(import x/sys/pact)
(def %t-big1 (Bignum + 9223372036854775807 1))
(def %t-f1 ((prim-ref (lit convert) (lit to)) %t-big1 (Pact get (lit float))))
(Float float? %t-f1)
```
---
    #t

### bignum literals parse from the next form on

```scheme
(Bignum bignum? 10000000000000000000)
```
---
    #t

### mixed literal arithmetic across the whole tower

```scheme
(= (+ 0.0 10000000000000000000) 10000000000000000000.0)
```
---
    #t

### the conversion is value-correct (2^63 is float-exact, and doubling agrees)

```scheme
(def %t-cv2 (prim-ref (lit convert) (lit to)))
(def %t-fh2 (Pact get (lit float)))
(def %t-big2 (Bignum + 9223372036854775807 1))
(def %t-f2 (%t-cv2 %t-big2 %t-fh2))
(= (+ %t-f2 %t-f2) (%t-cv2 (Bignum + %t-big2 %t-big2) %t-fh2))
```
---
    #t

### the converter honors the sign

```scheme
(def %t-cv3 (prim-ref (lit convert) (lit to)))
(def %t-fh3 (Pact get (lit float)))
(def %t-big3 (Bignum + 9223372036854775807 1))
(= (+ (%t-cv3 %t-big3 %t-fh3) (%t-cv3 (Bignum - 0 %t-big3) %t-fh3))
   (%t-cv3 0 %t-fh3))
```
---
    #t
