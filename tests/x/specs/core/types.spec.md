# @weight 1
## make-type

### creates a custom type with call handler

```x
(do (def %counter (Type make "COUNTER" (list (pair 'call (fn (_ self . args) (+ (first self) (first args))))))) (def c (Type make-instance %counter 10)) (c 5))
```
---
    15

### creates a custom type with write handler

```x
(do (def %tag (Type make "TAG" (list (pair 'write (fn (_ self) (display "<") (display (first self)) (display ">")))))) (write (Type make-instance %tag "hello")))
```
---
    <hello>

## make-instance

### stores data accessible via first

```x
(do (def my-t (Type make "MY-T" (list))) (def obj (Type make-instance my-t 42)) (first obj))
```
---
    42

### instance self-evaluates

```x
(do (def my-t (Type make "MY-T" (list))) (def obj (Type make-instance my-t 42)) (eq? obj obj))
```
---
    #t

## set-shape!

### declares the pair form of a type's units slot

```x
(do
  (def t (Type make "SHAPED" ()))
  (def ts ((prim-ref (lit type) (lit by-atom)) t))
  (Type set-shape! ts 1 '(bytes))
  (first (%type-units-cell ts)))
```
---
    (1 . 2)

### the engine's atom types are declared at boot

```x
(first (%type-units-cell ((prim-ref (lit type) (lit by-atom)) (Type of "x"))))
```
---
    (1 . 2)

### a kind mask packs two bits per unit, unit 0 lowest

```x
(list (Type %kind-mask '(ref)) (Type %kind-mask '(word))
      (Type %kind-mask '(bytes)) (Type %kind-mask '(foreign))
      (Type %kind-mask '(word ref)))
```
---
    (0 1 2 3 1)

### an unknown kind is refused

```x
(guard (e 'refused) (Type %kind-mask '(banana)))
```
---
    'refused

### `ref` units survive a collect, and the repeat rule reaches the payload

```x
(do
  (def t (Type make "SHAPED" ()))
  (def ts ((prim-ref (lit type) (lit by-atom)) t))
  (Type set-shape! ts -1 '(ref ref))
  (def o (Obj make t 3))
  (Obj set! o 0 2)
  (Obj set! o 1 (pair 1 2))
  (Obj set! o 2 (pair 3 4))
  ((prim-ref (lit heap) (lit collect)))
  (list (Obj ref o 0) (Obj ref o 1) (Obj ref o 2)))
```
---
    (2 (1 . 2) (3 . 4))

### `word` says "do not follow this", not "this is small"

No test asserts on the wrong case here, deliberately: getting it wrong frees
the object and leaves a DANGLING slot, not a nil one, so any spec that read it
back would be asserting on undefined behaviour and would flake.

The trap is worth stating even so. A vector's slot 0 holds a heap INTEGER
*object*, not an immediate, so `(word ref)` over a count of `-1` is wrong for
it -- the collector skips slot 0 and the length is freed under the instance.
A vector is `(ref ref)`, which is mask 0, which is the bare count it already
had. `word` is for a unit holding a machine value the collector must not
follow: the engine's own atom types, whose single data unit is an int or a
character code rather than a pointer. Ask what the unit HOLDS, not how big it
looks.

## type?

### returns #t for matching type

```x
(do (def my-t (Type make "MY-T" (list))) (Type ? (Type make-instance my-t 42) my-t))
```
---
    #t

### returns nil for wrong type

```x
(do (def t1 (Type make "T1" (list))) (def t2 (Type make "T2" (list))) (if (Type ? (Type make-instance t1 1) t2) "y" "n"))
```
---
    "n"

### returns nil for non-instance

```x
(do (def my-t (Type make "MY-T" (list))) (if (Type ? 42 my-t) "y" "n"))
```
---
    "n"

## type-name

### returns VECTOR for a vector

```x
(Type name (Vector of 1))
```
---
    "VECTOR"

### returns LIST for a list

```x
(Type name (list 1 2))
```
---
    "LIST"

### returns INTEGER for a number

```x
(Type name 42)
```
---
    "INTEGER"

### returns STRING for a string

```x
(Type name "hi")
```
---
    "STRING"

### returns custom type name

```x
(do (def my-t (Type make "MY-T" (list))) (Type name (Type make-instance my-t 1)))
```
---
    "MY-T"

## score-match

### sets score length and reader


