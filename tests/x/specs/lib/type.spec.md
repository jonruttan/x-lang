# @weight 1
## Type alist

### returns non-nil

```x
(not (null? (Type alist)))
```
---
    #t

## Type by-atom

### finds integer type

```x
(not (null? (Type by-atom (Type of 42))))
```
---
    #t

### finds string type

```x
(not (null? (Type by-atom (Type of "hello"))))
```
---
    #t

### finds symbol type

```x
(not (null? (Type by-atom (Type of 'foo))))
```
---
    #t

### returns nil for unknown

```x
(null? (Type by-atom 999))
```
---
    #t

## Type io

### returns non-nil for integer type

```x
(not (null? (Type io (Type by-atom (Type of 42)))))
```
---
    #t

## Type cvt

### returns non-nil for integer type

```x
(not (null? (Type cvt (Type by-atom (Type of 42)))))
```
---
    #t

## Type write-cell

### returns non-nil

```x
(not (null? (Type write-cell (Type by-atom (Type of 42)))))
```
---
    #t

## Type analyse-cell

### returns non-nil

```x
(not (null? (Type analyse-cell (Type by-atom (Type of 42)))))
```
---
    #t

## Type from-cell

### returns conversion data for string type

```x
(not (null? (Type from-cell (Type by-atom (Type of "")))))
```
---
    #t

## Type to-cell

### returns conversion data for integer type

```x
(not (null? (Type to-cell (Type by-atom (Type of 42)))))
```
---
    #t

## Type push-write / Type pop-write

### push adds handler, pop removes it

```x
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

```x
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

```x
(do (def rt-t ((prim-ref (lit type) (lit make)) "RETAGT" ()))
    (def rt-a (pair 1 2))
    ((prim-ref (lit obj) (lit retag!)) rt-a rt-t)
    (Type name (Type of rt-a)))
```
---
    "RETAGT"

### an unknown handle refuses -- policy in x

```x
(guard (e e) ((prim-ref (lit obj) (lit retag!)) (pair 1 2) (lit no-such-type)))
```
---
    "retag!: unknown type handle"
## Type name

### resolves a built-in handle (the documented handle form)

```x
(Type name (Type of 42))
```
---
    "INTEGER"

### resolves a custom handle

```x
(do (def %t (Type make "NAMED-T" (list))) (Type name %t))
```
---
    "NAMED-T"

### object form returns the object's type name

```x
(Type name "hello")
```
---
    "STRING"

### a plain symbol is an object, not a handle

```x
(Type name 'foo)
```
---
    "SYMBOL"

### nil has no type name

Pins the nil-return path (formerly a C spec: nil input, nil-typed objects,
and nil-NAME types all resolve to nil rather than misreading a payload).

```x
(null? (Type name ()))
```
---
    #t

## Type instances (Type wrap)

(Type wrap t) clothes a handle or struct as a Type instance: (t name),
(t cell 'type-write-stack), (t fields), (t push-write f).  Field names
come from the layout contract (engine/tools/contract/base-paths.x); a
non-type-rooted name is refused, because a base-rooted path stepped from
a type addresses arbitrary spine words.

### wrap a handle; the instance names itself

```x
((Type wrap (Type of 0)) name)
```
---
    "INTEGER"

### wrap a struct; the same instance surface

```x
((Type wrap (Type by-atom (Type of 0))) name)
```
---
    "INTEGER"

### the instance renders as #<type:NAME>

```x
((prim-ref 'io 'display-to-str) (Type wrap (Type of 0)))
```
---
    "#<type:INTEGER>"

### the write stack is reachable as a contract cell

```x
(do (def %ti (Type wrap (Type of 0)))
    (not (null? (first (%ti cell (lit type-write-stack))))))
```
---
    #t

### the field list carries the contract's type-rooted names only

```x
(do (def %tn ((Type wrap (Type of 0)) fields))
    (list (not (null? (List filter (fn (_ n) (eq? n (lit type-write-stack))) %tn)))
          (null? (List filter (fn (_ n) (eq? n (lit line))) %tn))))
```
---
    (#t #t)

### a non-type-rooted name is refused

```x
(guard (e (lit refused)) ((Type wrap (Type of 0)) cell (lit line)))
```
---
    'refused

### push-write through a wrapped type round-trips (shadow, then pop)

The probe runs under a guard and the stack is restored UNCONDITIONALLY
before asserting (the printer spec's missing-handler lesson): a raised
probe that skipped the pop would leave INTEGER's write stack hexed for
the whole batch.  Children of a written list render in the same mode,
so the pushed handler shows through the list writer.

```x
(do
  (def %wt (Type wrap (Type of 0)))
  (%wt push-write (fn (_ n) (display (Str8 append "0x" (%number->str n 16)))))
  (def %r (guard (e 'err) ((prim-ref 'io 'write-to-str) (list 1 2 42))))
  (Type pop-write (%wt raw))
  (list %r ((prim-ref 'io 'write-to-str) (list 1 2 42))))
```
---
    ("(0x1 0x2 0x2a)" "(1 2 42)")

## Type set-shape!

`set-units!` says how many units an instance has. `set-shape!` says what each
one **is**, installing the pair form of the slot -- `(count . mask)`, two bits
per unit, unit 0 lowest: `REF` 0, `WORD` 1, `BYTES` 2, `FOREIGN` 3.

The kind decides who may touch the unit. Only a `REF` holds a heap object
pointer, and only a `REF` may be handed to the collector's mark walk -- which
sets a mark bit *through* the pointer before it can establish that the pointer
is a heap object. Tracing a `WORD` therefore writes through whatever that
immediate happens to be.

Which is why the cases below force a collection. Nothing here checks a return
value: the assertion is that the process is still alive and the `REF` unit is
intact on the other side. An unshaped type would have traced the immediate.

### a WORD unit is not traced, and the REF beside it survives

Unit 0 is a `REF` and unit 1 a `WORD`, so the mask is `(1 << 2) | 0` = 4. The
immediate is a plain integer that is not a heap address; if the collector
walked it as one, this case would not finish.

```x
(do
  (import x/sys/gc)
  (def %ss (prim-ref (lit type) (lit set-shape!)))
  (def %by (prim-ref (lit type) (lit by-atom)))
  (def %mi (prim-ref (lit type) (lit make-instance)))
  (def %set! (prim-ref (lit obj) (lit set!)))
  (def %ref (prim-ref (lit obj) (lit ref)))
  (def %t ((prim-ref (lit type) (lit make)) "SHAPEWORD" ()))
  (%ss (%by %t) 2 4)
  (def %i (%mi %t (list 1 2 3)))
  (%set! %i 1 987654321)
  (Heap collect)
  (write (%ref %i 0)))
```
---
    (1 2 3)

### a zero mask means every unit a reference

The bare-count form's meaning, unchanged -- `REF` is 0, so a mask of 0
describes an all-reference instance and both units are traced as before.

```x
(do
  (import x/sys/gc)
  (def %ss (prim-ref (lit type) (lit set-shape!)))
  (def %by (prim-ref (lit type) (lit by-atom)))
  (def %mi (prim-ref (lit type) (lit make-instance)))
  (def %set! (prim-ref (lit obj) (lit set!)))
  (def %ref (prim-ref (lit obj) (lit ref)))
  (def %t ((prim-ref (lit type) (lit make)) "SHAPEREF" ()))
  (%ss (%by %t) 2 0)
  (def %i (%mi %t (list 4 5)))
  (%set! %i 1 (list 6 7))
  (Heap collect)
  (write (list (%ref %i 0) (%ref %i 1))))
```
---
    ((4 5) (6 7))
