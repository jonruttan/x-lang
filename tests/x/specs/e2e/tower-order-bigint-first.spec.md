# Numeric tower load order: bigint first, float later
# @weight 3

The bundle order under plain x-core imports: bigint is already joined when
float.x files its when-entry, so the bigint->float conversion installs
immediately at float load. The reverse order lives in
tower-order-float-first.spec.md; each order needs its own file because a
spec file is one interpreter batch.

PARSE-BEFORE-EVAL RULE: a type's literal syntax works from the top-level
form AFTER its import, never inside the same form (the whole form is
tokenized before the import evaluates). Literal tests therefore follow
their import's test as separate forms.

## bigint then float

### bigint works alone

```x
(import x/num/bigint)
(Bigint + 9223372036854775807 1)
```
---
    9223372036854775808

### bigint literals parse from the next form on

```x
(Bigint bigint? 10000000000000000000)
```
---
    #t

### float joins later; the conversion installed at float load

```x
(import x/num/float)
(import x/sys/pact)
(def %t-cv (prim-ref 'convert 'to))
(def %t-fh (Pact get 'float))
(def %t-big (Bigint + 9223372036854775807 1))
(def %t-f (%t-cv %t-big %t-fh))
(if (Float float? %t-f)
  (= (+ %t-f %t-f) (%t-cv (Bigint + %t-big %t-big) %t-fh))
  ())
```
---
    #t

### mixed literal arithmetic in the next form

```x
(= (+ 0.0 10000000000000000000) 10000000000000000000.0)
```
---
    #t

### rational on top of both

```x
(import x/num/rational)
(Rational rational? (Rational / 2 6))
```
---
    #t

### rational literals parse from the next form on

```x
(+ 1/3 1/6)
```
---
    1/2
