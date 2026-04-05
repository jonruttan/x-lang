[← Index](../../index.md)

# x/type/string

String manipulation, searching, and transformation.

## Construction

### `str`

Concatenate all arguments into a single string.

**Returns:** `STRING` — Concatenated result

**Examples:**

```
(str "hello" " " "world") => "hello world"
```

## Predicates

### `str-empty?`

Test whether a string is empty.

**Parameters:**

- **s** : `STRING` — String to test

**Returns:** `BOOL` — True if string has zero length

## Building

### `make-str`

Create a string of k copies of a character.

**Parameters:**

- **k** : `NUMBER` — Length of the string

**Returns:** `STRING` — A string of k copies of ch (default space)

### `str-join`

Join a list of strings with a separator.

**Parameters:**

- **sep** : `STRING` — Separator to insert between elements
- **lst** : `LIST` — List of strings

**Returns:** `STRING` — Joined string

### `str-repeat`

Repeat a string n times.

**Parameters:**

- **s** : `STRING` — String to repeat
- **n** : `INT` — Number of repetitions

**Returns:** `STRING` — Repeated string

### `str-pad-left`

Left-pad a string with ch to at least length n.

**Parameters:**

- **s** : `STRING` — String to pad
- **n** : `INT` — Desired minimum length
- **ch** : `CHAR` — Padding character

**Returns:** `STRING` — Padded string of at least length n

## Searching

### `str-contains?`

Test whether a string contains a substring.

**Parameters:**

- **sub** : `STRING` — Substring to search for
- **s** : `STRING` — String to search in

**Returns:** `BOOL` — True if sub appears in s

### `str-starts?`

Test whether a string starts with a prefix.

**Parameters:**

- **pfx** : `STRING` — Prefix to check
- **s** : `STRING` — String to test

**Returns:** `BOOL` — True if s starts with pfx

### `str-ends?`

Test whether a string ends with a suffix.

**Parameters:**

- **sfx** : `STRING` — Suffix to check
- **s** : `STRING` — String to test

**Returns:** `BOOL` — True if s ends with sfx

## Transformation

### `str-reverse`

Reverse a string.

**Parameters:**

- **s** : `STRING` — String to reverse

**Returns:** `STRING` — Reversed string

## Conversion

### `str->list`

Convert a string to a list of characters.

**Parameters:**

- **s** : `STRING` — String to convert

**Returns:** `LIST` — List of characters

## Case conversion

### `str-upcase`

Convert all characters in a string to uppercase.

**Parameters:**

- **s** : `STRING` — String to convert

**Returns:** `STRING` — Uppercased string

### `str-downcase`

Convert all characters in a string to lowercase.

**Parameters:**

- **s** : `STRING` — String to convert

**Returns:** `STRING` — Lowercased string

## Ordering

### `str<?`

Lexicographic string less-than comparison.

**Parameters:**

- **a** : `STRING` — First string
- **b** : `STRING` — Second string

**Returns:** `BOOL` — True if a is lexicographically less than b

### `str>?`

Lexicographic string greater-than comparison.

**Parameters:**

- **a** : `STRING` — First string
- **b** : `STRING` — Second string

**Returns:** `BOOL` — True if a is lexicographically greater than b

### `str<=?`

Lexicographic string less-than-or-equal comparison.

**Parameters:**

- **a** : `STRING` — First string
- **b** : `STRING` — Second string

**Returns:** `BOOL` — True if a <= b lexicographically

### `str>=?`

Lexicographic string greater-than-or-equal comparison.

**Parameters:**

- **a** : `STRING` — First string
- **b** : `STRING` — Second string

**Returns:** `BOOL` — True if a >= b lexicographically

## Case-insensitive comparison

### `str-ci=?`

Case-insensitive string equality.

**Parameters:**

- **a** : `STRING` — First string
- **b** : `STRING` — Second string

**Returns:** `BOOL` — True if strings are equal ignoring case

### `str-ci<?`

Case-insensitive string less-than.

**Parameters:**

- **a** : `STRING` — First string
- **b** : `STRING` — Second string

**Returns:** `BOOL` — True if a < b ignoring case

### `str-ci>?`

Case-insensitive string greater-than.

**Parameters:**

- **a** : `STRING` — First string
- **b** : `STRING` — Second string

**Returns:** `BOOL` — True if a > b ignoring case

### `str-ci<=?`

Case-insensitive string less-than-or-equal.

**Parameters:**

- **a** : `STRING` — First string
- **b** : `STRING` — Second string

**Returns:** `BOOL` — True if a <= b ignoring case

### `str-ci>=?`

Case-insensitive string greater-than-or-equal.

**Parameters:**

- **a** : `STRING` — First string
- **b** : `STRING` — Second string

**Returns:** `BOOL` — True if a >= b ignoring case

## Trimming

### `str-trim-left`

Remove leading whitespace from a string.

**Parameters:**

- **s** : `STRING` — String to trim

**Returns:** `STRING` — String with leading whitespace removed

### `str-trim-right`

Remove trailing whitespace from a string.

**Parameters:**

- **s** : `STRING` — String to trim

**Returns:** `STRING` — String with trailing whitespace removed

### `str-trim`

Remove whitespace from both ends of a string.

**Parameters:**

- **s** : `STRING` — String to trim

**Returns:** `STRING` — String with both leading and trailing whitespace removed

## Splitting

### `str-split`

Split a string by a separator.

**Parameters:**

- **sep** : `STRING` — Separator string; empty splits into characters
- **s** : `STRING` — String to split

**Returns:** `LIST` — List of substrings

