[← Index](../../index.md)

# x/core/predicates

### `null?`

Test if a value is nil (the empty list).

**Parameters:**

- **x** : `ANY` — Value to test

**Returns:** `BOOLEAN` — t if nil

### `pair?`

Test if a value is a pair (cons cell).

**Parameters:**

- **x** : `ANY` — Value to test

**Returns:** `BOOLEAN` — t if pair

### `not`

Logical negation.

**Parameters:**

- **x** : `ANY` — Value to negate

**Returns:** `BOOLEAN` — t if x is falsy

### `atom?`

Test if a value is an atom (not a pair).

**Parameters:**

- **x** : `ANY` — Value to test

**Returns:** `BOOLEAN` — t if not a pair

### `number?`

Test if a value is an integer.

**Parameters:**

- **x** : `ANY` — Value to test

**Returns:** `BOOLEAN` — t if integer

### `str?`

Test if a value is a string.

**Parameters:**

- **x** : `ANY` — Value to test

**Returns:** `BOOLEAN` — t if string

### `symbol?`

Test if a value is a symbol.

**Parameters:**

- **x** : `ANY` — Value to test

**Returns:** `BOOLEAN` — t if symbol

### `char?`

Test if a value is a character.

**Parameters:**

- **x** : `ANY` — Value to test

**Returns:** `BOOLEAN` — t if character

### `procedure?`

Test if a value is callable (procedure or primitive).

**Parameters:**

- **x** : `ANY` — Value to test

**Returns:** `BOOLEAN` — t if procedure or primitive

