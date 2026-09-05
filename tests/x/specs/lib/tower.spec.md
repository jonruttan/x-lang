# @lib ../tests/x/lib/tower.x
# @weight 5

The numeric tower's mixed-type policy on generic functions (x/num/tower):
seven generics (num+ num- num* num/ num% num< num=) with one method per
type, ops-cell shims that keep same-type pairs on each module's fast
worker, and lattice-directed promotion for mixed pairs. An unrelated pair
is a teaching error at the generic door.

## same-type stays on the workers

### rational arithmetic through the shims

```x
(display (list (+ 1/2 1/3) (< 1/3 1/2) (= 1/2 2/4)))
```
---
    (5/6 #t #t)

### the generics are callable values

```x
(display (list (num+ 1/2 1/3) (num= 1/2 1/2)))
```
---
    (5/6 #t)

## mixed pairs promote through the lattice

### rational + float promotes to float

```x
(display (+ 1/2 0.25))
```
---
    0.75

### int + rational promotes to rational

```x
(display (+ 1 1/2))
```
---
    3/2

### float + complex promotes to complex

```x
(display (+ 1+2i 0.5))
```
---
    1.5+2i

### mixed ordering promotes too

```x
(display (< 1/3 0.5))
```
---
    #t

## the unrelated pair

### the generic door errors, naming both types

The recorded hole: bigint and rational declare no cvt relation. Through
the generic door that is now a TEACHING error.

```x
(display (guard (e 'loud) (num+ 123456789012345678901234567890 1/2)))
```
---
    loud

### the bare operators reach the same door

The C arbitration punts on this pair -- both sides carry handlers and
neither declares the other -- and its raw fallback read payload words
as integers (#584, caught by the cross-engine fuzzer as address
garbage).  The bigint folds now ask %big-mixed-check first, which reads
the same from/ops cells the C arbitration walks and raises the
lattice's teaching error for exactly the punted pair, in EVERY dialect
profile (the generics below are an optional import; the folds are not).
Binary % < = still call the C prims bare and keep the raw fallback --
that residue stays open on #584.

```x
(display (list
  (guard (e 'loud) (+ 123456789012345678901234567890 1/2))
  (guard (e 'loud) (- 1/2 123456789012345678901234567890))
  (guard (e 'loud) (* 123456789012345678901234567890 1/2))))
```
---
    (loud loud loud)

### declared pairs still promote through the folds

```x
(display (list (+ 123456789012345678901234567890 1) (+ 1 1/2)))
```
---
    (123456789012345678901234567891 3/2)

### complex sits ordering out at the generic door too

```x
(display (guard (e 'unordered) (num< 1+2i 3+4i)))
```
---
    unordered

## decimal at the generic door

### same-type pairs stay on decimal's own worker

```x
(display (num+ 0.1d 0.2d))
```
---
    0.3d

### float promotes into decimal, which absorbs it exactly

```x
(display (num* 2d 3.5))
```
---
    7d

### rational promotes too, at the current precision

```x
(display (num= 1/2 0.5d))
```
---
    #t

### complex still absorbs the decimal, not the other way round

```x
(display (Complex complex? (num+ 1+2i 0.5d)))
```
---
    #t
