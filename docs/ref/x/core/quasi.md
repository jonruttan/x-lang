[← Index](../../index.md)

# x/core/quasi

Quasiquote: template with unquote and splicing.

### `quasi`

Quasiquote: template with unquote and splicing.

> Compile-on-first-use: the template is compiled to a pair/lit/append tree on first evaluation, then cached.

**Returns:** `ANY` — Expanded template with substitutions

**Examples:**

```
(def x 1) (quasi (a ,x b)) => (a 1 b)
```

