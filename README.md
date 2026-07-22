# x-lang

```
    ., .,
    {O,O}
    (   )
     " "
```

[![CI](https://github.com/jonruttan/x-lang/actions/workflows/ci.yml/badge.svg)](https://github.com/jonruttan/x-lang/actions/workflows/ci.yml)

**x-lang** is a language built from computational-expression layers over a
minimal, type-agnostic interpreter core written in C89. The core provides
atom/pair primitives, an adaptive type system, and fexpr-based evaluation;
s-expressions are the deliberately simple initial syntax — the reader
itself is extensible, and whole surface languages load as personalities.
Everything above the core — the language semantics, standard library, object
system, numeric tower, JIT compiler, and the toolchain itself — is written
in x-lang.

## Status

x-lang is a research and teaching vehicle for **layered language
construction** — an investigation of how much a minimal, type-agnostic fexpr
core can bootstrap without ever being modified. The answer so far: the
semantics, standard library, object system, numeric tower, JIT compiler, and
the entire toolchain, all written in x-lang itself.

It is useful if you want to read or borrow a working design for extensible
readers, fexpr evaluation, runtime type systems, or self-hosted toolchains.
It is not a general-purpose application language, and it is not trying to
displace one.

**Maturity — v0.3.0.** The C core and the xenon dialect are covered by a
full spec suite with CI on macOS and Linux plus a hard AddressSanitizer gate.
The surface API is *not* frozen and may change between versions. The radon
dialect is explicitly experimental. x86_64 parity for the automatic
native-code compiler is in progress.

## A taste

```scheme
; Values dispatch to their class, subject-last -- and a list is callable
("hello,world" split ",")      ; -> ("hello" "world")
((list 10 20 30) 1)            ; -> 20

; Fexprs at the core: op receives its arguments unevaluated,
; plus the caller's environment as e
(def my-quote (op (x) e x))
(my-quote (+ 1 2))             ; -> the list (+ 1 2), unevaluated

; Every closure receives itself as argument 0 -- recursion needs no global name
(def fact (fn (self n) (if (= n 0) 1 (* n (self (- n 1))))))
(fact 20)                      ; -> 2432902008176640000

; The xenon dialect adds a full numeric tower with automatic promotion
(+ 1/3 1/6)                    ; -> 1/2
(* 1+2i 3+4i)                  ; -> -5+10i
```

More in [examples/](examples/) — start with the
[examples guide](examples/README.md), or run one directly with
`sh x.sh -f examples/x/hello.x`.

## A larger demonstration: Logo

[`apps/logo/`](apps/logo/) is a Logo interpreter written in x-lang — its own
tokenizer types, an infix expression parser, an HTTP server, and a live
animated turtle in the browser, in ~2,400 lines. It is the worked proof that
whole surface languages load on top of a dialect rather than being bolted into
the core.

```sh
sh x.sh -l logo             # REPL + viewer at http://localhost:8080
```

See [`apps/logo/README.md`](apps/logo/README.md) for the command reference.

## Features

- **Fexpr foundation** — All primitives receive unevaluated arguments. `fn` provides applicative semantics; `op` creates user-level fexprs with access to the caller's environment.
- **Adaptive type system** — Define new types at runtime with `make-type`. Each type carries dispatch methods for call, eval, write, read, convert, and more.
- **Object system** — Classes are callable objects with message-passing dispatch (no quoting), single inheritance and `super`, encapsulated mutable members, and a `(static …)` block for static methods and class-wide members — so a class doubles as a namespace. All in x-lang, on `make-type`.
- **Module system** — `provide`/`import` with deduplication. Modules are auto-discovered.
- **Numeric tower** — Arbitrary-precision integers, IEEE 754 floats, exact rationals, complex numbers with automatic promotion.
- **JIT compiler** — A data-driven assembler assembles, maps, and executes native machine code on both ARM64 and x86_64 (arch-tagged specs execute on each in CI). The automatic x-lang-function-to-native compiler currently targets ARM64.
- **POSIX interface** — Fork, exec, pipe, dup2, wait, open, close, read, write, chdir, getenv, setenv via FFI.
- **Regular expressions** — Custom type with `#/pattern/` literal syntax.
- **Self-hosted tools** — Linter, formatter, coverage analyzer, profiler, and documentation generator written in x-lang.
- **Tail-call optimization** — Trampoline-based TCO with environment save/restore.
- **C89 portable** — No third-party dependencies: the expression engine links only `libc`; the full binary adds `-ldl` for the FFI/JIT layer (float math dlopens `libm` at runtime rather than linking it). CI builds with gcc and clang on macOS and Linux; any C89-compatible compiler should work.

## Architecture

The system is layered. Each layer expands capabilities without modifying those below it.

1. **Atom/pair bootstrap** ([x-expr](ext/x-expr/)) — One storage shape, two blessed lengths: every object is a fixed-size vector of slots, and the two smallest — the atom (one) and the pair (two) — are sufficient for evaluation and data construction. The evaluator dispatches through type methods, so these two suffice to get the system running.
2. **Adaptive type system** — Runtime type definitions with dispatch methods (call, eval, write, length, etc.). Types and the base object share the same nested-list contract structure, extensible by appending pairs.
3. **Modular library** (`lib/`) — ~100 modules organized by domain: core operations, custom types (vectors, strings, promises), a numeric tower (bignum, float, rational, complex), system interfaces (POSIX, FFI, GC), self-hosted tools (linter, formatter, coverage, profiler, doc generator), and platform-specific code (x86_64, ARM64).
4. **FFI and native code** — Dynamic library loading via `dlopen`/`dlsym`, typed foreign calls, raw pointer operations, and a JIT compiler that compiles x-lang functions to native machine code via a data-driven assembler.

See [docs/](docs/) for complete reference documentation.

## Dialects

The library is composed into dialects that control what capabilities are loaded:

- **helium** (`lib/he.x`) — The light dialect and the default (`lib/x.x` points to it). Bootstraps 40+ modules providing combinators, list operations, sorting, strings, vectors, promises, quasiquote, and a REPL. No numeric tower.
- **xenon** (`lib/xe.x`) — Stable full-stack dialect. Adds POSIX, hash tables, the JIT compiler, and a numeric tower (bignum, float, rational, complex) with compiled tokenizer analysers for fast parsing.
- **radon** (`lib/rn.x`) — Experimental dialect. Everything in xenon plus the raw syscall surface, character constants, and I/O handle constants; file I/O and sockets load on demand (`(import x/sys/file)`, `x/platform/socket`).

Dialects are selected via the `-l` flag on the shell wrapper. Language personalities (R5RS Scheme, R7RS Scheme, Kernel, ASH shell, sweet expressions) are maintained as sibling projects and load as additional libraries on top of a dialect.

## Build

The expression engine (`ext/x-expr`) and the C test runner are git submodules
— clone recursively, or fetch them into an existing clone:

```sh
git clone --recursive https://github.com/jonruttan/x-lang.git
# or, in an existing clone:
git submodule update --init
```

Then:

```sh
make clean && make
```

Requires a C89-compatible compiler. Produces the `x` binary.

The expression engine (`ext/x-expr`) needs nothing beyond `libc`; the full
binary adds `-ldl` for the FFI/JIT layer. There is no `-lm` — float math
resolves `libm` at runtime through the FFI, the same way it resolves any
other library. One optional tool needs more: `x/tool/compile` — the
C-emitting compiler — invokes `cc` at *runtime* and `dlopen`s the result, so
it needs a host C toolchain present when it runs. Nothing else does.

## Run

The interpreter reads from stdin. Libraries are loaded by concatenation:

```sh
# Shell wrapper (recommended)
sh x.sh                     # helium (the default) + REPL
sh x.sh -l xe               # xenon: full-stack with numeric tower
sh x.sh -l rn               # radon: experimental + file I/O

# Direct invocation
cat lib/x.x - | ./x         # the default dialect (helium)
cat lib/xe.x - | ./x        # xenon dialect
cat lib/rn.x - | ./x        # radon dialect

# Evaluate a file
cat lib/x.x program.x | ./x
sh x.sh -f program.x
```

The `-` in `cat ... - | ./x` connects stdin for interactive use after library loading.

Inside a session, `(help)` shows the documentation index; `(quit)` or ctrl-d
exits. For line editing and history, wrap the session in `rlwrap`.

## Install

```sh
make install                # /usr/local by default
make install PREFIX=~/.local
```

Installs the wrapper as `bin/x` (the user-facing command), the engine
binary under `libexec/x/`, and the runtime tree under `share/x/`: the
library and apps **byte-identical** to the repo's (`diff -r` runs inside
the install as proof), plus generated amalgamated boot entries under
`share/x/boot/` — so `x`, `x -l xe`, and `x -f program.x` work from any
directory (see `docs/boot-amalgam.md`). `DESTDIR` is honoured for
staged/packaged installs. Remove with `make uninstall` (same `PREFIX`).

## Test

```sh
make test-x                          # x-lang tests (2,000+ tests)
make test-c                          # C unit tests
make test                            # all tests
```

Test specs are markdown files in `tests/x/specs/` organized by category: core language, closures and applicatives, extensions (types, numeric tower, compile), standard library, end-to-end, and tools. CI runs the full suite on macOS and Linux, plus a hard AddressSanitizer gate.

## Documentation

**Start here: [docs/index.md](docs/index.md)** — the documentation front door,
with a suggested reading order. New to the vocabulary? The
[Glossary](docs/glossary.md) defines the load-bearing terms (fexpr, operative,
dialect, the base, contract).

### Guides

- [Architecture](docs/architecture.md) — System design, evaluation model, the contract pattern
- [Type System](docs/type-system.md) — Objects, types, the base, dispatch, extensibility
- [Object System](docs/object-system.md) — Classes, instances, statics, inheritance, encapsulation
- [Dialects](docs/dialects.md) — the helium, xenon, and radon dialect layers
- [Tutorial](docs/tutorial.md) — Getting started guide
- [Modules](docs/modules.md) — The provide/import module system

### References

- [Specification](docs/spec.md) — Normative language specification
- [Glossary](docs/glossary.md) — Settled vocabulary and naming rulings
- [Syntax](docs/syntax.md) — Surface syntax rulings ([bare-core variant](docs/syntax-bare.md))
- [Primitives](docs/primitives.md) — All C-level primitive operations
- [Standard Library](docs/standard-library.md) — Core library function reference
- x-lang API Reference — generated locally, not committed: run `make doc-x`, then open `docs/ref/x/index.md`
- C API Reference — Doxygen: run `make doc-c`, then open `docs/ref/c/html/index.html`

### Tools

- [Linter](tools/README-lint.md) — AST linter for x-lang source
- [Formatter](tools/README-fmt.md) — Comment-preserving s-expression formatter
- [Coverage](tools/README-cov.md) — Library coverage analysis

## License

[MIT No Attribution (MIT-0)](LICENSE)
