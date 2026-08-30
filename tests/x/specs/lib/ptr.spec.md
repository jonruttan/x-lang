# Raw pointers (Ptr)
# @weight 1

`(Ptr from-int n)` builds a pointer from an integer address and `(Ptr ->int p)`
reads it back; `(Ptr ptr? x)` tests for a pointer.

## Ptr from-int / ->int

### round-trips an address through a pointer

```scheme
(Ptr ->int (Ptr from-int 42))
```
---
    42

## Ptr ptr?

### true for a pointer

```scheme
(Ptr ptr? (Ptr from-int 0))
```
---
    #t

### false for the integer address

```scheme
(if (Ptr ptr? 42) "yes" "no")
```
---
    "no"

### false for a string

```scheme
(if (Ptr ptr? "x") "yes" "no")
```
---
    "no"

## make-callable -- deliberately not specced here

`make-callable` wraps a raw address as an `x_fn_t` and returns a callable
prim. Applying the result is only defined when the address really is a
function with the `(base, args) -> obj` signature, and x-lang has no safe way
to obtain one: the engine's own primitives are static C symbols, so `dlsym`
cannot reach them, and any other address makes the call an invalid jump
rather than an error. Constructing one and never applying it would assert
nothing worth having. This belongs in a C test, next to a conforming symbol.

## ptr ->str

### a string round-trips through its own pointer

`str ->ptr` hands out the address of a string's bytes; `ptr ->str` copies a
C string back out of one.  The copy is a new object, not the original.

```scheme
(do
  (def %s "hello")
  (def %p ((prim-ref 'str '->ptr) %s))
  ((prim-ref 'ptr '->str) %p))
```
---
    "hello"

### the result is a copy, not the original object

```scheme
(do
  (def %s "hello")
  (def %c ((prim-ref 'ptr '->str) ((prim-ref 'str '->ptr) %s)))
  (list (equal? %c %s) (eq? %c %s)))
```
---
    (#t #f)
