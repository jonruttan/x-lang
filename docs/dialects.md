# x-lang Dialects

*x-lang: computational expressions over a minimal, type-agnostic engine.*


A dialect is a composition of x-lang library modules that determines what capabilities are loaded. The dialects are named after noble gases — the theme ties to the x-expr/Xe etymology, and read correctly it is self-teaching along the two axes that actually distinguish the entries:

- **Atomic weight = library weight.** Helium is light: fast boot, no numeric tower. Xenon and radon are heavy: the full tower, regular expressions, the compiler.
- **Radioactivity = instability.** Xenon is inert: the stable full-stack surface. Radon is radioactive: xenon's surface plus experimental, raw, volatile APIs.

| Name | Element | Is |
|------|---------|----|
| — | — | the engine binary: no libraries, substrate rather than a dialect |
| `he` | helium | light, fast boot, interactive; no tower — the **default** |
| `xe` | xenon | full numeric tower, regular expressions, `Dict` and `Set`, compiler; stable |
| `rn` | radon | xenon's surface plus experimental/raw APIs; explicitly volatile |

**The rule dialects follow: they may differ in what surface is *loaded*; they must never differ in what a shared spelling *means*.** A `+` that means pointer arithmetic in one dialect, or a `+` that coerces `"123"` to a number, is not a dialect — it is a different language wearing the same clothes (that would be a *lang*, below). If radon ever grows ergonomic address math, it gets a distinct spelling (the `Ptr` class), not an overload.

The interpreter core has no knowledge of any dialect. A dialect is library source the wrapper feeds the engine ahead of user input. The shell wrapper (`x.sh`, installed as `x`) selects a dialect with the `-l` flag:

```sh
sh x.sh                  # helium (default)
sh x.sh -l xe            # xenon
sh x.sh -l rn            # radon
```

In an **installed** tree (`make install`) the wrapper boots the same dialects
from `share/x/boot/` — one generated, amalgamated entry per dialect (the raw
include chain flattened to a single stream) — and
the library under `share/x/lib/` is byte-identical to the repo's. Repo
checkouts always load the live entries above.

`lib/x.x` is a pointer, not a dialect: it is what a bare `sh x.sh` boots, and it points at helium. The default is the light one because xenon's boot loads the compiler and the numeric tower and compiles the reader's analysers, which a session that needs none of them should not pay for. An unknown `-l` name fails with the wrapper's inventory listing, which names the real entries.

---

### helium (`lib/he.x`)

The light dialect. Loads `lib/x-core.x`, which bootstraps the module system and loads 40+ modules:

- **Boot:** operatives, data constructors, string primitives, module system (`provide`/`import`)
- **Core:** predicates, control flow, GC, type system, conversions, booleans, higher-order functions, logic, list operations (60+ functions), math, syntax forms (`cond`, `case`, `when`, `unless`, `letrec`), association lists, arithmetic, quasiquote, REPL, banner
- **System:** intrinsics, token system, numeric tower helpers
- **Types:** characters, strings, vectors, promises
- **POSIX wrappers** (`x/sys/posix.x`) — fork, exec, pipe, dup2, wait, open, close, read, write, chdir, getenv, setenv via FFI

Helium provides everything needed for general-purpose programming: combinators, list processing, sorting, pattern matching, strings, vectors, lazy evaluation, and an interactive REPL. It has no numeric tower beyond built-in integers.

---

### xenon (`lib/xe.x`)

Stable full-stack dialect. Includes all of helium's surface, then adds:

- **Dict** and **Set** (`x/type/dict.x`, `x/type/set.x`) — content-hashed mutable containers (symbol, string, integer, and char keys), loaded by default in both tower dialects
- **Assembler** (`x/tool/asm.x`) — emits machine code in process on ARM64, x86-64 and 32-bit ARM
- **Compiler** (`x/tool/compile.x`) — `compile-asm` lowers x-lang functions to native code through the assembler, with no host toolchain. `compile` is the C-emitting lane: it invokes a host `cc` at runtime and `dlopen`s the result, and needs a C toolchain on the machine running it.

Then loads the numeric tower with immediate analyser compilation (the shared
block `lib/x/boot/tower-compiled.x`, included by every full-tower
composition — `x-base.x` and the xenon/radon bodies):

1. **Bigint** (`x/num/bigint.x`) — Arbitrary-precision integers. Analysers for bigint and int-capped types are compiled to native code immediately after loading.
2. **Regex** (`x/type/regex.x`) — Regular expressions with `#/pattern/` literal syntax. Uses a C-level analyser, no compilation needed.
3. **Float** (`x/num/float.x`) — IEEE 754 floating-point. Analyser compiled after loading.
4. **Rational** (`x/num/rational.x`) — Exact rationals. Analyser compiled after loading.
5. **Complex** (`x/num/complex.x`) — Complex numbers with rectangular and polar forms. Analyser compiled after loading.
6. **Decimal** (`x/num/decimal.x`) — Arbitrary-precision decimal floating-point, literal suffix `d` (`1.5d`). Analyser compiled after loading. Last on purpose: its conversions declare float, rational and complex, and its analyser only claims a digit run that ends in `d`, so it never contests a token the earlier readers want.

The analyser compilation pattern is the key design choice: each numeric type's tokenizer analyser is compiled to native code right after the type loads, so subsequent source files (including later numeric types) are parsed through fast compiled analysers rather than interpreted ones.

Xenon does NOT include raw syscall access, file I/O, or socket constants.

---

### radon (`lib/rn.x`)

Experimental/hacking dialect. Everything in xenon, plus:

- **Syscall tables** (`x/platform/syscall.x`) — Symbolic syscall number lookup for x86_64 and i386/BSD (loaded via the POSIX layer)
- **File I/O** (`x/sys/file.x`) — File operations via POSIX syscalls with symbolic mode flags. **Opt-in** (#36): `(import x/sys/file)`
- **Socket constants** (`x/platform/socket.x`) — Linux socketcall, protocol families, socket types. **Opt-in** (#36): `(import x/platform/socket)`
- **Character constants** — `#newline`/`#nl`, `#cr`, `#esc`, `#0`, `#crnl`
- **I/O constants** — `stdin` (0), `stdout` (1), `stderr` (2), `current-input-handle`, `current-output-handle`, `current-error-handle`
- **Car/cdr compositions** — 28 composed accessors from `caar` through `cddddr`
- **`system`** — Execute a shell command via fork/execve
- **`do-loop`** — Scheme-style iteration form

Radon is the right choice for systems programming, kernel hacking, or any task that needs direct access to the operating system. It is chemically honest: heavy AND radioactive — full-featured and explicitly unstable. APIs here may change or vanish between releases.

---

### Langs

Langs are loaded as additional libraries on top of a dialect, aliasing x-lang primitives and adding derived forms to emulate another language's syntax. This is where same-spelling-different-meaning belongs: a lang may claim any spelling it likes, because it announces itself as a different language.

Each lang is a sibling project, installed as a pinned bundle and selected with the same `-l` flag:

```sh
x --install-lang https://github.com/jonruttan/x-r5rs/releases/latest/download/lang.pin.xon
x -l r5rs
```

A lang declares the dialect it loads over in its own `lang.xon`. The [README](../README.md#languages-on-top) lists the langs; [The Lang Contract](lang-contract.md) is the terms one is held to.

The interpreter core has no knowledge of any lang. All lang semantics are implemented in x-lang library code.
