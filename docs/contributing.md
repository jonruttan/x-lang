# Contributing

## Build Prerequisites

- A C89-compatible compiler (gcc, clang, tcc, c89, c99)
- POSIX shell (`sh`) for test runners
- Make

```sh
make clean && make
```

## Code Style

### C Code

- **C89 standard** — Variables declared at the top of blocks, no C99 features
- **`x_` prefix** — All exported symbols use the `x_` prefix
- **Naming** — Use `pair`/`first`/`rest`, never cons/car/cdr. Use `fn`/`def`/`set`/`do`/`op`/`lit`/`quasi`/`match`
- **No globals** — All interpreter state belongs on `p_base`. Never use static or global variables for state
- **Stack-allocated pairs** — Prefer `x_satom_t`/`x_spair_t` over heap allocation where possible
- **Doxygen comments** — All public functions and macros documented with `@brief`, `@param`, `@return`. File headers include `@file`, `@brief`, `@author`, `@copyright`, `@license`, and the ASCII owl

### x-lang Code

- **Module structure** — Dependencies via `(import ...)`, exports via `(provide ...)` at file bottom
- **Documentation** — Wrap definitions in `(doc ...)` forms with `(param ...)`, `(returns ...)`, description string
- **No `cond`/`convert` in tokenizer callbacks** — Use nested `if` and direct C primitives to avoid GC corruption
- **File extension** — `.x`

## Testing

### Test Structure

Tests are markdown spec files in `tests/x/specs/` organized by category:

- `core/` — Language fundamentals (evaluation, forms, closures, logic, arithmetic, strings, etc.)
- `applicative/` — Higher-order function tests
- `ext/` — Extension types (bignum, float, rational, complex, regex, compile, POSIX)
- `lib/` — Standard library functions
- `e2e/` — End-to-end integration tests
- `tools/` — Tool tests (lint, fmt)

### Running Tests

```sh
make test-x          # x-lang tests (1229 cases)
make test-c          # C unit tests
make test            # all tests
```

### Adding Tests

Tests use a markdown format where each `###` heading is a test case:

```markdown
## section-name

### test description

\`\`\`scheme
(expression)
\`\`\`
---
    expected output
```

The spec runner evaluates the `scheme` code block and compares stdout against the indented expected output after the `---` separator.

## Commit Conventions

This project follows [AngularJS commit conventions](CONVENTIONS.md):

```
<type>(<scope>): <subject>
```

Types: `feat`, `fix`, `docs`, `style`, `refactor`, `test`, `chore`

Only `feat` and `fix` appear in changelogs.

## Documentation

### Generating Docs

```sh
make doc-c           # C API reference (Doxygen → docs/ref/c/)
make doc-x           # x-lang library reference (doc-gen → docs/ref/x/)
make doc             # both
```

### Adding Library Documentation

Wrap function definitions in `(doc ...)`:

```scheme
(doc (def my-function
  (fn (_ x y)
    (+ x y)))
  (param x INTEGER "First operand")
  (param y INTEGER "Second operand")
  (returns INTEGER "Sum of x and y")
  "Add two integers.")
```

The `(doc ...)` form is transparent — it evaluates the inner `def` normally, then registers metadata for the doc generator.

## License

MIT No Attribution (MIT-0)
