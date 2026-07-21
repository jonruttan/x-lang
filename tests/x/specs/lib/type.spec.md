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
(not (null? (Type by-atom (Type of 42))))
```
---
    #t

### finds string type

```scheme
(not (null? (Type by-atom (Type of "hello"))))
```
---
    #t

### finds symbol type

```scheme
(not (null? (Type by-atom (Type of 'foo))))
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
(not (null? (Type io (Type by-atom (Type of 42)))))
```
---
    #t

## Type cvt

### returns non-nil for integer type

```scheme
(not (null? (Type cvt (Type by-atom (Type of 42)))))
```
---
    #t

## Type write-cell

### returns non-nil

```scheme
(not (null? (Type write-cell (Type by-atom (Type of 42)))))
```
---
    #t

## Type analyse-cell

### returns non-nil

```scheme
(not (null? (Type analyse-cell (Type by-atom (Type of 42)))))
```
---
    #t

## Type from-cell

### returns conversion data for string type

```scheme
(not (null? (Type from-cell (Type by-atom (Type of "")))))
```
---
    #t

## Type to-cell

### returns conversion data for integer type

```scheme
(not (null? (Type to-cell (Type by-atom (Type of 42)))))
```
---
    #t

## Type push-write / Type pop-write

### push adds handler, pop removes it

```scheme
(do (def ts (Type by-atom (Type of 42)))
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
    (def orig-type (Type of a))
    (Type cast! a "hello")
    (eq? (Type of a) (Type of "hello")))
```
---
    #t

## obj retag!

The handle-resolving sibling of cast!, pure reflection in boot/reflect.x
(retired from C by the #101 ruling). The singleton claim itself is pinned
by bool.spec.md and the gc-stress collect path.

### retags an object to a handle-resolved type

```scheme
(do (def rt-t ((prim-ref (lit type) (lit make)) "RETAGT" ()))
    (def rt-a (pair 1 2))
    ((prim-ref (lit obj) (lit retag!)) rt-a rt-t)
    (Type name (Type of rt-a)))
```
---
    "RETAGT"

### an unknown handle refuses -- policy in x

```scheme
(guard (e e) ((prim-ref (lit obj) (lit retag!)) (pair 1 2) (lit no-such-type)))
```
---
    "retag!: unknown type handle"
## Type name

### resolves a built-in handle (the documented handle form)

```scheme
(Type name (Type of 42))
```
---
    "INTEGER"

### resolves a custom handle

```scheme
(do (def %t (Type make "NAMED-T" (list))) (Type name %t))
```
---
    "NAMED-T"

### object form returns the object's type name

```scheme
(Type name "hello")
```
---
    "STRING"

### a plain symbol is an object, not a handle

```scheme
(Type name 'foo)
```
---
    "SYMBOL"

### nil has no type name

Pins the nil-return path (formerly a C spec: nil input, nil-typed objects,
and nil-NAME types all resolve to nil rather than misreading a payload).

```scheme
(null? (Type name ()))
```
---
    #t
