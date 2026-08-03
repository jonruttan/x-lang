# Dev tools

Developer conveniences: formatter, linter, coverage, benchmarks, doc
generation.  None of these are gates -- the contract gates live in
`tools/check/` (see `tools/README.md` for the taxonomy).

## Formatter

Auto-formatter for x-lang source files with configurable width threshold.

```sh
# Print formatted output to stdout (a pure filter)
sh x.sh --no-pin -q -f tools/dev/fmt.x -- FILE

# Format all library files in place / check formatting
make fmt-x
make fmt-check-x
```

In-place and check modes are launch glue in the make recipes; the tool
itself is a filter.  NOTE: `make fmt-check-x` is currently red on four
hand-formatted files (x-core.x, constructs.x, rn.x, xe.x) whose layout
disagrees with the formatter's width rules -- a pre-existing style
adjudication tracked in the overhaul follow-ups.

### Formatting rules

Forms shorter than 60 characters stay on one line.  Longer forms break
across multiple lines with 2-space indentation.

| Form | Rule |
|------|------|
| `def` | Name on same line, body at +2 |
| `if` | Condition on same line, branches at +2 |
| `fn` / `op` | Params on same line, body at +2 |
| `do` / `begin` | Body forms at +2 |
| `let` | Bindings on same line, body at +2 |
| `match` / `cond` | Clauses at +2 |

`;` line comments are preserved; quoted strings are preserved exactly;
`()` is output for nil; atoms output raw.

### Architecture

- `tools/dev/fmt.x` -- the whole tool (slurps constructs + target by
  path, tokenizes with a fresh comment-keeping base, walks, emits)

## Linter

Static analysis: undefined symbol references and unused definitions.

```sh
# Lint a single file
sh tools/dev/lint.sh FILE

# Lint all library files
sh tools/dev/lint.sh
# or: make lint-x

# Lint in library mode (suppresses unused warnings)
sh tools/dev/lint.sh --lib FILE
```

Undefined symbols are auto-discovered against the current environment, so
built-ins are never flagged.  `%`-prefixed names are exempt from unused
warnings; `--lib` mode suppresses unused warnings entirely (library
exports are used downstream).  Scope tracking covers `def`/`set!`, `fn`,
`op`, `let`, `guard`; `lit` is opaque; `quasi` walks only unquoted parts.

### Architecture

- `tools/dev/lint.x` -- the linter (scope walk + reporting; the `%lint-lib`
  first-form token is its library-mode flag)
- `tools/dev/lint.sh` -- launch wrapper (file discovery, constructs input)
- `tools/dev/lint-lib.x` -- legacy def/use analysis library; loaded by
  nothing but its own specs (see Tests below)

## Coverage

Flag-bit branch coverage for x-lang programs.  The `x-bin-cov` binary is
a modified build that sets `X_OBJ_FLAG_2` (0x2) on every AST node at eval
time; the reporter walks the original AST afterwards and reports which
`if`/`match`/`cond` branches never ran.

```sh
sh tools/dev/cov.sh FILE      # single-file branch coverage
sh tools/dev/cov-lib.sh      # aggregated library coverage (x-bin-profile)
```

NOTE: the `make x-bin-cov` build target this tool needs is currently
absent from the Makefile (pre-existing rot; only `make clean` remembers
the binary).  Restoring it is tracked in the tools-overhaul follow-ups.

1. **Marking**: `x-bin-cov` adds one line to `x_eval()` under `#ifdef
   X_COV`, setting bit 0x2 on every evaluated expression's flags field.
2. **Tokenization**: the reporter (`cov.x`) reads the source as a string
   and tokenizes with `(Tok read-str)` on the current base.
3. **Evaluation**: an operative loop evaluates each top-level form
   (operatives, not closures, so `def` effects persist).
4. **Walking**: branch nodes without the flag are reported.

The GC sweep clears only `X_OBJ_FLAG_HEAP`, so coverage flags survive
collection.  Limitations: interned atoms are shared (marking one `x`
marks them all -- compound branch expressions are the reliable signal);
no line numbers; the target must run under `x-bin-cov` itself.

## Others

- `tools/dev/bench.sh` -- library-load benchmarks over `x-bin-profile`
- `tools/dev/doc.x` -- Markdown doc generation from source (per-file filter)
- `tools/dev/doc-index.x` -- the `docs/ref` master index (filter)

## Tests

```sh
make test-tools
```

Runs `tools/tests/` (fmt + lint + cov specs).  CURRENTLY RED and not part
of `make test`: the suite rotted while orphaned (nothing invoked it; API
drift accumulated -- `make-base` retired for `(Base make)`, `includes?`
homed onto List, printer output changes).  It rejoins the gate when the
specs are repaired or folded into `tests/x/specs/` -- tracked in the
tools-overhaul follow-up issue.
