# Spec Format (.spec.md)

BDD-style test specs as a markdown subset. Files use the `.spec.md`
extension so editors provide syntax highlighting and structure folding.

## Structure

````markdown
# @lib r5rs.x

## unit name

### test description

```scheme
(+ 1 2)
```
---
    3

### another test

    (string-length "hello")
---
    5

### pending test (no --- separator)
````

## Rules

| Marker | Meaning |
|--------|---------|
| `# @lib PATH` | Library override (relative to default lib dir) |
| `## text` | Unit / describe group |
| `### text` | Test case |
| `---` | Separator between input and expected output |
| `` ``` `` | Fenced code block (with optional language tag) |
| 4-space indent | Indented code block |

### Content blocks

Test input and expected output must be in one of two forms:

**Fenced code block** (preferred for input — enables syntax highlighting):

````markdown
### test name

```scheme
(define x 42)
x
```
---
    42
````

**Indented block** (4-space or 1-tab prefix, stripped by runner):

````markdown
### test name

    (define x 42)
    x
---
    42
````

Bare lines (no indent, no fence) are ignored. This means prose, notes,
and other markdown content can appear freely between tests.

### Blank lines

- After `##` and `###` headings: required (markdown convention)
- Between tests: recommended for readability
- Inside fenced blocks: preserved as literal content
- After `---` in expected output: triggers test flush

### Pending tests

A `###` heading with no `---` separator before the next heading is
counted as pending (displayed as `p` in output).

### Nil expected output

When the expected output is empty (e.g., evaluating `()`), place nothing
after `---`:

````markdown
### evaluates nil

```scheme
()
```
---
````

## Running tests

Each language personality has a `spec-runner.sh` that sets three variables
and sources the shared runner:

```sh
SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
SPEC_PATH="$SCRIPT_DIR/specs"
X_BIN="$SCRIPT_DIR/../../../x"
LANG_LIB="$SCRIPT_DIR/../lib/r5rs.x"

. "$SCRIPT_DIR/../../../tests/spec-runner.sh"
```

The shared runner (`tests/spec-runner.sh`) launches one AWK process per
`.spec.md` file in parallel, then aggregates results.

### Commands

```sh
sh tests/x/spec-runner.sh          # x-lang (792 tests)
sh lang/r5rs/tests/spec-runner.sh  # R5RS   (327 tests)
sh lang/r7rs/tests/spec-runner.sh  # R7RS   (516 tests)
sh lang/krn/tests/spec-runner.sh   # Kernel  (72 tests)
sh lang/ash/tests/spec-runner.sh   # ASH     (82 tests)
sh lang/sweet/tests/spec-runner.sh # Sweet   (31 tests)
```

## Language tags

| Personality | Tag |
|-------------|-----|
| x-lang, R5RS, R7RS, Kernel, Sweet, SL | `scheme` |
| ASH | `sh` |

## AWK runner internals

`tests/spec-runner.awk` is a POSIX AWK state machine with three states:

| State | Name | Collects |
|-------|------|----------|
| 0 | IDLE | Nothing (metadata, prose ignored) |
| 1 | INPUT | Test input lines |
| 2 | EXPECT | Expected output lines |

Transitions: `###` &rarr; INPUT, `---` &rarr; EXPECT, blank line or
next heading &rarr; IDLE.

Content is collected from fenced blocks (literal, between `` ``` ``
markers) or indented blocks (4-space / tab prefix stripped). Bare lines
are ignored.

Test execution pipes `cat $LANG_LIB $tmpfile | $X_BIN 2>/dev/null`,
strips REPL prompts (`> `, `$ `), and compares the last non-empty output
line against the expected value.
