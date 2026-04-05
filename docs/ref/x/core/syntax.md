[← Index](../../index.md)

# x/core/syntax

Derived syntax forms: cond, case, when, unless, let*, letrec.

> These are operatives that extend the core syntax.

### `when`

Evaluate body forms when test is true.

**Parameters:**

- **test** : `ANY` — Expression to evaluate as a boolean
- **body** : `ANY` — One or more body expressions

### `unless`

Evaluate body forms when test is false.

**Parameters:**

- **test** : `ANY` — Expression to evaluate as a boolean
- **body** : `ANY` — One or more body expressions

### `let*`

Sequential let: bindings are evaluated left to right, each visible to the next.

**Parameters:**

- **bindings** : `LIST` — List of (name value) binding pairs
- **body** : `ANY` — One or more body expressions

### `letrec`

Recursive let: all bindings are visible to each other, enabling mutual recursion.

**Parameters:**

- **bindings** : `LIST` — List of (name value) binding pairs
- **body** : `ANY` — One or more body expressions

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

### `cond`

Multi-way conditional: evaluates clauses in order, returning the body of the first true test. Supports else and => syntax.

**Parameters:**

- **clauses** : `LIST` — List of (test body...) clauses; use else for default

### `case`

Dispatch on a value: evaluates key, then matches against datum lists in each clause.

**Parameters:**

- **key** : `ANY` — Expression to evaluate and match against
- **clauses** : `LIST` — List of ((datum ...) body...) clauses; use else for default

