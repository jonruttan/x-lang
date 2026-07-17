# x-lang Linter

Static analysis for x-lang programs: detects undefined symbol references and unused definitions.

## Usage

```sh
# Lint a single file
sh tools/lint.sh FILE

# Lint all library files
sh tools/lint.sh
# or: make lint-x

# Lint in library mode (suppresses unused warnings)
sh tools/lint.sh --lib FILE
```

## Rules

### Undefined Symbols

Reports symbols that are referenced but never defined. The linter auto-discovers built-in names from the current environment, so standard library functions are not flagged.

### Unused Definitions

Reports `def` bindings that are never referenced. Exceptions:
- **`%`-prefixed names**: Internal/private names (e.g., `%helper`) are not flagged as unused.
- **`--lib` mode**: When linting library files, all unused warnings are suppressed since exports are used by downstream code.

## Scope Tracking

The linter walks the AST and tracks scoping for:
- `def` / `set!` -- definitions and mutations
- `fn` -- parameter bindings
- `op` -- parameter and env-param bindings
- `let` -- local bindings
- `guard` -- error variable binding
- `lit` -- opaque (contents not analyzed)
- `quasi` / `unquote` -- only unquoted parts are analyzed

## Architecture

- `tools/lint-lib.x` -- Core linting functions (extracted library)
- `tools/lint.x` -- CLI wrapper (includes lint-lib.x, reads input, reports)
- `tools/lint.sh` -- Shell wrapper (handles file discovery and `--lib` mode)

## Tests

```sh
make test-tools
```
