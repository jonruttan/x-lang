## Type alist

### returns non-nil

```scheme
(not (null? (Type alist)))
```
---
    #t

## Type by-atom

### finds integer type

```scheme
(not (null? (Type by-atom (type-of 42))))
```
---
    #t

### finds string type

```scheme
(not (null? (Type by-atom (type-of "hello"))))
```
---
    #t

### finds symbol type

```scheme
(not (null? (Type by-atom (type-of (lit foo)))))
```
---
    #t

### returns nil for unknown

```scheme
(null? (Type by-atom 999))
```
---
    #t

## Type io

### returns non-nil for integer type

```scheme
(not (null? (Type io (Type by-atom (type-of 42)))))
```
---
    #t

## Type cvt

### returns non-nil for integer type

```scheme
(not (null? (Type cvt (Type by-atom (type-of 42)))))
```
---
    #t

## Type write-cell

### returns non-nil

```scheme
(not (null? (Type write-cell (Type by-atom (type-of 42)))))
```
---
    #t

## Type analyse-cell

### returns non-nil

```scheme
(not (null? (Type analyse-cell (Type by-atom (type-of 42)))))
```
---
    #t

## Type from-cell

### returns conversion data for string type

```scheme
(not (null? (Type from-cell (Type by-atom (type-of "")))))
```
---
    #t

## Type to-cell

### returns conversion data for integer type

```scheme
(not (null? (Type to-cell (Type by-atom (type-of 42)))))
```
---
    #t

## Type push-write / Type pop-write

### push adds handler, pop removes it

```scheme
(do (def ts (Type by-atom (type-of 42)))
    (def before (first (Type write-cell ts)))
    (Type push-write ts (fn (_ x) x))
    (def during (first (Type write-cell ts)))
    (Type pop-write ts)
    (def after (first (Type write-cell ts)))
    (if (eq? before after) "restored" "broken"))
```
---
    "restored"

## Type cast!

### changes object type identity

```scheme
(do (def a (pair 1 2))
    (def orig-type (type-of a))
    (Type cast! a "hello")
    (eq? (type-of a) (type-of "hello")))
```
---
    #t
