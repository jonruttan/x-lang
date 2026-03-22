## type-alist

### returns non-nil

```scheme
(not (null? (type-alist)))
```
---
    #t

## type-by-atom

### finds integer type

```scheme
(not (null? (type-by-atom (type-of 42))))
```
---
    #t

### finds string type

```scheme
(not (null? (type-by-atom (type-of "hello"))))
```
---
    #t

### finds symbol type

```scheme
(not (null? (type-by-atom (type-of (lit foo)))))
```
---
    #t

### returns nil for unknown

```scheme
(null? (type-by-atom 999))
```
---
    #t

## type-io

### returns non-nil for integer type

```scheme
(not (null? (type-io (type-by-atom (type-of 42)))))
```
---
    #t

## type-cvt

### returns non-nil for integer type

```scheme
(not (null? (type-cvt (type-by-atom (type-of 42)))))
```
---
    #t

## type-write-cell

### returns non-nil

```scheme
(not (null? (type-write-cell (type-by-atom (type-of 42)))))
```
---
    #t

## type-analyse-cell

### returns non-nil

```scheme
(not (null? (type-analyse-cell (type-by-atom (type-of 42)))))
```
---
    #t

## type-from-cell

### returns conversion data for string type

```scheme
(not (null? (type-from-cell (type-by-atom (type-of "")))))
```
---
    #t

## type-to-cell

### returns conversion data for integer type

```scheme
(not (null? (type-to-cell (type-by-atom (type-of 42)))))
```
---
    #t

## type-push-write / type-pop-write

### push adds handler, pop removes it

```scheme
(do (def ts (type-by-atom (type-of 42)))
    (def before (first (type-write-cell ts)))
    (type-push-write ts (fn (_ x) x))
    (def during (first (type-write-cell ts)))
    (type-pop-write ts)
    (def after (first (type-write-cell ts)))
    (if (eq? before after) "restored" "broken"))
```
---
    "restored"

## type-cast!

### changes object type identity

```scheme
(do (def a (pair 1 2))
    (def orig-type (type-of a))
    (type-cast! a "hello")
    (eq? (type-of a) (type-of "hello")))
```
---
    #t
