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
the generic door that is now a TEACHING error.

```scheme
(display (guard (e 'loud) (num+ 123456789012345678901234567890 1/2)))
```
---
    loud

### the bare operators reach the same door

The C arbitration used to punt on this pair -- both sides carry
handlers and neither declares the other -- and its raw fallback read
payload words as integers (#584, caught by the cross-engine fuzzer as
address garbage).  The arbitration itself (x_type_op_try and its rust
twin) now decides, in every dialect profile with no lib-side guard to
keep in step: = answers #f -- unrelated values are not equal, a
question with an answer (x-python's tuple-vs-list == leans on it) --
and every op with no answer absent a declared relation raises the
teaching error.

```scheme
(display (list
  (guard (e 'loud) (+ 123456789012345678901234567890 1/2))
  (guard (e 'loud) (- 1/2 123456789012345678901234567890))
  (guard (e 'loud) (* 123456789012345678901234567890 1/2))
  (guard (e 'loud) (% 123456789012345678901234567890 1/2))
  (guard (e 'loud) (< 123456789012345678901234567890 1/2))
  (= 123456789012345678901234567890 1/2)
  (= 1/2 123456789012345678901234567890)))
```
---
    (loud loud loud loud loud #f #f)

### the teaching error names the unabsorbed type

Pinned exactly: the two engines must compose the identical message, or
the differential fuzzer reads the difference as an engine divergence.
One appended name is what the engine's error door offers; the second
operand's type is the one named.

```scheme
(display (guard (e e) (% 123456789012345678901234567890 1/2)))
```
---
    no declared promotion; declare the cvt relation for 'RATIONAL'

### declared pairs still promote through the folds

```scheme
(display (list (+ 123456789012345678901234567890 1) (+ 1 1/2)))
```
---
    (123456789012345678901234567891 3/2)

### complex sits ordering out at the generic door too

```scheme
(display (guard (e 'unordered) (num< 1+2i 3+4i)))
```
---
    unordered

## decimal at the generic door

### same-type pairs stay on decimal's own worker

```scheme
(display (num+ 0.1d 0.2d))
```
---
    0.3d

### float promotes into decimal, which absorbs it exactly

```scheme
(display (num* 2d 3.5))
```
---
    7d

### rational promotes too, at the current precision

```scheme
(display (num= 1/2 0.5d))
```
---
    #t

### complex still absorbs the decimal, not the other way round

```scheme
(display (Complex complex? (num+ 1+2i 0.5d)))
```
---
    #t
