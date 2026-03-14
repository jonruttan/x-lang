# x-lang Formatter

Auto-formatter for x-lang source files with configurable width threshold.

## Usage

```sh
# Print formatted output to stdout
sh tools/fmt.sh FILE

# Format file in place
sh tools/fmt.sh -i FILE

# Check formatting (exit 1 if changes needed)
sh tools/fmt.sh --check FILE

# Format all library files
make fmt-x
```

## Formatting Rules

### Width Threshold

Forms shorter than 60 characters stay on one line. Longer forms are broken across multiple lines with 2-space indentation.

### Special Form Indentation

| Form | Rule |
|------|------|
| `def` | Name on same line, body at +2 |
| `if` | Condition on same line, branches at +2 |
| `fn` / `op` | Params on same line, body at +2 |
| `do` / `begin` | Body forms at +2 |
| `let` | Bindings on same line, body at +2 |
| `match` / `cond` | Clauses at +2 |

### Other Behavior

- **Comments**: `;` line comments are preserved in output
- **Strings**: Quoted strings are preserved exactly
- **Nil**: `()` is output for nil values
- **Atoms**: Symbols output raw, integers as digits, characters as bare chars

## Architecture

- `tools/fmt.x` -- Formatter implementation (tokenizes input, walks AST, emits formatted output)
- `tools/fmt.sh` -- Shell wrapper (handles `-i`, `--check`, file I/O)

## Tests

```sh
make test-tools
```
