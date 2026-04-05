[← Index](../../index.md)

# x/num/tower

Numeric tower helpers for building type-promoting operators.

### `%make-fold-op`

Create a variadic arithmetic operator that promotes operands to a numeric type.

**Parameters:**

- **pred?** : `CALLABLE` — Type predicate
- **type-op** : `CALLABLE` — Binary type-specific operation
- **coerce** : `CALLABLE` — Coercion to this type
- **prev-op** : `CALLABLE` — Fallback operator for other types
- **identity** : `NUMBER` — Identity element (0 for +, 1 for *)

**Returns:** `CALLABLE` — Variadic operator with type promotion

### `%make-cmp-op`

Create a binary comparison operator that promotes operands to a numeric type.

**Parameters:**

- **pred?** : `CALLABLE` — Type predicate
- **type-cmp** : `CALLABLE` — Binary type-specific comparison
- **coerce** : `CALLABLE` — Coercion to this type
- **prev-op** : `CALLABLE` — Fallback comparison for other types

**Returns:** `CALLABLE` — Binary comparison with type promotion

