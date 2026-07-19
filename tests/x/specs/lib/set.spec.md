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

## new refuses (constructor adjudication)

### new raises kind-'state; make is the constructor

```scheme
(do (import x/type/set)
  (guard (e (list (Err kind-of e) (((Set make) add! 3) has? 3)))
    (Set new)))
```
---
    ('state #t)
