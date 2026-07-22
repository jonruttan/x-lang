# Set: membership over a Dict

## construction

### make yields an empty set

```scheme
(do (import x/type/set) ((Set make) empty?))
```
---
    #t

### of builds a set variadically (duplicates collapse)

```scheme
(do (import x/type/set) ((Set of 1 2 2 3) length))
```
---
    3

### from-list collapses duplicates

```scheme
(do (import x/type/set) ((Set from-list (list 1 2 2 3 1)) length))
```
---
    3

### string elements collapse by content

```scheme
(do (import x/type/set)
  ((Set from-list (list "a" (Str8 append "" "a") "b")) length))
```
---
    2

## membership

### add! then has?

```scheme
(do (import x/type/set)
  (let ((s (Set make))) (s add! 'x) (s has? 'x)))
```
---
    #t

### absent element is not a member

```scheme
(do (import x/type/set)
  (if ((Set make) has? 'x) "y" "n"))
```
---
    "n"

### add! is idempotent

```scheme
(do (import x/type/set)
  (let ((s (Set make))) (s add! 5) (s add! 5) (s length)))
```
---
    1

### del! removes membership

```scheme
(do (import x/type/set)
  (let ((s (Set from-list (list 1 2))))
    (s del! 1)
    (list (s has? 1) (s length))))
```
---
    (#f 1)

### mutators chain

```scheme
(do (import x/type/set)
  ((((Set make) add! 1) add! 2) length))
```
---
    2

## extraction

### ->list returns the members

```scheme
(do (import x/type/set)
  (List sort < ((Set from-list (list 3 1 2)) ->list)))
```
---
    (1 2 3)

## uninitialized instances fail loudly (constructor adjudication)

### a generic-new instance raises kind-'state at first use; make constructs

```scheme
(do (import x/type/set)
  (guard (e (list (Err kind-of e) (((Set make) add! 3) has? 3)))
    ((Set new) add! 3)))
```
---
    ('state #t)

## algebra (new sets; operands unmutated)

### union holds the members of either operand

```scheme
(do (import x/type/set)
  (let ((a (Set of 1 2)) (b (Set of 2 3)))
    (list ((a union b) length) (a length) (b length))))
```
---
    (3 2 2)

### intersection holds the common members

```scheme
(do (import x/type/set)
  (List sort < (((Set of 1 2 3) intersection (Set of 2 3 4)) ->list)))
```
---
    (2 3)

### difference drops the other set's members

```scheme
(do (import x/type/set)
  (((Set of 1 2 3) difference (Set of 2 3 4)) ->list))
```
---
    (1)

### copy is independent of the original

```scheme
(do (import x/type/set)
  (let ((a (Set of 1 2)))
    (let ((b (a copy)))
      (b add! 3)
      (list (a length) (b length)))))
```
---
    (2 3)

## predicates

### subset? / superset?

```scheme
(do (import x/type/set)
  (let ((small (Set of 1 2)) (big (Set of 1 2 3)))
    (list (small subset? big) (big subset? small) (big superset? small))))
```
---
    (#t #f #t)

### the empty set is a subset of anything

```scheme
(do (import x/type/set)
  ((Set make) subset? (Set of 1)))
```
---
    #t

### =? ignores insertion order

```scheme
(do (import x/type/set)
  (list ((Set of 1 2) =? (Set of 2 1)) ((Set of 1 2) =? (Set of 1 3))))
```
---
    (#t #f)

### set? recognises sets and rejects the rest

```scheme
(do (import x/type/set)
  (list (Set set? (Set make)) (Set set? 5)))
```
---
    (#t #f)

## iteration

### for-each visits every member

```scheme
(do (import x/type/set)
  (let ((sum (pair 0 ())))
    ((Set of 1 2 3) for-each (fn (_ x) (%set-first! sum (+ (first sum) x))))
    (first sum)))
```
---
    6

### filter keeps the members passing the predicate

```scheme
(do (import x/type/set)
  (List sort < (((Set of 1 2 3 4) filter (fn (_ x) (> x 2))) ->list)))
```
---
    (3 4)

### map collapses duplicate images

```scheme
(do (import x/type/set)
  (((Set of 1 2 3) map (fn (_ x) (* x 0))) length))
```
---
    1

### fold accumulates over the members

```scheme
(do (import x/type/set)
  ((Set of 1 2 3) fold (fn (_ a x) (+ a x)) 0))
```
---
    6

## instance members (identity)

### equal-but-distinct instances are distinct members

```scheme
(do (import x/type/set)
  (def-class C () row col)
  (let ((a (C new row 0 col 1)) (b (C new row 0 col 1)) (s (Set make)))
    (s add! a) (s add! a) (s add! b)
    (list (s length) (s has? a) ((s del! a) has? a) (s has? b))))
```
---
    (2 #t #f #t)
