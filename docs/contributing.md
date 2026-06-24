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
make test-x          # x-lang spec suite
make test-c          # C unit tests
make test            # all tests (the full gate)
make test-asan       # both suites under AddressSanitizer (memory-safety net)
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

> **Last line only (default).** By default the runner compares only the **last non-empty stdout line**, and stderr is discarded. To assert a single multi-value result this way, put it on one line (e.g. `(display a)(display " ")(display b)`).
>
> **Multi-line output (`` ```output ``).** Fence the expected block as `` ```output `` to compare the **full multi-line stdout** instead — for formatters, pretty-printers, and any multi-line render. Leading blank lines are ignored and the trailing newline is trimmed; interior blank lines are significant. Errors are catchable too: the harness prints an uncaught error to stdout as `Error: <value>`, so a `` ```output `` block can assert it (or use `raised`/`throws?`). See `tests/x/specs/meta/multiline.spec.md`.
>
> A spec can swap in a custom support library with a `# @lib ../tests/x/lib/NAME.x` header — it *replaces* the default lib, so the support file must `(include "lib/x-core.x")` first (see `tests/x/lib/token.x`).

### The test-with-fix rule

**Every bug fix ships with a regression test in the same commit**, written so it **fails before the fix and passes after** — confirm both. A fix without a test that proves it is incomplete: nothing stops the bug from returning. This is the project's main defense against recurring "should-have-been-caught" regressions. A `fix:` commit that touches no `tests/` file is the smell to avoid.

### Error-path assertions

`tests/x/lib/assert.x` names the "this must raise" pattern, so the silent-failure class (a form that should raise but returns nil) can't read as a pass. Add `# @lib ../tests/x/lib/assert.x` to a spec, then:

- `(throws? (fn (_) EXPR))` → `#t` if `EXPR` raises, else `#f`
- `(raised  (fn (_) EXPR))` → the value `EXPR` raised, or the symbol `%none`

### Memory safety (AddressSanitizer)

`make test-asan` runs both suites against an ASan build. It catches the crash class that is silently wrong on 64-bit but faults on 32-bit/Pi (e.g. an unchecked read past an object) — run it before pushing C or eval-core changes. It is **report-only** for now: there is a tracked, pre-existing baseline finding, so confirm a red ASan run is actually *your* regression before acting on it.

### Pre-push gate

```sh
make install-hooks   # sets core.hooksPath=.githooks
```

The hook hard-gates on `make test` (both suites) and blocks the push if it fails (bypass a single push with `git push --no-verify`). `make test-asan` still crashes at HEAD on a tracked, pre-existing finding, so it runs only on demand and non-blocking — `RUN_ASAN=1`. **Promote it into the hard gate once it is green.**

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
