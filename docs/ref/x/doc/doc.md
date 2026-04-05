[← Index](../../index.md)

# x/doc/doc

Inline documentation system.

> doc wraps def or provide for metadata. help for REPL lookup. apropos for search.

### `doc`

Attach documentation metadata to a definition, provide, or bare symbol.

> Three forms: (doc (def name val) meta... desc), (doc (provide name syms) meta... desc), (doc name meta... desc)

> Meta forms: (param name TYPE desc), (returns TYPE desc), (example expr result), (see name), (note text)

### `note`

Section marker for documentation grouping. No-op at runtime.

**Parameters:**

- **text** : `STRING` — Section description

### `help`

Look up documentation in the REPL.

> (help) shows overview. (help name) shows function or module docs. (help modules) lists all modules.

### `apropos`

Search documentation by name substring.

**Parameters:**

- **str** : `STRING` — Substring to search for

### `modules`

List all known modules with load status and descriptions.

