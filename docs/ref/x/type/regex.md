[← Index](../../index.md)

# x/type/regex

Regular expressions with literal syntax.

> Syntax: #/pattern/. Supports: . * + ? \ [class] [^neg] (group) | alternation ^ $ anchors {n,m} repetition \d \w \s.

### `regex-exec`

Execute a regex AST against a string from the given position.

**Parameters:**

- **nodes** : `LIST` — List of AST nodes from a compiled regex
- **str** : `STRING` — Input string to match against
- **pos** : `INTEGER` — Starting position in the string
- **end** : `INTEGER` — End position (string length)

**Returns:** `INTEGER` — Final position after match, or nil on failure

### `regex-parse`

Parse a regex pattern string into an executable AST.

**Parameters:**

- **pattern** : `STRING` — Regex pattern string

**Returns:** `LIST` — AST node list

### `regex-exec-one`

### `regex-exec-star`

### `regex-exec-plus`

### `regex-exec-opt`

### `regex-exec-lazy-star`

### `regex-exec-lazy-plus`

### `regex-exec-lazy-opt`

### `regex-exec-repeat`

### `regex?`

Test whether a value is a regex.

**Parameters:**

- **x** : `ANY` — Value to test

**Returns:** `BOOLEAN` — True if x is a regex

### `regex-match`

Test whether a regex matches an entire string.

**Parameters:**

- **rx** : `REGEX` — Compiled regex
- **str** : `STRING` — Input string

**Returns:** `BOOLEAN` — True if regex matches the entire string

### `regex-search`

Search for the first occurrence of a regex pattern in a string.

**Parameters:**

- **rx** : `REGEX` — Compiled regex
- **str** : `STRING` — Input string

**Returns:** `LIST` — Pair (start end) of first match, or nil if not found

### `regex-find-at`

Search for regex starting from position pos.

**Parameters:**

- **rx** : `REGEX` — Compiled regex
- **str** : `STRING` — Input string
- **pos** : `INTEGER` — Start position

**Returns:** `LIST` — Pair (start end) of match, or nil

### `regex-find`

Find first match and return the matched substring.

**Parameters:**

- **rx** : `REGEX` — Compiled regex
- **str** : `STRING` — Input string

**Returns:** `STRING` — Matched substring, or nil

**Examples:**

```
(regex-find #/[0-9]+/ "abc123def") => "123"
```

### `regex-find-all`

Find all non-overlapping matches as a list of substrings.

**Parameters:**

- **rx** : `REGEX` — Compiled regex
- **str** : `STRING` — Input string

**Returns:** `LIST` — List of matched substrings

**Examples:**

```
(regex-find-all #/[0-9]+/ "a1b22c333") => ("1" "22" "333")
```

### `regex-find-all-pos`

Find all non-overlapping match positions.

**Parameters:**

- **rx** : `REGEX` — Compiled regex
- **str** : `STRING` — Input string

**Returns:** `LIST` — List of (start end) pairs

### `regex-count`

Count the number of non-overlapping matches.

**Parameters:**

- **rx** : `REGEX` — Compiled regex
- **str** : `STRING` — Input string

**Returns:** `INTEGER` — Number of non-overlapping matches

**Examples:**

```
(regex-count #/[0-9]+/ "a1b22c333") => 3
```

### `regex-replace`

Replace the first match. rep can be a string or a function that receives the matched text.

**Parameters:**

- **rx** : `REGEX` — Compiled regex
- **str** : `STRING` — Input string
- **rep** : `ANY` — Replacement string or function

**Returns:** `STRING` — String with first match replaced

**Examples:**

```
(regex-replace #/[0-9]+/ "abc123def" "N") => "abcNdef"
```

### `regex-replace-all`

Replace all matches. rep can be a string or a function that receives each matched text.

**Parameters:**

- **rx** : `REGEX` — Compiled regex
- **str** : `STRING` — Input string
- **rep** : `ANY` — Replacement string or function

**Returns:** `STRING` — String with all matches replaced

**Examples:**

```
(regex-replace-all #/[0-9]+/ "a1b22c333" "N") => "aNbNcN"
```

### `regex-split`

Split a string at regex matches.

**Parameters:**

- **rx** : `REGEX` — Compiled regex
- **str** : `STRING` — Input string

**Returns:** `LIST` — List of substrings between matches

**Examples:**

```
(regex-split #/,/ "a,b,c") => ("a" "b" "c")
```

