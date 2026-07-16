# Numeric tower load order: bignum first, float later

The bundle order under plain x-core imports: bignum is already joined when
float.x files its when-entry, so the bignum->float conversion installs
immediately at float load. The reverse order lives in
tower-order-float-first.spec.md; each order needs its own file because a
spec file is one interpreter batch.

PARSE-BEFORE-EVAL RULE: a type's literal syntax works from the top-level
form AFTER its import, never inside the same form (the whole form is
tokenized before the import evaluates). Literal tests therefore follow
their import's test as separate forms.

## bignum then float

### bignum works alone

```scheme
(import x/num/bignum)
(Bignum + 9223372036854775807 1)
```
---
    9223372036854775808

### bignum literals parse from the next form on

```scheme
(Bignum bignum? 10000000000000000000)
```
---
    #t

### float joins later; the conversion installed at float load

```scheme
(import x/num/float)
(import x/sys/pact)
(def %t-cv (prim-ref (lit convert) (lit to)))
(def %t-fh (Pact get (lit float)))
(def %t-big (Bignum + 9223372036854775807 1))
(def %t-f (%t-cv %t-big %t-fh))
(if (Float float? %t-f)
  (= (+ %t-f %t-f) (%t-cv (Bignum + %t-big %t-big) %t-fh))
  ())
```
---
    #t

### mixed literal arithmetic in the next form

```scheme
(= (+ 0.0 10000000000000000000) 10000000000000000000.0)
```
---
    #t

### rational on top of both

```scheme
(import x/num/rational)
(Rational rational? (Rational / 2 6))
```
---
    #t

### rational literals parse from the next form on

```scheme
(+ 1/3 1/6)
```
---
    1/2
