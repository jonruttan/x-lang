# @weight 1
## iter

### iterates a list

```x
(Iter ->list (Iter new (list 1 2 3)))
```
---
    (1 2 3)

### iterates a vector

```x
(Iter ->list (Iter new (Vector of 10 20 30)))
```
---
    (10 20 30)

### iterates a string by code point

```x
(Iter ->list (Iter new "abc"))
```
---
    (#\a #\b #\c)

### empty list yields an empty iterator

```x
(null? (Iter ->list (Iter new (list))))
```
---
    #t

### empty vector yields an empty iterator

```x
(null? (Iter ->list (Iter new (Vector of))))
```
---
    #t

### ->list at 16K elements (crash regression)

The drain recursed in argument position -- (pair h (drain it)) -- one C
eval frame group per element, so a ~16K+ iterator crashed the C stack
(the shape %map1 had before 2026-09-01).  Now tail accumulate +
%rev-onto, reverse once; the end probes pin that order survived the
reverse.

```x
(def l (Iter ->list (Iter new (List range 0 16384))))
(list (List length l) (List ref 0 l) (List ref 16383 l))
```
---
    (16384 0 16383)

## iter-empty?

### reports exhaustion across a step

```x
(do (def it (Iter new (list 1))) (def before (Iter empty? it)) (Iter next it) (list before (Iter empty? it)))
```
---
    (#f #t)

## iter-next

### advances element by element

```x
(do (def it (Iter new (list 7 8 9))) (list (Iter next it) (Iter next it) (Iter next it)))
```
---
    (7 8 9)

## iter-fold

### left-folds the remaining elements

```x
(Iter fold + 0 (Iter new (list 1 2 3 4)))
```
---
    10

## iter-for-each

### visits every element

```x
(do (def %acc (list 0)) (Iter for-each (fn (_ x) (%set-first! %acc (+ (first %acc) x))) (Iter new (Vector of 1 2 3 4))) (first %acc))
```
---
    10

## iter (class instances)

### iterates a def-class instance as name/value pairs

```x
(do (def-class Pt () (x 0) (y 0)) (def p (new Pt x 3 y 4)) (Iter ->list (Iter new p)))
```
---
    (('x . 3) ('y . 4))

## make-iter

### builds an iterator from a custom step function (pure: state -> (value . next-state))

```x
(do (def it (Iter make (fn (self st) (if (null? st) () (pair (first st) (rest st)))) (list 5 6))) (Iter ->list it))
```
---
    (5 6)

## step (the functional door)

### yields (value . next-iterator) and leaves the source untouched

```x
(do (import x/type/iter)
  (def it (Iter new (list 7 8)))
  (def s (Iter step it))
  (list (first s) (Iter next (rest s)) (Iter next it)))
```
---
    (7 8 7)

### returns nil on an exhausted iterator

```x
(do (import x/type/iter) (null? (Iter step (Iter new ()))))
```
---
    #t

## iter?

### true for an iterator

```x
(Iter iter? (Iter new (list 1 2 3)))
```
---
    #t

### false for the underlying list

```x
(if (Iter iter? (list 1 2 3)) "yes" "no")
```
---
    "no"

### false for an integer

```x
(if (Iter iter? 42) "yes" "no")
```
---
    "no"

## refuses a non-iterator (crash regression)

The driver prims read an iterator's box behind a type probe, and a `nil` is
typeless -- the probe had no handle to read, so it walked off one and the
process died.  `(Iter new)` answered exactly that nil for a value whose
type carries no iter slot, which put the crash behind every `List` door
via `(List from-seq)`: `(List length 5)` segfaulted, and so did `(List
length (%type-alist))` -- the reader's type alist is a C-built spine, so
`pair?` answers `#f` on it and `from-seq` sent it to `Iter`.  Those
spines are walked with the bare `first`/`rest` accessors instead;
`docs/sandboxing-tutorial.md` says why.  Every public door now probes its
iterator once on the way in.

### new refuses an integer

```x
(Iter new 5)
```
---
    Error: #<err:type Iter new: not iterable>

### new refuses a fn

```x
(Iter new (fn (_) 1))
```
---
    Error: #<err:type Iter new: not iterable>

### new refuses the reader's type alist

```x
(Iter new (%type-alist))
```
---
    Error: #<err:type Iter new: not iterable>

### the bare accessors still walk the type alist

```x
(def go (fn (self al n) (if (null? al) n (self (rest al) (+ n 1)))))
(> (go (%type-alist) 0) 0)
```
---
    #t

### ->list refuses nil

```x
(Iter ->list ())
```
---
    Error: #<err:type Iter ->list: not an iterator>

### next refuses nil

```x
(Iter next ())
```
---
    Error: #<err:type Iter next: not an iterator>

### step refuses nil

```x
(Iter step ())
```
---
    Error: #<err:type Iter step: not an iterator>

### empty? refuses nil

```x
(Iter empty? ())
```
---
    Error: #<err:type Iter empty?: not an iterator>

### fold refuses nil

```x
(Iter fold + 0 ())
```
---
    Error: #<err:type Iter fold: not an iterator>

### for-each refuses nil

```x
(Iter for-each (fn (_ x) x) ())
```
---
    Error: #<err:type Iter for-each: not an iterator>

### an empty sequence is still an iterator, not nil

```x
(list (Iter empty? (Iter new ())) (Iter empty? (Iter new (Vector of))))
```
---
    (#t #t)
