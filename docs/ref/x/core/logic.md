[← Index](../../index.md)

# x/core/logic

Boolean logic, structural equality, and derived comparisons.

### `boolean?`

Test whether a value is a boolean.

**Parameters:**

- **x** : `ANY` — Value to test

**Returns:** `BOOLEAN` — True if x is #t or #f

### `default-to`

Return x if non-nil, otherwise return the default d.

**Parameters:**

- **d** : `ANY` — Default value
- **x** : `ANY` — Value to check

**Returns:** `ANY` — x if non-nil, otherwise d

### `until`

Repeatedly apply f to x until pred is satisfied, then return the value.

**Parameters:**

- **pred** : `CALLABLE` — Predicate to stop on
- **f** : `CALLABLE` — Transformation function
- **x** : `ANY` — Initial value

**Returns:** `ANY` — First value satisfying pred

### `equal?`

Structural equality: compares numbers by value, strings by content, else by identity.

**Parameters:**

- **a** : `ANY` — First value
- **b** : `ANY` — Second value

**Returns:** `BOOLEAN` — True if a and b are structurally equal

### `>`

Test whether a is greater than b.

**Parameters:**

- **a** : `NUMBER` — Left operand
- **b** : `NUMBER` — Right operand

**Returns:** `BOOLEAN` — True if a is greater than b

### `<=`

Test whether a is less than or equal to b.

**Parameters:**

- **a** : `NUMBER` — Left operand
- **b** : `NUMBER` — Right operand

**Returns:** `BOOLEAN` — True if a is less than or equal to b

### `>=`

Test whether a is greater than or equal to b.

**Parameters:**

- **a** : `NUMBER` — Left operand
- **b** : `NUMBER` — Right operand

**Returns:** `BOOLEAN` — True if a is greater than or equal to b

