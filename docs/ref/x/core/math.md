[← Index](../../index.md)

# x/core/math

Integer arithmetic utilities.

## Arithmetic

### `inc`

Add one to a number.

**Parameters:**

- **n** : `NUMBER` — Number to increment

**Returns:** `NUMBER` — n + 1

### `dec`

Subtract one from a number.

**Parameters:**

- **n** : `NUMBER` — Number to decrement

**Returns:** `NUMBER` — n - 1

### `negate`

Return the negation of a number.

**Parameters:**

- **n** : `NUMBER` — Number to negate

**Returns:** `NUMBER` — The additive inverse of n

### `abs`

Return the absolute value of a number.

**Parameters:**

- **n** : `NUMBER` — Number

**Returns:** `NUMBER` — Absolute value of n

### `min`

Return the smaller of two numbers.

**Parameters:**

- **a** : `NUMBER` — First number
- **b** : `NUMBER` — Second number

**Returns:** `NUMBER` — The smaller of a and b

### `max`

Return the larger of two numbers.

**Parameters:**

- **a** : `NUMBER` — First number
- **b** : `NUMBER` — Second number

**Returns:** `NUMBER` — The larger of a and b

### `clamp`

Clamp a number to the range [lo, hi].

**Parameters:**

- **lo** : `NUMBER` — Lower bound
- **hi** : `NUMBER` — Upper bound
- **n** : `NUMBER` — Value to clamp

**Returns:** `NUMBER` — n clamped to [lo, hi]

### `min-by`

Return the value with the smaller result under f.

**Parameters:**

- **f** : `CALLABLE` — Projection function
- **a** : `ANY` — First value
- **b** : `ANY` — Second value

**Returns:** `ANY` — The value whose projection is smaller

### `max-by`

Return the value with the larger result under f.

**Parameters:**

- **f** : `CALLABLE` — Projection function
- **a** : `ANY` — First value
- **b** : `ANY` — Second value

**Returns:** `ANY` — The value whose projection is larger

## Number predicates

### `zero?`

Test whether a number is zero.

**Parameters:**

- **n** : `NUMBER` — Number to test

**Returns:** `BOOLEAN` — True if n is zero

### `positive?`

Test whether a number is positive.

**Parameters:**

- **n** : `NUMBER` — Number to test

**Returns:** `BOOLEAN` — True if n is positive

### `negative?`

Test whether a number is negative.

**Parameters:**

- **n** : `NUMBER` — Number to test

**Returns:** `BOOLEAN` — True if n is negative

### `even?`

Test whether an integer is even.

**Parameters:**

- **n** : `NUMBER` — Integer to test

**Returns:** `BOOLEAN` — True if n is even

### `odd?`

Test whether an integer is odd.

**Parameters:**

- **n** : `NUMBER` — Integer to test

**Returns:** `BOOLEAN` — True if n is odd

## GCD / LCM

### `gcd`

Compute the greatest common divisor. Variadic: (gcd a b c ...) folds pairwise.

**Returns:** `NUMBER` — Greatest common divisor of all arguments

### `lcm`

Compute the least common multiple. Variadic: (lcm a b c ...) folds pairwise.

**Returns:** `NUMBER` — Least common multiple of all arguments

## Exponentiation

### `expt`

Compute base raised to a non-negative integer exponent by repeated squaring.

**Parameters:**

- **base** : `NUMBER` — Base
- **exp** : `NUMBER` — Non-negative integer exponent

**Returns:** `NUMBER` — base raised to the power exp

