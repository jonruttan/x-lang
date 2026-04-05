[← Index](../../index.md)

# x/core/boolean

Short-circuit logical AND and OR operatives, plus timing.

### `and`

Short-circuit logical AND. Evaluates left to right, returns #f on first falsy value.

**Returns:** `ANY` — Last truthy value, or #f if any expression is falsy

**Examples:**

```
(and 1 2 3) => 3
(and 1 #f 3) => #f
```

### `or`

Short-circuit logical OR. Evaluates left to right, returns first truthy value.

**Returns:** `ANY` — First truthy value, or () if all are falsy

**Examples:**

```
(or #f 2 3) => 2
(or #f ()) => ()
```

### `time`

Time an expression. Prints elapsed microseconds to stdout, returns the result.

**Returns:** `ANY` — Result of the expression

