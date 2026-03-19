# x-heap.c 100% Coverage Plan

## Problem
`ext/x-expr/x-heap.c` shows 0% coverage in the main project's gcov report.
The x-expr subproject has its own `3.x-heap.spec.c` but those results don't
feed into the main project's coverage tooling.

## Solution
Create `tests/c/src/8.x-heap.spec.c` in the main project's test suite that
unity-includes `ext/x-expr/src/x-heap.c` and exercises all branches.

## Functions to cover (2 functions, ~25 executable lines)

### `x_heap_mark` — 6 branches
1. `p_obj == NULL` → early return (while condition false)
2. Already-marked object (flags already set) → skip (while condition false)
3. Simple pair → recurse first, iterate rest
4. Non-pair, `p_mark_fn == NULL` → break
5. Non-pair, `p_mark_fn != NULL`, returns non-NULL → continue
6. Non-pair, `p_mark_fn != NULL`, returns NULL → break

### `x_heap_sweep` — 5 branches
1. `prev` when `x_obj_heap(p_base) == p_obj` → prev = p_base
2. `prev` when `x_obj_heap(p_base) != p_obj` → prev = p_obj
3. Marked object (flags set) → clear flags, advance
4. Unmarked object, `p_free_fn == NULL` → free, relink
5. Unmarked object, `p_free_fn != NULL` → call callback, free, relink

## Test structure
- Unity-build includes: x-sys.c, x-lib.c, x-obj.c, x-heap.c
- Stubs: STUB_X_PROCEDURE
- Uses helper-system-functions.c for malloc/free tracking
- 8 test functions, ~20 assertions

## Verification
```
make test TESTS=tests/c/src/8.x-heap.spec.c
make test  # all green
```
