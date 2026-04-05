[← Index](../../index.md)

# x/tool/lint

AST linter: def/use analysis for x-lang source.

### `lint-forms`

Walk top-level forms, collecting definitions and symbol uses.

**Returns:** `LIST` — (defs uses) pair

### `lint-undefined`

Compute undefined symbols: used but not in env or file defs.

**Returns:** `LIST` — Symbols used but not defined

### `lint-unused`

Compute unused symbols: defined but not referenced. Skips %-prefixed internals.

**Returns:** `LIST` — Symbols defined but never used

