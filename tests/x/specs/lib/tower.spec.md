# @lib ../tests/x/lib/tower.x
# @weight 5

The numeric tower's mixed-type policy on generic functions (x/num/tower):
seven generics (num+ num- num* num/ num% num< num=) with one method per
type, ops-cell shims that keep same-type pairs on each module's fast
worker, and lattice-directed promotion for mixed pairs. An unrelated pair
is a teaching error at the generic door.

## same-type stays on the workers

### rational arithmetic through the shims

```scheme
(display (list (+ 1/2 1/3) (< 1/3 1/2) (= 1/2 2/4)))
```
---
    (5/6 #t #t)

### the generics are callable values

```scheme
(display (list (num+ 1/2 1/3) (num= 1/2 1/2)))
```
---
    (5/6 #t)

## mixed pairs promote through the lattice

### rational + float promotes to float

```scheme
(display (+ 1/2 0.25))
```
---
    0.75

### int + rational promotes to rational

```scheme
(display (+ 1 1/2))
```
---
    3/2

### float + complex promotes to complex

```scheme
(display (+ 1+2i 0.5))
```
---
    1.5+2i

### mixed ordering promotes too

```scheme
(display (< 1/3 0.5))
```
---
    #t

## the unrelated pair

### the generic door errors, naming both types

The recorded hole: bigint and rational declare no cvt relation. Through
the generic door that is now a TEACHING error. (At the raw operator the
C arbitration still falls through for this one pair -- both sides carry
handlers and neither declares the other, so no x-lang code is ever
reached; routing it needs either the C-side arbitration fallback or the
exact rational-over-bigint arc. Recorded, not hidden.)

```scheme
(display (guard (e 'loud) (num+ 123456789012345678901234567890 1/2)))
```
---
    loud

### complex sits ordering out at the generic door too

```scheme
(display (guard (e 'unordered) (num< 1+2i 3+4i)))
```
---
    unordered
