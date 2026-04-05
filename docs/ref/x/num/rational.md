[← Index](../../index.md)

# x/num/rational

Exact rational number arithmetic.

> Literal syntax: 1/3, -2/7. Extends +,-,*,/,%,<,=.

## Predicates

### `rational?`

Test whether a value is a rational number or integer.

**Parameters:**

- **x** : `ANY` — Value to test

**Returns:** `BOOLEAN` — True if x is rational or integer

### `exact?`

Test whether a value is an exact number.

**Parameters:**

- **x** : `ANY` — Value to test

**Returns:** `BOOLEAN` — True if x is exact (rational or integer)

## Accessors

### `numerator`

Return the numerator of a rational number.

**Parameters:**

- **x** : `RATIONAL|INTEGER` — Rational or integer

**Returns:** `INTEGER` — Numerator of the rational, or the integer itself

### `denominator`

Return the denominator of a rational number.

**Parameters:**

- **x** : `RATIONAL|INTEGER` — Rational or integer

**Returns:** `INTEGER` — Denominator of the rational, or 1 for integers

## Arithmetic

### `rat+`

Add two rational numbers.

**Parameters:**

- **a** : `RATIONAL|INTEGER` — First operand
- **b** : `RATIONAL|INTEGER` — Second operand

**Returns:** `RATIONAL|INTEGER` — Sum, reduced to lowest terms

### `rat-`

Subtract two rational numbers.

**Parameters:**

- **a** : `RATIONAL|INTEGER` — First operand
- **b** : `RATIONAL|INTEGER` — Second operand

**Returns:** `RATIONAL|INTEGER` — Difference, reduced to lowest terms

### `rat*`

Multiply two rational numbers.

**Parameters:**

- **a** : `RATIONAL|INTEGER` — First operand
- **b** : `RATIONAL|INTEGER` — Second operand

**Returns:** `RATIONAL|INTEGER` — Product, reduced to lowest terms

### `rat/`

Divide two rational numbers.

**Parameters:**

- **a** : `RATIONAL|INTEGER` — Dividend
- **b** : `RATIONAL|INTEGER` — Divisor

**Returns:** `RATIONAL|INTEGER` — Quotient, reduced to lowest terms

## Comparison

### `rat<`

Test whether rational a is less than rational b.

**Parameters:**

- **a** : `RATIONAL|INTEGER` — Left operand
- **b** : `RATIONAL|INTEGER` — Right operand

**Returns:** `BOOLEAN` — True if a < b

### `rat=`

Test whether two rational numbers are equal.

**Parameters:**

- **a** : `RATIONAL|INTEGER` — Left operand
- **b** : `RATIONAL|INTEGER` — Right operand

**Returns:** `BOOLEAN` — True if a equals b

## Operator Overrides

### `+`

Add numbers with int/rational/float promotion.

**Parameters:**

- **args** : `NUMBER` — Numbers to add

**Returns:** `NUMBER` — Sum

### `*`

Multiply numbers with int/rational/float promotion.

**Parameters:**

- **args** : `NUMBER` — Numbers to multiply

**Returns:** `NUMBER` — Product

### `/`

Divide numbers with int/rational/float promotion. Integer division produces rationals when not exact.

**Parameters:**

- **args** : `NUMBER` — Numbers to divide

**Returns:** `NUMBER` — Quotient

### `-`

Subtract numbers with int/rational/float promotion. Unary form negates.

**Parameters:**

- **args** : `NUMBER` — Numbers to subtract

**Returns:** `NUMBER` — Difference

### `<`

Compare numbers with int/rational/float promotion.

**Parameters:**

- **a** : `NUMBER` — Left operand
- **b** : `NUMBER` — Right operand

**Returns:** `BOOLEAN` — True if a < b

### `=`

Test equality with int/rational/float promotion.

**Parameters:**

- **a** : `NUMBER` — Left operand
- **b** : `NUMBER` — Right operand

**Returns:** `BOOLEAN` — True if a equals b

### `%`

Integer remainder, hardened against rational / override.

**Parameters:**

- **a** : `INTEGER` — Dividend
- **b** : `INTEGER` — Divisor

**Returns:** `INTEGER` — Remainder

