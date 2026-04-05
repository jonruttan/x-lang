[← Index](../../index.md)

# x/core/arithmetic

### `modulo-int`

### `+`

Variadic addition. Returns the sum of all arguments.

**Parameters:**

- **args** : `NUMBER` — Zero or more numbers

**Returns:** `NUMBER` — Sum of all arguments, or 0 with no arguments

**Examples:**

```
(+ 1 2 3) => 6
(+) => 0
```

### `*`

Variadic multiplication. Returns the product of all arguments.

**Parameters:**

- **args** : `NUMBER` — Zero or more numbers

**Returns:** `NUMBER` — Product of all arguments, or 1 with no arguments

**Examples:**

```
(* 2 3 4) => 24
(*) => 1
```

### `/`

Variadic integer division. Folds left.

**Parameters:**

- **args** : `NUMBER` — One or more numbers

**Returns:** `NUMBER` — Quotient from left fold

**Examples:**

```
(/ 100 5 2) => 10
```

### `-`

Variadic subtraction. With one argument, negates. With multiple, folds left.

**Parameters:**

- **args** : `NUMBER` — One or more numbers

**Returns:** `NUMBER` — Difference, or negation with one argument

**Examples:**

```
(- 10 3 2) => 5
(- 5) => -5
```

