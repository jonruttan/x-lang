[← Index](../../index.md)

# x/core/fn

Higher-order function combinators.

## Combinators

### `identity`

Return the given value unchanged.

**Parameters:**

- **x** : `ANY` — Value to return

**Returns:** `ANY` — The input value unchanged

### `const`

Return a function that always returns x, ignoring its argument.

**Parameters:**

- **x** : `ANY` — Value to capture

**Returns:** `CALLABLE` — A function that always returns x

### `compose`

Right-to-left function composition: (compose f g) returns a function that applies g then f.

**Parameters:**

- **f** : `CALLABLE` — Outer function
- **g** : `CALLABLE` — Inner function

**Returns:** `CALLABLE` — Composed function: f(g(x))

### `pipe`

Left-to-right function composition: (pipe f g) returns a function that applies f then g.

**Parameters:**

- **f** : `CALLABLE` — First function
- **g** : `CALLABLE` — Second function

**Returns:** `CALLABLE` — Piped function: g(f(x))

### `curry`

Partially apply a binary function by fixing its first argument.

**Parameters:**

- **f** : `CALLABLE` — Binary function to partially apply
- **x** : `ANY` — First argument to bind

**Returns:** `CALLABLE` — Partially applied function awaiting one argument

### `flip`

Return a function that calls f with its two arguments reversed.

**Parameters:**

- **f** : `CALLABLE` — Binary function

**Returns:** `CALLABLE` — Function with reversed argument order

### `tap`

Return a function that calls f on its argument for side effects, then returns the argument.

**Parameters:**

- **f** : `CALLABLE` — Side-effect function

**Returns:** `CALLABLE` — Function that applies f for side effects and returns x

