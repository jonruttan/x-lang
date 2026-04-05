[← Index](../../index.md)

# x/tool/profile

Performance profiling and smart garbage collection.

### `alloc-count`

Return the number of heap objects allocated.

**Returns:** `INTEGER` — Total heap allocations since last reset

### `eval-count`

Return the number of eval invocations.

**Returns:** `INTEGER` — Total eval calls since last reset

### `tco-count`

Return the number of tail-call optimizations performed.

**Returns:** `INTEGER` — Total tail-call optimizations since last reset

### `assoc-calls-count`

Return the number of association list lookup operations.

**Returns:** `INTEGER` — Total alist lookup calls

### `assoc-steps-count`

Return the total steps walked during alist lookups.

**Returns:** `INTEGER` — Total alist walk steps

### `sym-find-calls-count`

Return the number of symbol lookup operations.

**Returns:** `INTEGER` — Total symbol-find calls

### `sym-find-steps-count`

Return the total steps walked during symbol lookups.

**Returns:** `INTEGER` — Total symbol-find steps

### `gc-runs-count`

Return the number of garbage collection runs.

**Returns:** `INTEGER` — Total GC mark/sweep cycles

### `bst-hits-count`

Return the number of successful BST (binary search tree) lookups.

**Returns:** `INTEGER` — BST cache hits

### `bst-misses-count`

Return the number of BST lookups that fell through to alist walk.

**Returns:** `INTEGER` — BST cache misses

### `profile-reset`

Reset all performance counters to zero.

### `heap-collect-force`

Force a full GC mark/sweep cycle, returning the number of objects freed.

**Returns:** `INTEGER` — Number of objects freed

### `heap-collect`

Smart GC: only collect when allocations since last run exceed surviving objects.

**Returns:** `INTEGER` — Number of objects freed, or 0 if skipped

### `profile-dump`

Dump all profile counters to stderr.

