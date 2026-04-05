[← Index](../../index.md)

# x/num/complex

Complex number arithmetic with rectangular and polar forms.

> Literal syntax: a+bi, a-bi (e.g. 3+4i, 0+1i, 2-3i)

> Extends arithmetic operators (+, -, *, /, =) with complex promotion.

## Arithmetic

### `complex+`

Add two complex numbers.

**Parameters:**

- **a** : `COMPLEX|NUMBER` — First operand
- **b** : `COMPLEX|NUMBER` — Second operand

**Returns:** `COMPLEX|NUMBER` — Sum, collapsed to real if imaginary part is zero

### `complex-`

Subtract two complex numbers.

**Parameters:**

- **a** : `COMPLEX|NUMBER` — First operand
- **b** : `COMPLEX|NUMBER` — Second operand

**Returns:** `COMPLEX|NUMBER` — Difference, collapsed to real if imaginary part is zero

### `complex*`

Multiply two complex numbers.

**Parameters:**

- **a** : `COMPLEX|NUMBER` — First operand
- **b** : `COMPLEX|NUMBER` — Second operand

**Returns:** `COMPLEX|NUMBER` — Product, collapsed to real if imaginary part is zero

### `complex/`

Divide two complex numbers.

**Parameters:**

- **a** : `COMPLEX|NUMBER` — Dividend
- **b** : `COMPLEX|NUMBER` — Divisor

**Returns:** `COMPLEX|NUMBER` — Quotient, collapsed to real if imaginary part is zero

### `complex=`

Test whether two complex numbers are equal.

**Parameters:**

- **a** : `COMPLEX|NUMBER` — Left operand
- **b** : `COMPLEX|NUMBER` — Right operand

**Returns:** `BOOLEAN` — True if both real and imaginary parts are equal

## Constructors and Accessors

### `make-rectangular`

Construct a complex number from rectangular coordinates.

**Parameters:**

- **re** : `NUMBER` — Real part
- **im** : `NUMBER` — Imaginary part

**Returns:** `COMPLEX|NUMBER` — Complex number, or real if imaginary part is zero

### `make-polar`

Construct a complex number from polar coordinates (magnitude and angle).

**Parameters:**

- **mag** : `NUMBER` — Magnitude
- **ang** : `NUMBER` — Angle in radians

**Returns:** `COMPLEX|NUMBER` — Complex number from polar coordinates

### `real-part`

Return the real part of a complex number, or the number itself for reals.

**Parameters:**

- **z** : `COMPLEX|NUMBER` — Complex or real number

**Returns:** `NUMBER` — Real part

### `imag-part`

Return the imaginary part of a complex number, or 0 for reals.

**Parameters:**

- **z** : `COMPLEX|NUMBER` — Complex or real number

**Returns:** `NUMBER` — Imaginary part

### `magnitude`

Return the magnitude (absolute value) of a complex or real number.

**Parameters:**

- **z** : `COMPLEX|NUMBER` — Complex or real number

**Returns:** `FLOAT` — Absolute value (distance from origin)

### `angle`

Return the angle (argument) of a complex number in radians.

**Parameters:**

- **z** : `COMPLEX|NUMBER` — Complex or real number

**Returns:** `FLOAT` — Angle in radians

## Operator Overrides

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

### `=`

Test numeric equality.

**Parameters:**

- **a** : `INT` — First number
- **b** : `INT` — Second number

**Returns:** `BOOLEAN` — t if equal

### `/`

Variadic integer division. Folds left.

**Parameters:**

- **args** : `NUMBER` — One or more numbers

**Returns:** `NUMBER` — Quotient from left fold

**Examples:**

```
(/ 100 5 2) => 10
```

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

## Predicates

### `number?`

Test whether a value is any numeric type (integer, rational, float, or complex).

**Parameters:**

- **x** : `ANY` — Value to test

**Returns:** `BOOLEAN` — True if x is a number

### `complex?`

Test whether a value is any numeric type (alias for number?).

**Parameters:**

- **x** : `ANY` — Value to test

**Returns:** `BOOLEAN` — True if x is a number

### `real?`

Test whether a value is a real number (integer, rational, or float, but not complex).

**Parameters:**

- **x** : `ANY` — Value to test

**Returns:** `BOOLEAN` — True if x is a real number

