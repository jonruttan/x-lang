[← Index](../../index.md)

# x/num/float

IEEE 754 floating-point arithmetic.

> Literal syntax: 3.14, 1.0e10. Extends +,-,*,/,<,= with float promotion.

## Conversion

### `float->str`

Convert a float bit pattern to its string representation.

**Parameters:**

- **bits** : `INTEGER` — IEEE 754 double bit pattern

**Returns:** `STRING` — Decimal string representation

### `int->float`

Convert an integer to a float bit pattern.

**Parameters:**

- **n** : `INTEGER` — Integer value

**Returns:** `INTEGER` — IEEE 754 double bit pattern

### `float->int`

Convert a float bit pattern to an integer by truncation.

**Parameters:**

- **bits** : `INTEGER` — IEEE 754 double bit pattern

**Returns:** `INTEGER` — Truncated integer value

### `str->float`

Parse a decimal string into a float.

**Parameters:**

- **s** : `STRING` — Decimal string to parse

**Returns:** `FLOAT` — Parsed float value

## Predicates

### `float?`

Test whether a value is a float.

**Parameters:**

- **x** : `ANY` — Value to test

**Returns:** `BOOLEAN` — True if x is a float

### `exact->inexact`

Convert an exact integer to an inexact float.

**Parameters:**

- **x** : `INTEGER` — Exact integer value

**Returns:** `FLOAT` — Float representation

### `inexact->exact`

Convert an inexact float to an exact integer by truncation.

**Parameters:**

- **x** : `FLOAT` — Float value

**Returns:** `INTEGER` — Truncated integer value

## Arithmetic

### `f+`

Add two floats.

**Parameters:**

- **a** : `FLOAT` — First operand
- **b** : `FLOAT` — Second operand

**Returns:** `FLOAT` — Sum

### `f-`

Subtract two floats.

**Parameters:**

- **a** : `FLOAT` — First operand
- **b** : `FLOAT` — Second operand

**Returns:** `FLOAT` — Difference

### `f*`

Multiply two floats.

**Parameters:**

- **a** : `FLOAT` — First operand
- **b** : `FLOAT` — Second operand

**Returns:** `FLOAT` — Product

### `f/`

Divide two floats.

**Parameters:**

- **a** : `FLOAT` — Dividend
- **b** : `FLOAT` — Divisor

**Returns:** `FLOAT` — Quotient

## Comparisons

### `f<`

Test whether float a is less than float b.

**Parameters:**

- **a** : `FLOAT` — Left operand
- **b** : `FLOAT` — Right operand

**Returns:** `BOOLEAN` — True if a < b

### `f=`

Test whether two floats are equal.

**Parameters:**

- **a** : `FLOAT` — Left operand
- **b** : `FLOAT` — Right operand

**Returns:** `BOOLEAN` — True if a equals b

## Math Functions

### `fsin`

Compute the sine of a float.

**Returns:** `FLOAT` — Sine of x

### `fcos`

Compute the cosine of a float.

**Returns:** `FLOAT` — Cosine of x

### `ftan`

Compute the tangent of a float.

**Returns:** `FLOAT` — Tangent of x

### `fsqrt`

Compute the square root of a float.

**Returns:** `FLOAT` — Square root of x

### `fexp`

Compute e raised to a power.

**Returns:** `FLOAT` — e raised to the power x

### `flog`

Compute the natural logarithm of a float.

**Returns:** `FLOAT` — Natural logarithm of x

### `fabs`

Compute the absolute value of a float.

**Returns:** `FLOAT` — Absolute value of x

### `ffloor`

Round a float down to the nearest integer.

**Returns:** `FLOAT` — Largest integer not greater than x

### `fceil`

Round a float up to the nearest integer.

**Returns:** `FLOAT` — Smallest integer not less than x

### `fround`

Round a float to the nearest integer.

**Returns:** `FLOAT` — Nearest integer, ties away from zero

### `ftrunc`

Truncate a float toward zero.

**Returns:** `FLOAT` — Integer part of x

### `frint`

Round a float to the nearest integer using the current rounding mode.

**Returns:** `FLOAT` — Nearest integer using current rounding mode

### `fasin`

Compute the arc sine of a float.

**Returns:** `FLOAT` — Arc sine in radians

### `facos`

Compute the arc cosine of a float.

**Returns:** `FLOAT` — Arc cosine in radians

### `fatan`

Compute the arc tangent of a float.

**Returns:** `FLOAT` — Arc tangent in radians

### `fpow`

Raise a float to a power.

**Returns:** `FLOAT` — base raised to the power exponent

### `fatan2`

Compute the arc tangent of y/x, using signs to determine the quadrant.

**Returns:** `FLOAT` — Angle in radians

## Generic Overrides

### `+`

Variadic addition. Returns the sum of all arguments.

**Parameters:**

- **args** : `NUMBER` — Zero or more numbers

**Returns:** `NUMBER` — Sum of all arguments, or 0 with no arguments

**Examples:**

```
(+ 1 2 3) => 6
(+) => 0
```

### `*`

Variadic multiplication. Returns the product of all arguments.

**Parameters:**

- **args** : `NUMBER` — Zero or more numbers

**Returns:** `NUMBER` — Product of all arguments, or 1 with no arguments

**Examples:**

```
(* 2 3 4) => 24
(*) => 1
```

### `/`

Variadic integer division. Folds left.

**Parameters:**

- **args** : `NUMBER` — One or more numbers

**Returns:** `NUMBER` — Quotient from left fold

**Examples:**

```
(/ 100 5 2) => 10
```

### `<`

Test numeric less-than.

**Parameters:**

- **a** : `INT` — First number
- **b** : `INT` — Second number

**Returns:** `BOOLEAN` — t if a < b

### `=`

Test numeric equality.

**Parameters:**

- **a** : `INT` — First number
- **b** : `INT` — Second number

**Returns:** `BOOLEAN` — t if equal

### `-`

Variadic subtraction. With one argument, negates. With multiple, folds left.

**Parameters:**

- **args** : `NUMBER` — One or more numbers

**Returns:** `NUMBER` — Difference, or negation with one argument

**Examples:**

```
(- 10 3 2) => 5
(- 5) => -5
```

## R7RS Predicates

### `integer?`

Test whether a value is an integer. Alias for the original number? predicate.

### `number?`

Test whether a value is a number (integer or float).

**Parameters:**

- **x** : `ANY` — Value to test

**Returns:** `BOOLEAN` — True if x is a number

### `real?`

Test whether a value is a real number. Equivalent to number?.

### `inexact?`

Test whether a value is inexact. Equivalent to float?.

