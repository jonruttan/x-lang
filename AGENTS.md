# AGENTS.md — x-lang for coding agents

This is the briefing. It exists because the rest of the documentation is
written for a person reading in order, and an agent arrives in the middle,
needs six facts, and will otherwise guess them wrong — the same six, every
time. Read this file first; it is short on purpose and every claim in it is
checkable with one command.

`CLAUDE.md` is a symlink to this file.

## What x-lang is, in three sentences

A minimal, type-agnostic **engine** provides atoms, pairs, an adaptive
runtime type system, and fexpr-based evaluation. Everything else — the
semantics, the standard library, the object system, the numeric tower, the
JIT, the toolchain — is written in x-lang on top of it, in layers, none of
which modify the layer below. s-expressions are the initial syntax, not the
only one: the reader is extensible, and whole surface languages (Scheme, C,
Python, awk) load on top as **langs**.

The engine lives in a separate repository and arrives as a pinned, verified
artifact behind [a published contract](docs/engine-contract.md). This
repository is the *language*. The `engine` symlink is the only path to it.

## Run it

```bash
sh x.sh -q -c '(write (+ 1 2))'      # evaluate an expression and exit
sh x.sh -q -f program.x              # evaluate a file and exit
echo '(write (+ 1 2))' | sh x.sh -q  # stdin is program text
sh x.sh                              # REPL (needs a terminal)
```

`-c/--eval` is repeatable and expressions run in order, so a definition and
its use can share one command:

```bash
sh x.sh -q -l xe -c '(def sq (fn (_ n) (* n n)))' -c '(write (sq 12))'
```

Errors go to stderr and exit non-zero. `-q` suppresses the banner. There is
no implicit printing — **an expression's value is not shown unless you print
it**; use `(write x)` for the machine-readable form, `(display x)` for the
human one, `(newline)` between them.

### Never invoke the engine directly

Do not run `./x-bin` (or `x-bin-asan`, `x-bin-cov`, …). Run bare, it has no
allocation ceiling and a runaway program takes the machine down — nine
documented OOM incidents. A `PreToolUse` hook
([.claude/hooks/x-guard.sh](.claude/hooks/x-guard.sh)) blocks it, but the
hook is a backstop, not the rule. The safe routes arm limits first: `x.sh`
(pipes the library onto stdin, which arms conservative limits) and
`tests/x/spec-runner.sh` (arms `X_ALLOC_LIMIT_OBJS` per spec).

## It is not Scheme

It looks like a Lisp and it is not one. These are the guesses that fail,
and they fail on the first line you write:

| You will reach for | It is actually | Note |
|---|---|---|
| `car` / `cdr` | `first` / `rest` | `car` is unbound |
| `print` | `write` / `display` | `print` is unbound |
| `(string-split s ",")` | `("a,b" split ",")` | methods dispatch **subject-last** |
| `(lambda (x) …)` | `(fn (self x) …)` | every closure gets **itself** as argument 0 |
| `(define …)` | `(def …)` | |
| `(quote x)` / `'x` | `'x` or `(lit x)` | both work; `lit` is the primitive |
| `#t` / `#f` | same | falsy is exactly `{nil, #f}` — `0` and `""` are true |

Three more that have no Scheme analogue at all:

- **`op` is the core, `fn` is derived.** `(op (x) e …)` receives its
  arguments **unevaluated** plus the caller's environment as `e`. `fn`
  is the applicative wrapper. Primitives are operatives.
- **Self as argument 0.** `(fn (self n) … (self (- n 1)))` recurses with no
  global name. Write `_` for the slot when you do not need it:
  `(fn (_ a b) (+ a b))`.
- **A value is callable and dispatches to its class**, subject-last:
  `("hello,world" split ",")`, `((list 10 20 30) 1)`, `(1/2 numerator)`.

## Finding out what exists

This is the part worth internalising, because it replaces guessing. The
library documents itself, and three calls reach all of it:

```bash
sh x.sh -q -c '(apropos "split")'    # search every documented name
sh x.sh -q -c '(help Str8/split)'    # signature, arg types, return, example
sh x.sh -q -c '(help x/core/math)'   # a module: its exports
sh x.sh -q -c '(modules)'            # every module, with [loaded] markers
sh x.sh -q -c '(help)'               # the overview
```

`(help Name/method)` is the high-value one. It answers with the real
signature, every argument's type and meaning, the return type, and a
runnable example:

```
Str8/split: Split s into a list of pieces around each occurrence of sep.
  sep : STRING -- Separator to split on
  s : STRING -- String to split
  => LIST -- List of substrings of s between separators
  > (Str8 split "," "a,b,c") => ("a" "b" "c")
```

Reach for `apropos` before grepping the library, and before assuming a
function does not exist. Names are not the ones you would guess
(`Str8 upcase`, not `upper`), but they are all in there.

A missed method suggests near matches — `no such method splt -- did you
mean split?` — so a typo self-corrects, but a wrong *concept* will not.

**The generated API reference** covers every module, built from the
`(doc …)` forms in the source: <https://jonruttan.github.io/x-lang/> — the
whole documentation set is published there, both generated references
included. Offline, `make doc-x` writes it to `docs/ref/x/` (it is generated
in CI, not committed, so a fresh clone will not have it until you build it).

## Dialects: pick the right one or things will be "missing"

The library composes into three dialects, and **helium is the default**.
Most "that function doesn't exist" confusion is a dialect mismatch.

| Flag | Dialect | Has |
|---|---|---|
| *(none)* | helium (`lib/x.x` → `lib/he.x`) | 40+ modules: combinators, lists, sort, strings, vectors, promises, quasiquote, REPL. **No numeric tower.** |
| `-l xe` | xenon | helium + POSIX, hash tables, JIT, the full numeric tower (bigint, float, rational, complex, decimal) |
| `-l rn` | radon | xenon + raw syscalls, char/IO constants; file I/O and sockets on demand. **Experimental.** |

```bash
sh x.sh -q -c '(write (+ 1/3 1/6))'        # helium: fails, no tower
sh x.sh -q -l xe -c '(write (+ 1/3 1/6))'  # xenon: 1/2
```

Load a module explicitly with `(import x/type/regex)`. Modules are
auto-discovered and deduplicated.

## Where things are

| Path | What |
|---|---|
| `lib/x/**` | the library, ~130 modules, all x-lang. The `(doc …)` forms here generate the API reference. |
| `lib/x.x`, `lib/xe.x`, `lib/rn.x` | dialect entry points |
| `engine` → | symlink to the engine checkout or unpacked release. Not this repo. |
| `tests/x/specs/**` | **142 spec files: executable examples with expected output.** The best corpus for "how is this actually used". |
| `tests/x/conformance/**` | what judges an engine implementation |
| `docs/` | 28 hand-written documents; [docs/index.md](docs/index.md) is the front door |
| `tools/` | self-hosted linter, formatter, coverage, profiler, doc generator |
| `apps/`, `examples/` | worked programs |

Reading `tests/x/specs/**` is usually faster than reading prose. Each test
is a heading, a fenced x-lang block, a `---` line, and the expected last
line of output — shown here indented, since the real thing is markdown:

    ### detects undefined symbol reference

    ```x
    (display (lint-has? "x" %undef))
    ```
    ---
        #t

The format is [tests/spec-format.md](tests/spec-format.md). x-lang's own
specs are tagged `x`, not `scheme` — a reader who trusts a `scheme` tag
guesses a language that is not this one.

## Conventions that will bite

- **`%` means private** — `%str-append`, `%class-call-handler`. Not API.
  Do not call it from user code and do not put it in docs.
- **Indexes are 0-based; negatives count from the end.**
- **Misses return nil, never `#f`.** Predicates answer `#t`/`#f`. Falsy is
  exactly `{nil, #f}`.
- **member / field / slot are three different tiers**, not synonyms — see
  [docs/contributing.md](docs/contributing.md).
- Doc type vocabulary is fixed: `INT` not INTEGER, `BOOL` not BOOLEAN,
  `CALLABLE` not FUNCTION. `make check-doc-vocab` enforces it.

Full style rules: [docs/contributing.md](docs/contributing.md) and
[CONVENTIONS.md](CONVENTIONS.md).

## Testing and gates

```bash
make test-x       # the x-lang spec suite (2,800+ cases), each job booted
                  # from a state image; IMG=0 boots every library from source
make test-c       # the engine's C unit tests (delegated; a fetched
                  # release ships no C and says it skipped)
make test         # everything
make lint         # the self-hosted linter
```

Run `make test-x` after touching anything under `lib/`. CI runs the full
suite on macOS and Linux plus a hard AddressSanitizer gate.

## Documentation map

Start at [docs/index.md](docs/index.md). When you need one specific thing:

| Question | Document |
|---|---|
| What does this word mean? | [glossary.md](docs/glossary.md) |
| Is this behaviour normative? | [spec.md](docs/spec.md) |
| How does evaluation work? | [architecture.md](docs/architecture.md) |
| How do types/dispatch work? | [type-system.md](docs/type-system.md) |
| How do classes work? | [object-system.md](docs/object-system.md) |
| What can I write? | [syntax.md](docs/syntax.md), [primitives.md](docs/primitives.md) |
| What's in the library? | [standard-library.md](docs/standard-library.md), or `apropos` |
| How do modules/pinning work? | [modules.md](docs/modules.md) |
| What must an engine provide? | [engine-contract.md](docs/engine-contract.md) |
| How do I build a surface language? | [crafting-a-lang.md](docs/crafting-a-lang.md) |

## If you change something

- The `(doc …)` form beside a definition **is** the reference — update it in
  the same edit, never in a separate pass.
- Do not hand-copy a fact that already lives somewhere else. This project
  treats a duplicated fact as a bug: a copy nobody checks goes stale and
  tells the next reader something false. Link to the source instead.
- Commit style and PR conventions: [docs/contributing.md](docs/contributing.md).
