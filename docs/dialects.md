# x-lang Dialects

*Part of the C implementation of x-lang: computational expressions over a minimal, type-agnostic core.*


A dialect is a composition of x-lang library modules that determines what capabilities are loaded. The dialects are named after noble gases — the theme ties to the x-expr/Xe etymology, and read correctly it is self-teaching along the two axes that actually distinguish the entries:

- **Atomic weight = library weight.** Helium is light: fast boot, no numeric tower. Xenon and radon are heavy: the full tower, POSIX, the compiler.
- **Radioactivity = instability.** Xenon is inert: the stable full-stack surface. Radon is radioactive: xenon's surface plus experimental, raw, volatile APIs.

| Name | Element | Is |
|------|---------|----|
| — | — | `./x`, the engine binary: no libraries, substrate rather than a dialect |
| `he` | helium | light, fast boot, interactive; no tower — the **default** |
| `xe` | xenon | full numeric tower, POSIX, compiler; stable |
| `rn` | radon | xenon's surface plus experimental/raw APIs; explicitly volatile |

**The rule that shapes the family: dialects may differ in what surface is *loaded*; they must never differ in what a shared spelling *means*.** A `+` that means pointer arithmetic in one dialect, or a `+` that coerces `"123"` to a number, is not a dialect — it is a different language wearing the same clothes (that would be a *personality*, below). If radon ever grows ergonomic address math, it gets a distinct spelling (the `Ptr` class), not an overload.

The interpreter core has no knowledge of any dialect. Dialects are loaded by shell concatenation before user input. The shell wrapper (`x.sh`) selects a dialect with the `-l` flag:

```sh
sh x.sh                  # helium (default)
sh x.sh -l xe            # xenon
sh x.sh -l rn            # radon
```

Or directly:

```sh
cat lib/he.x - | ./x     # helium
cat lib/xe.x - | ./x     # xenon
cat lib/rn.x - | ./x     # radon
```

`lib/x.x` is a pointer, not a dialect: it is what a bare `sh x.sh` boots, and it currently points at helium. The default stays light on purpose — xenon's boot runs eight runtime `cc` compilations (the compiled tokenizer analysers), which would make every newcomer run slow and host-toolchain-dependent. The retired spellings `-l x-and` and `-l x-or` still boot (compat shims, one release; see the CHANGELOG).

---

### helium (`lib/he.x`)

The light dialect. Loads `lib/x-core.x`, which bootstraps the module system and loads 40+ modules:

- **Boot:** operatives, data constructors, string primitives, module system (`provide`/`import`)
- **Core:** predicates, control flow, GC, type system, conversions, booleans, higher-order functions, logic, list operations (60+ functions), math, syntax forms (`cond`, `case`, `when`, `unless`, `letrec`), association lists, arithmetic, quasiquote, REPL, banner
- **System:** intrinsics, token system, numeric tower helpers
- **Types:** characters, strings, vectors, promises

Helium provides everything needed for general-purpose programming: combinators, list processing, sorting, pattern matching, strings, vectors, lazy evaluation, and an interactive REPL. It has no numeric tower beyond built-in integers, no POSIX access, and no file I/O.

---

### xenon (`lib/xe.x`)

Stable full-stack dialect. Includes all of helium's surface, then adds:

- **POSIX wrappers** (`x/sys/posix.x`) — fork, exec, pipe, dup2, wait, open, close, read, write, chdir, getenv, setenv via FFI
- **Hash tables** (`x/type/hash.x`) — FNV-1a hash function for strings
- **Compiler** (`x/tool/compile.x`) — Compiles x-lang functions by emitting C, invoking a host `cc` at runtime, and `dlopen`ing the result. Requires a C toolchain on the machine running it. (The separate data-driven *assembler* — `x/tool/asm.x`, emitting machine code directly on ARM64 and x86_64 — is not loaded by this dialect.)

Then loads the numeric tower with immediate analyser compilation (the shared
block `lib/x/boot/tower-compiled.x`, included by every full-tower
composition — `x-base.x` and the xenon/radon bodies):

1. **Bignum** (`x/num/bignum.x`) — Arbitrary-precision integers. Analysers for bignum and int-capped types are compiled to native code immediately after loading.
2. **Regex** (`x/type/regex.x`) — Regular expressions with `#/pattern/` literal syntax. Uses a C-level analyser, no compilation needed.
3. **Float** (`x/num/float.x`) — IEEE 754 floating-point. Analyser compiled after loading.
4. **Rational** (`x/num/rational.x`) — Exact rationals. Analyser compiled after loading.
5. **Complex** (`x/num/complex.x`) — Complex numbers with rectangular and polar forms. Analyser compiled after loading.

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

### Language Personalities

Language personalities are loaded as additional libraries on top of a dialect, aliasing x-lang primitives and adding derived forms to emulate another language's syntax. This is where same-spelling-different-meaning belongs: a personality may re-mean anything, because it announces itself as a different language.

| Personality | Base Dialect | Description |
|-------------|-------------|-------------|
| R5RS Scheme | helium | `lambda`, `cons`/`car`/`cdr`, `define`, `cond`, `case` |
| R7RS Scheme | R5RS | `do`, `case-lambda`, `delay`/`force`, `values`, `define-record-type` |
| Kernel | helium | `$vau` (operative-first), `$define!`, `$lambda` via `wrap` |
| ASH Shell | helium | POSIX shell syntax: pipes, redirections, if/while/for/case |
| Sweet Expressions | helium | SRFI-105/110: curly-infix + indentation-sensitive syntax |

Personalities are maintained as sibling projects and load by concatenation on
top of a dialect:

```sh
cat lib/he.x path/to/r5rs.x - | ./x
```

The interpreter core has no knowledge of any personality. All personality semantics are implemented in x-lang library code.
