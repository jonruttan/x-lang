# int->str

Renders an integer's digits into a fresh string, in an optional base (2..36,
default 10).  Filed under the `int` namespace, so it is reached through the
catalog like its neighbours.

The conversion itself is x-lib's `ltoa` drop-in.  That function takes a
magnitude by negating its argument, which is the one operation that does not
round-trip on the most-negative integer -- so the primitive peels the final
digit first, in the negative domain, and never hands `ltoa` a value it cannot
negate.  The last two cases are that guard.

## int ->str

### renders a positive integer in base 10

```scheme
(do (def %i2s (prim-ref (lit int) (lit ->str)))
    (%i2s 12345))
```
---
    "12345"

### renders zero

```scheme
(do (def %i2s (prim-ref (lit int) (lit ->str)))
    (%i2s 0))
```
---
    "0"

### renders a negative integer

```scheme
(do (def %i2s (prim-ref (lit int) (lit ->str)))
    (%i2s -42))
```
---
    "-42"

### a single negative digit keeps its sign

The peeled quotient is zero here, so the sign has to be written by hand.

```scheme
(do (def %i2s (prim-ref (lit int) (lit ->str)))
    (%i2s -7))
```
---
    "-7"

### renders in base 16

```scheme
(do (def %i2s (prim-ref (lit int) (lit ->str)))
    (%i2s 255 16))
```
---
    "ff"

### renders in base 2

```scheme
(do (def %i2s (prim-ref (lit int) (lit ->str)))
    (%i2s 5 2))
```
---
    "101"

### a negative value in a non-decimal base

```scheme
(do (def %i2s (prim-ref (lit int) (lit ->str)))
    (%i2s -255 16))
```
---
    "-ff"

### THE most-negative integer round-trips

The minimum is derived by shifting rather than written down, so this holds
whatever the word size.

```scheme
(do (def %i2s (prim-ref (lit int) (lit ->str)))
    (def %min-of (fn (self k) (match ((< (<< 1 k) 0) (<< 1 k)) (#t (self (+ k 1))))))
    (def %min (%min-of 1))
    (= (%str->number (%i2s %min 10) 10) %min))
```
---
    #t

### the most-negative integer keeps its sign

```scheme
(do (def %i2s (prim-ref (lit int) (lit ->str)))
    (def %min-of (fn (self k) (match ((< (<< 1 k) 0) (<< 1 k)) (#t (self (+ k 1))))))
    (%str-byte-ref (%i2s (%min-of 1) 10) 0))
```
---
    #\-
