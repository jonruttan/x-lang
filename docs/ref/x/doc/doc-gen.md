[← Index](../../index.md)

# x/doc/doc-gen

Markdown documentation generator from x-lang source tokens.

### `doc-sym-is?`

Test if a value is a symbol matching a name string (cross-base safe).

**Returns:** `BOOLEAN` — True if sym is a symbol with the given name

### `doc-form?`

### `doc-note-form?`

### `doc-def-form?`

### `doc-set-form?`

### `doc-param-form?`

### `doc-provide-form?`

### `doc-find-last-string`

### `doc-extract-params`

### `doc-extract-meta-type`

### `doc-extract`

Extract structured metadata from a (doc ...) form.

**Returns:** `LIST` — (name desc params returns examples sees notes)

### `doc-emit-heading`

### `doc-emit-param`

### `doc-emit-entry`

Emit a single function's documentation as Markdown.

### `doc-build-lookup`

Build a lookup alist from (doc ...) forms in a token stream.

**Returns:** `LIST` — Alist of (name-string . extracted-7-tuple) pairs

### `doc-lookup-alist`

Cross-base-safe lookup in a doc alist by name string.

**Returns:** `LIST` — Extracted 7-tuple, or () if not found

### `doc-walk-with-prims`

Walk source tokens, using prims-alist as fallback docs for bare defs.

### `doc-walk`

Walk a token tree, extracting and emitting all documentation as Markdown.

