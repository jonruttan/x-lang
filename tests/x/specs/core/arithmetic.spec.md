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

### a nil operand raises rather than dereferencing

Counting arguments is not enough: a nil operand reaches the primitive and is
dereferenced exactly like a missing one. `x_prim_lt` reads `x_intval(NULL)`
where `x_prim_eq` is nil-safe, so an explicit `()` was a live crash after the
arity tier landed.

```scheme
(list (guard (e (lit R)) (< 1 ())) (guard (e (lit R)) (< () 1))
      (guard (e (lit R)) (& 6 ())) (guard (e (lit R)) (~ ())))
```
---
    ('R 'R 'R 'R)

### the derived comparisons raise instead of passing nil through

`>` is `(fn (_ a b) (< b a))`, so `(> 1)` binds `b` to nil and calls
`(< nil 1)` -- two arguments, so the arity tier passes it straight to the
unchecked primitive.

```scheme
(list (guard (e (lit R)) (> 1)) (guard (e (lit R)) (<= 1))
      (guard (e (lit R)) (>= 1)) (guard (e (lit R)) (>)))
```
---
    ('R 'R 'R 'R)

## division by zero (#80)

C division has no zero test, no SIGFPE handler exists, and `guard` cannot
catch a hardware trap -- so before the guard, `(/ 1 0)` killed the whole
process. The gate is the saved C `number?`, so only a C-level integer zero
is stopped; boxed tower divisors keep their own dispatch.

### binary tier raises for / and %

```scheme
(list (guard (e (lit R)) (/ 1 0)) (guard (e (lit R)) (% 1 0)))
```
---
    ('R 'R)

### fold tier raises mid-fold

```scheme
(list (guard (e (lit R)) (/ 8 2 0)) (guard (e (lit R)) (% 17 10 0)))
```
---
    ('R 'R)

### zero as dividend still divides

```scheme
(list (/ 0 5) (% 0 5) (/ 100 2 5) (% 17 10 3))
```
---
    (0 0 10 1)

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

## non-numeric operands refuse (#52 ruled)

The refusal lives in the dispatch registry: string/char/list/pair/vector
register error-raising handlers for + - * / % <, so op_try routes a bad
operand to err:type instead of the int fallthrough's pointer arithmetic.
Zero cost on the int path (op_try fast-declines ops-less types; benchmarked
at baseline). Symbols (tree-typed) and nil-typed singletons (#t) are the
documented residuals until booleans become a real type.

### wrong-type operands raise err:type across the family

```scheme
(list (guard (e (Err kind-of e)) (+ 1 "abc"))
      (guard (e (Err kind-of e)) (< 1 "a"))
      (guard (e (Err kind-of e)) (* 2 (list 1)))
      (guard (e (Err kind-of e)) (/ #(1) 2))
      (guard (e (Err kind-of e)) (% 7 (pair 1 2))))
```
---
    ('type 'type 'type 'type 'type)

### the message names op and type

```scheme
(guard (e (e msg)) (+ 1 "abc"))
```
---
    "no + for STRING"

### chars ARE their code points -- the pun is contract, not an accident

The regex engine reads {3} via (- ch #\0) inside the tokenizer, utf8 decode
masks CHAR-typed bytes with &, and the printer's escaper orders chars with <.

```scheme
(list (< #\a #\b) (- #\3 #\0) (+ #\a 1) (& #\a 15))
```
---
    (#t 3 98 1)

## nil operands raise in the C prims (#52 ruled)

An x-level wrapper test measured +9% on every method dispatch, so the check
follows x_prim_eq's existing nil-safety convention instead: two pointer
tests inside the prim, after op_try. (+ 1 ()) segfaulted before this.

### nil raises catchably on all five, all shapes

```scheme
(list (guard (e (lit R)) (+ 1 ())) (guard (e (lit R)) (- ())) (guard (e (lit R)) (- 5 ()))
      (guard (e (lit R)) (* () 2)) (guard (e (lit R)) (/ 6 ())) (guard (e (lit R)) (% () 2))
      (guard (e (lit R)) (+ 1 2 () 4)))
```
---
    ('R 'R 'R 'R 'R 'R 'R)

## bitwise is integer-only (#52 ruled)

No tower semantics exist for the bitwise family, so unlike `<` (whose
strictness would break float comparisons) rejecting every non-INT operand
is simply correct -- inline type tests in the wrappers, nil included.

### non-integers raise across the bitwise family

```scheme
(list (guard (e (lit R)) (& "a" 1)) (guard (e (lit R)) (| 1 (list 2)))
      (guard (e (lit R)) (~ "x")) (guard (e (lit R)) (<< 1 ())))
```
---
    ('R 'R 'R 'R)
