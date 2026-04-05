[← Index](../../index.md)

# x/tool/cov

Library coverage analysis for x-profile instrumented code.

### `cov-covered?`

Test whether an object was marked as evaluated by x-profile.

**Returns:** `BOOLEAN` — True if object was evaluated (FLAG_2 set)

### `cov-count-tree`

Count covered and total AST nodes in a tree.

**Returns:** `LIST` — (covered total) pair

### `cov-check-fn`

Check coverage for a single function.

**Returns:** `LIST` — (name covered total) or nil

### `cov-walk`

Walk an environment alist checking coverage on each procedure.

### `cov-skip-to-library`

Skip past test definitions to the library boundary marker.

**Returns:** `LIST` — Alist from library boundary marker onward

