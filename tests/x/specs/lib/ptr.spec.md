# Raw pointers (Ptr)

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
