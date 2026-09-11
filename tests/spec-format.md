# Spec Format (.spec.md)

BDD-style test specs as a markdown subset. Files use the `.spec.md`
extension so editors provide syntax highlighting and structure folding.

## Structure

````markdown
# @lib r5rs.x

## unit name

### test description

```x
(+ 1 2)
```
---
    3

### another test

    (str-length "hello")
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

```x
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

```x
()
```
---
````

### Full multi-line output

By default only the **last non-empty output line** is compared. To assert the
**full multi-line output** (formatters, pretty-printers, multi-line renders),
fence the expected block as `output`:

````markdown
### formats a nested form

```x
(fmt-expr (quote (a (b c))))
```
---
```output
(a
  (b c))
```
````

In this mode leading blank lines are ignored and the trailing newline is
trimmed; interior blank lines are significant. Errors are assertable too: the
harness prints an uncaught error to stdout as `Error: <value>`.

### NUL bytes

A zero byte in the captured output reaches the comparison as the literal text
`<<NUL>>`, so a spec asserts one by writing `<<NUL>>` in its expected block:

````markdown
### writes a zero byte
```x
(File write 1 buf 3)
```
---
```output
a<<NUL>>b
```
````

Escaping happens in the pipeline, before awk reads the line, because awk is a
C-string language: a raw NUL TERMINATES a record, so the rest of the line used
to be lost silently (`a\0b` compared as `a`). Only stdout is escaped -- a NUL
in stderr still truncates the diagnostic the harness quotes on a crash.

Two caveats. `display` stops at the zero byte itself, so it cannot put one on
the wire; use a door that takes an explicit length, like `(File write)`. And
like `<<SEP>>`, the sentinel is in-band: a program that prints the seven
characters `<<NUL>>` is indistinguishable from one that prints a zero byte.

The escaper needs `perl`. Without it the runner warns once and the old
truncation stands, so a spec asserting `<<NUL>>` fails rather than passing
quietly. `SPEC_NUL_FILTER` overrides the command (set it empty to disable).

## Running tests

Each lang has a `spec-runner.sh` that sets three variables
and sources the shared runner:

```sh
SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
SPEC_PATH="$SCRIPT_DIR/specs"
X_BIN="$SCRIPT_DIR/../../../x-bin"
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

| Lang | Tag |
|-------------|-----|
| x-lang | `x` |
| R5RS, R7RS, Kernel, Sweet, SL | `scheme` |
| ASH | `sh` |

The tag is decoration — [the runner](spec-runner.awk) collects any fenced
block the same way, and only `` ```output `` means anything to it. It is
still worth getting right, and x-lang's own specs are tagged `x` rather
than `scheme` for two reasons. It is what the rest of this repository
already uses: `` ```x `` is the tag the Pages build highlights (Rouge has
no x-lang lexer, so `tools/dev/highlight-sweep.sh` supplies one), and the
hand-written docs are written with it. And `scheme` is not true — x-lang
is not Scheme, it has no `car`/`cdr`, and a reader who trusts the tag,
human or machine, guesses a language that is not this one.

The `scheme` row is still right for the langs that *are* Scheme dialects,
and they keep it.

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

Test execution pipes `cat $LANG_LIB $tmpfile | $X_BIN`, strips REPL prompts
(`> `, `$ `), and compares the last non-empty output line against the expected
value — unless the expected block is fenced as `` ```output ``, in which case
the full multi-line output is compared (leading blanks ignored, trailing
newline trimmed, interior blanks significant).

Two stages sit between the engine and the comparison. Stderr is redirected to a
file, quoted only when a death message is being built (a green batch never
opens it). Stdout passes through the NUL escaper, so a zero byte arrives as
`<<NUL>>` instead of truncating the record — see **NUL bytes** above. Because
that escaper is the pipeline's last command, the engine's own exit status is
echoed to a file inside the pipeline rather than taken from `close()`, which
would otherwise report the escaper's 0 and lose the crash code.
