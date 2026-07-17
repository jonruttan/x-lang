# Computational Expressions in C

## Dialects

A dialect is a composition of x-lang library modules that determines what capabilities are available. Each dialect builds on the previous, adding more features at the cost of longer startup time.

The interpreter core has no knowledge of any dialect. Dialects are loaded by shell concatenation before user input. The shell wrapper (`x.sh`) selects a dialect with the `-l` flag:

```sh
sh x.sh                  # x-lang (default)
sh x.sh -l x-and         # x/and
sh x.sh -l x-or          # x/or
```

Or directly:

```sh
cat lib/x.x - | ./x      # x-lang
cat lib/x-and.x - | ./x  # x/and
cat lib/x-or.x - | ./x   # x/or
```

---

### x-lang (`lib/x.x`)

The core dialect. Loads `lib/x-core.x`, which bootstraps the module system and loads 40+ modules:

- **Boot:** operatives, data constructors, string primitives, module system (`provide`/`import`)
- **Core:** predicates, control flow, GC, type system, conversions, booleans, higher-order functions, logic, list operations (60+ functions), math, syntax forms (`cond`, `case`, `when`, `unless`, `let*`, `letrec`), association lists, arithmetic, quasiquote, REPL, banner
- **System:** intrinsics, token system, numeric tower helpers
- **Types:** characters, strings, vectors, promises

x-lang provides everything needed for general-purpose programming: combinators, list processing, sorting, pattern matching, strings, vectors, lazy evaluation, and an interactive REPL. It has no numeric tower beyond built-in integers, no POSIX access, and no file I/O.

---

### x/and (`lib/x-and.x`)

Stable full-stack dialect. Includes all of x-lang, then adds:

- **POSIX wrappers** (`x/sys/posix.x`) — fork, exec, pipe, dup2, wait, open, close, read, write, chdir, getenv, setenv via FFI
- **Hash tables** (`x/core/hash.x`) — FNV-1a hash function for strings
- **JIT compiler** (`x/tool/compile.x`) — Compiles x-lang functions to native machine code via the data-driven assembler

Then loads the numeric tower with immediate analyser compilation (the shared
block `lib/x/boot/tower-compiled.x`, included by all three full-stack
entries — x-base.x, x-and.x, x-or.x):

1. **Bignum** (`x/num/bignum.x`) — Arbitrary-precision integers. Analysers for bignum and int-capped types are compiled to native code immediately after loading.
2. **Regex** (`x/type/regex.x`) — Regular expressions with `#/pattern/` literal syntax. Uses a C-level analyser, no compilation needed.
3. **Float** (`x/num/float.x`) — IEEE 754 floating-point. Analyser compiled after loading.
4. **Rational** (`x/num/rational.x`) — Exact rationals. Analyser compiled after loading.
5. **Complex** (`x/num/complex.x`) — Complex numbers with rectangular and polar forms. Analyser compiled after loading.

The analyser compilation pattern is the key design choice: each numeric type's tokenizer analyser is compiled to native code right after the type loads, so subsequent source files (including later numeric types) are parsed through fast compiled analysers rather than interpreted ones.

x/and does NOT include raw syscall access, file I/O, or socket constants.

---

### x/or (`lib/x-or.x`)

Experimental/hacking dialect. Everything in x/and, plus:

- **Syscall tables** (`x/platform/syscall.x`) — Symbolic syscall number lookup for x86_64 and i386/BSD
- **File I/O** (`x/sys/file.x`) — File operations via POSIX syscalls with symbolic mode flags
- **Socket constants** (`x/platform/socket.x`) — Linux socketcall, protocol families, socket types
- **Character constants** — `#newline`/`#nl`, `#cr`, `#esc`, `#0`, `#crnl`
- **I/O constants** — `stdin` (0), `stdout` (1), `stderr` (2), `current-input-handle`, `current-output-handle`, `current-error-handle`
- **Car/cdr compositions** — 28 composed accessors from `caar` through `cddddr`
- **`system`** — Execute a shell command via fork/execve
- **`do-loop`** — Scheme-style iteration form

x/or is the right choice for systems programming, kernel hacking, or any task that needs direct access to the operating system.

---

### Language Personalities

Language personalities are loaded as additional libraries on top of a dialect, aliasing x-lang primitives and adding derived forms to emulate another language's syntax:

| Personality | Base Dialect | Description |
|-------------|-------------|-------------|
| R5RS Scheme | x-lang | `lambda`, `cons`/`car`/`cdr`, `define`, `cond`, `case` |
| R7RS Scheme | R5RS | `do`, `case-lambda`, `delay`/`force`, `values`, `define-record-type` |
| Kernel | x-lang | `$vau` (operative-first), `$define!`, `$lambda` via `wrap` |
| ASH Shell | x-lang | POSIX shell syntax: pipes, redirections, if/while/for/case |
| Sweet Expressions | x-lang | SRFI-105/110: curly-infix + indentation-sensitive syntax |

Personalities are maintained as sibling projects and load by concatenation on
top of a dialect:

```sh
cat lib/x.x path/to/r5rs.x - | ./x
```

The interpreter core has no knowledge of any personality. All personality semantics are implemented in x-lang library code.
