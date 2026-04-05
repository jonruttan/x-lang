[← Index](../../index.md)

# x/num/bignum

Arbitrary-precision integers.

> Auto-promotes when integers exceed native range. Extends +,-,*,/,%,<,=.

## Predicates

### `bignum?`

Test whether a value is an arbitrary-precision integer.

**Parameters:**

- **x** : `ANY` — Value to test

**Returns:** `BOOLEAN` — True if x is a bignum

## Arithmetic

### `big+`

Add two bignums.

**Parameters:**

- **a** : `BIGNUM` — First operand
- **b** : `BIGNUM` — Second operand

**Returns:** `INTEGER|BIGNUM` — Sum, demoted to integer if it fits

### `big-`

Subtract two bignums.

**Parameters:**

- **a** : `BIGNUM` — First operand
- **b** : `BIGNUM` — Second operand

**Returns:** `INTEGER|BIGNUM` — Difference, demoted to integer if it fits

### `big*`

Multiply two bignums.

**Parameters:**

- **a** : `BIGNUM` — First operand
- **b** : `BIGNUM` — Second operand

**Returns:** `INTEGER|BIGNUM` — Product, demoted to integer if it fits

### `big/`

Divide two bignums (truncating division).

**Parameters:**

- **a** : `BIGNUM` — Dividend
- **b** : `BIGNUM` — Divisor

**Returns:** `INTEGER|BIGNUM` — Quotient (truncated), demoted to integer if it fits

### `big%`

Compute the remainder of bignum division.

**Parameters:**

- **a** : `BIGNUM` — Dividend
- **b** : `BIGNUM` — Divisor

**Returns:** `INTEGER|BIGNUM` — Remainder, demoted to integer if it fits

## Comparison

### `big<`

Test whether bignum a is less than bignum b.

**Parameters:**

- **a** : `BIGNUM` — Left operand
- **b** : `BIGNUM` — Right operand

**Returns:** `BOOLEAN` — True if a < b

### `big=`

Test whether two bignums are equal.

**Parameters:**

- **a** : `BIGNUM` — Left operand
- **b** : `BIGNUM` — Right operand

**Returns:** `BOOLEAN` — True if a equals b

### `would-overflow-add?`

Test whether addition of two native integers would overflow.

**Parameters:**

- **a** : `INTEGER` — First operand
- **b** : `INTEGER` — Second operand

**Returns:** `BOOLEAN` — True if a + b would overflow native integer

### `would-overflow-mul?`

Test whether multiplication of two native integers would overflow.

**Parameters:**

- **a** : `INTEGER` — First operand
- **b** : `INTEGER` — Second operand

**Returns:** `BOOLEAN` — True if a * b would overflow native integer

## Operator Overrides

### `+`

Add numbers, promoting to bignum on overflow.

**Parameters:**

- **args** : `INTEGER|BIGNUM` — Numbers to add

**Returns:** `INTEGER|BIGNUM` — Sum

### `-`

Subtract numbers, promoting to bignum on overflow. Unary form negates.

**Parameters:**

- **args** : `INTEGER|BIGNUM` — Numbers to subtract

**Returns:** `INTEGER|BIGNUM` — Difference

### `*`

Multiply numbers, promoting to bignum on overflow.

**Parameters:**

- **args** : `INTEGER|BIGNUM` — Numbers to multiply

**Returns:** `INTEGER|BIGNUM` — Product

### `/`

Divide numbers, promoting to bignum when needed.

**Parameters:**

- **args** : `INTEGER|BIGNUM` — Numbers to divide

**Returns:** `INTEGER|BIGNUM` — Quotient

### `%`

Compute remainder, promoting to bignum when needed.

**Parameters:**

- **a** : `INTEGER|BIGNUM` — Dividend
- **b** : `INTEGER|BIGNUM` — Divisor

**Returns:** `INTEGER|BIGNUM` — Remainder

### `<`

Compare numbers, promoting to bignum when needed.

**Parameters:**

- **a** : `INTEGER|BIGNUM` — Left operand
- **b** : `INTEGER|BIGNUM` — Right operand

**Returns:** `BOOLEAN` — True if a < b

### `=`

Test equality, promoting to bignum when needed.

**Parameters:**

- **a** : `INTEGER|BIGNUM` — Left operand
- **b** : `INTEGER|BIGNUM` — Right operand

**Returns:** `BOOLEAN` — True if a equals b

