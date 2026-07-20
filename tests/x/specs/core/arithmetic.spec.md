## arithmetic basics

### adds two numbers

```scheme
(+ 1 2)
```
---
    3

### subtracts two numbers

```scheme
(- 10 3)
```
---
    7

### multiplies two numbers

```scheme
(* 4 5)
```
---
    20

### nests arithmetic

```scheme
(+ 1 (* 2 3))
```
---
    7

### handles negative results

```scheme
(- 3 10)
```
---
    -7

## variadic +

### adds two numbers

```scheme
(+ 1 2)
```
---
    3

### adds three numbers

```scheme
(+ 1 2 3)
```
---
    6

### adds many numbers

```scheme
(+ 1 2 3 4 5)
```
---
    15

### identity is 0

```scheme
(+)
```
---
    0

### single arg returns it

```scheme
(+ 5)
```
---
    5

## variadic -

### subtracts two numbers

```scheme
(- 10 3)
```
---
    7

### subtracts three numbers

```scheme
(- 10 3 2)
```
---
    5

### unary negates

```scheme
(- 5)
```
---
    -5

### no args returns 0

```scheme
(-)
```
---
    0

## variadic *

### multiplies two numbers

```scheme
(* 4 5)
```
---
    20

### multiplies three numbers

```scheme
(* 2 3 4)
```
---
    24

### identity is 1

```scheme
(*)
```
---
    1

### single arg returns it

```scheme
(* 7)
```
---
    7

## variadic /

### divides two numbers

```scheme
(/ 10 3)
```
---
    3

### divides evenly

```scheme
(/ 12 4)
```
---
    3

### handles negative dividend

```scheme
(/ -10 3)
```
---
    -3

### chains division

```scheme
(/ 100 5 2)
```
---
    10

## variadic %

### computes modulo

```scheme
(% 10 3)
```
---
    1

### returns zero for even division

```scheme
(% 12 4)
```
---
    0

### handles negative dividend

```scheme
(% -10 3)
```
---
    -1

### chains modulo

```scheme
(% 100 7 3)
```
---
    2

## ~ (bitwise NOT)

### inverts zero

```scheme
(~ 0)
```
---
    -1

### inverts one

```scheme
(~ 1)
```
---
    -2

### inverts negative

```scheme
(~ -1)
```
---
    0

### double invert is identity

```scheme
(~ (~ 42))
```
---
    42

## & (bitwise AND)

### ands with zero

```scheme
(& 255 0)
```
---
    0

### ands with self

```scheme
(& 42 42)
```
---
    42

### masks low bits

```scheme
(& 255 15)
```
---
    15

### masks high nibble

```scheme
(& 170 240)
```
---
    160

## | (bitwise OR)

### ors with zero

```scheme
(| 42 0)
```
---
    42

### ors complementary bits

```scheme
(| 170 85)
```
---
    255

### ors with self

```scheme
(| 42 42)
```
---
    42

## ^ (bitwise XOR)

### xors with zero

```scheme
(^ 42 0)
```
---
    42

### xors with self gives zero

```scheme
(^ 42 42)
```
---
    0

### xors complementary bits

```scheme
(^ 170 85)
```
---
    255

### double xor is identity

```scheme
(^ (^ 42 99) 99)
```
---
    42

## << (shift left)

### shifts by 0

```scheme
(<< 1 0)
```
---
    1

### shifts by 1

```scheme
(<< 1 1)
```
---
    2

### shifts by 4

```scheme
(<< 1 4)
```
---
    16

### shifts value

```scheme
(<< 5 3)
```
---
    40

## >> (shift right)

### shifts by 0

```scheme
(>> 16 0)
```
---
    16

### shifts by 1

```scheme
(>> 16 1)
```
---
    8

### shifts by 4

```scheme
(>> 255 4)
```
---
    15

### shifts to zero

```scheme
(>> 1 1)
```
---
    0


## arity guards (#72)

These all SEGFAULTED before #72 -- a REPL user typing `(< 1)` lost the session.
The guard lives in `lib/x/core/arithmetic.x`, the same layer that gives
`+ - * /` their 0/1/2-arg tiers, so the C prims stay unchecked by design.

### zero-arg modulo is an error, not an identity

`%` has no meaningful identity element, so unlike `+ - * /` it raises rather
than returning a value. spec.md's old `(%) -> 0` claim is retracted.

```scheme
(guard (e (lit RAISED)) (%))
```
---
    'RAISED

### one-arg modulo still passes through

```scheme
(% 7)
```
---
    7

### bitwise ops need two arguments

```scheme
(list (guard (e (lit R)) (&)) (guard (e (lit R)) (& 6))
      (guard (e (lit R)) (|)) (guard (e (lit R)) (^)))
```
---
    ('R 'R 'R 'R)

### shifts need two arguments

```scheme
(list (guard (e (lit R)) (<< 1)) (guard (e (lit R)) (>> 4)))
```
---
    ('R 'R)

### bitwise not needs one argument

```scheme
(guard (e (lit RAISED)) (~))
```
---
    'RAISED

### less-than needs two arguments

```scheme
(list (guard (e (lit R)) (<)) (guard (e (lit R)) (< 1)))
```
---
    ('R 'R)

### the guarded operators still compute normally

```scheme
(list (& 6 3) (| 6 3) (^ 6 3) (<< 1 4) (>> 16 4) (~ 0) (% 7 2) (< 1 2) (< 2 1))
```
---
    (2 7 5 16 1 -1 1 #t #f)

### the identity-carrying operators keep their zero-arg tiers

```scheme
(list (+) (-) (*) (/))
```
---
    (0 0 1 1)
