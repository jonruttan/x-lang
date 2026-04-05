[← Index](../../index.md)

# x/type/char

Character classification and case conversion.

> ASCII only.

## Classification

### `char-alphabetic?`

Test whether a character is alphabetic.

**Parameters:**

- **c** : `CHAR` — Character to test

**Returns:** `BOOL` — True if c is a letter A-Z or a-z

### `char-numeric?`

Test whether a character is a digit.

**Parameters:**

- **c** : `CHAR` — Character to test

**Returns:** `BOOL` — True if c is a digit 0-9

### `char-whitespace?`

Test whether a character is whitespace (space, tab, newline, CR, FF).

**Parameters:**

- **c** : `CHAR` — Character to test

**Returns:** `BOOL` — True if c is whitespace

### `char-upper-case?`

Test whether a character is uppercase.

**Parameters:**

- **c** : `CHAR` — Character to test

**Returns:** `BOOL` — True if c is uppercase A-Z

### `char-lower-case?`

Test whether a character is lowercase.

**Parameters:**

- **c** : `CHAR` — Character to test

**Returns:** `BOOL` — True if c is lowercase a-z

## Case conversion

### `char-upcase`

Convert a character to uppercase.

**Parameters:**

- **c** : `CHAR` — Character to convert

**Returns:** `CHAR` — Uppercase version of c, or c unchanged

### `char-downcase`

Convert a character to lowercase.

**Parameters:**

- **c** : `CHAR` — Character to convert

**Returns:** `CHAR` — Lowercase version of c, or c unchanged

## Comparisons

### `char=?`

Test whether two characters are equal.

**Parameters:**

- **a** : `CHAR` — First character
- **b** : `CHAR` — Second character

**Returns:** `BOOL` — True if characters are equal

### `char<?`

Test whether a character is less than another by code point.

**Parameters:**

- **a** : `CHAR` — First character
- **b** : `CHAR` — Second character

**Returns:** `BOOL` — True if a comes before b

### `char>?`

Test whether a character is greater than another by code point.

**Parameters:**

- **a** : `CHAR` — First character
- **b** : `CHAR` — Second character

**Returns:** `BOOL` — True if a comes after b

### `char<=?`

Test whether a character is less than or equal to another.

**Parameters:**

- **a** : `CHAR` — First character
- **b** : `CHAR` — Second character

**Returns:** `BOOL` — True if a is equal to or comes before b

### `char>=?`

Test whether a character is greater than or equal to another.

**Parameters:**

- **a** : `CHAR` — First character
- **b** : `CHAR` — Second character

**Returns:** `BOOL` — True if a is equal to or comes after b

## Case-insensitive comparisons

### `char-ci=?`

Case-insensitive character equality.

**Parameters:**

- **a** : `CHAR` — First character
- **b** : `CHAR` — Second character

**Returns:** `BOOL` — True if characters are equal ignoring case

### `char-ci<?`

Case-insensitive character less-than.

**Parameters:**

- **a** : `CHAR` — First character
- **b** : `CHAR` — Second character

**Returns:** `BOOL` — True if a < b ignoring case

### `char-ci>?`

Case-insensitive character greater-than.

**Parameters:**

- **a** : `CHAR` — First character
- **b** : `CHAR` — Second character

**Returns:** `BOOL` — True if a > b ignoring case

### `char-ci<=?`

Case-insensitive character less-than-or-equal.

**Parameters:**

- **a** : `CHAR` — First character
- **b** : `CHAR` — Second character

**Returns:** `BOOL` — True if a <= b ignoring case

### `char-ci>=?`

Case-insensitive character greater-than-or-equal.

**Parameters:**

- **a** : `CHAR` — First character
- **b** : `CHAR` — Second character

**Returns:** `BOOL` — True if a >= b ignoring case

