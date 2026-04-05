[← Index](../../index.md)

# x/tool/fmt

Comment-preserving s-expression formatter.

### `fmt-build-table`

Build a formatter lookup table from construct declarations.

**Returns:** `ALIST` — Lookup table mapping names to property lists

### `fmt-lookup`

Look up formatting properties for a construct name.

**Returns:** `LIST` — Property list or nil

### `fmt-get-prop`

Get a specific property from a construct property list.

**Returns:** `ANY` — Property value or nil

### `fmt-comment?`

Test whether a token is a comment.

**Returns:** `BOOLEAN` — True if tok is a comment token

### `fmt-width`

Estimate the display width of a form using write-to-str.

**Returns:** `INTEGER` — Estimated display width in characters

### `fmt-expr`

Format any expression.

### `fmt-list`

Format a list form with indentation-aware pretty printing.

### `fmt-body`

### `fmt-tokens`

Format a list of top-level tokens with the given construct table.

