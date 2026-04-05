[← Index](../../index.md)

# x/core/control

### `if`

Conditional: evaluate test, then branch.

**Parameters:**

- **test** : `ANY` — Condition expression
- **then** : `ANY` — True branch
- **else** : `ANY` — False branch (optional)

**Examples:**

```
(if (> 3 2) "yes" "no") => "yes"
```

**See also:** [`match`](#match) [`cond`](#cond) 

### `let`

Bind local variables and evaluate body.

> Named let: (let name ((var init) ...) body) creates a loop.

**Parameters:**

- **bindings** : `LIST` — ((name value) ...) binding pairs
- **body** : `ANY` — Body expression

**Examples:**

```
(let ((x 1) (y 2)) (+ x y)) => 3
(let loop ((n 5) (acc 1)) (if (= n 0) acc (loop (- n 1) (* acc n)))) => 120
```

**See also:** [`let*`](#let*) [`letrec`](#letrec) 

