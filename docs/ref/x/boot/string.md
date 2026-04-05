### `not`

Logical negation.

**Parameters:**

- **x** : `ANY` — Value to negate

**Returns:** `BOOLEAN` — t if x is falsy

### `list`

Create a list from arguments.

**Parameters:**

- **args** : `ANY` — Zero or more values

**Returns:** `LIST` — A new list

**Examples:**

```
(list 1 2 3) => (1 2 3)
```

### `str-ref`

Return the character at an index in a string.

**Parameters:**

- **s** : `STRING` — A string
- **i** : `INT` — Zero-based index

**Returns:** `CHAR` — Character at index

### `str-length`

Return the length of a string.

**Parameters:**

- **s** : `STRING` — A string

**Returns:** `INT` — Number of characters

### `substring`

Extract a substring.

**Parameters:**

- **s** : `STRING` — Source string
- **start** : `INT` — Start index (inclusive)
- **end** : `INT` — End index (exclusive)

**Returns:** `STRING` — The substring

### `newline`

Display a newline character.

### `str=?`

Test string equality.

**Parameters:**

- **a** : `STRING` — First string
- **b** : `STRING` — Second string

**Returns:** `BOOLEAN` — t if equal

### `number->str`

Convert an integer to a string.

**Parameters:**

- **n** : `INT` — Integer to convert
- **radix** : `INT` — Base (optional, default 10)

**Returns:** `STRING` — String representation

### `str->number`

Parse a string as an integer.

**Parameters:**

- **s** : `STRING` — String to parse

**Returns:** `INT` — Parsed integer, or nil on failure

