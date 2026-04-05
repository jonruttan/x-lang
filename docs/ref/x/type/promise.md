[← Index](../../index.md)

# x/type/promise

Lazy evaluation with delay/force.

> Promises are memoized -- forced only once.

## Predicates

### `promise?`

Test whether a value is a promise.

**Parameters:**

- **x** : `ANY` — Value to test

**Returns:** `BOOL` — True if x is a promise

## Construction and evaluation

### `delay`

Create a promise that delays evaluation of an expression until forced.

### `force`

Force a promise, returning its cached value. Non-promises pass through.

**Parameters:**

- **p** : `ANY` — Promise or value

**Returns:** `ANY` — The forced value, or p itself if not a promise

