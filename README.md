# Computational Expressions in C

```
    ., .,
    {O,O}
    (   )
     " "
```

A minimal, type-agnostic expression interpreter written in C89. The core provides atom/pair primitives, an adaptive type system, and fexpr-based evaluation. Everything else — including the standard library, language semantics, numeric tower, JIT compiler, and safety — is built on top.

## Architecture

The system is layered. Each layer expands capabilities without modifying those below it.

1. **Atom/pair bootstrap** ([x-expr](ext/x-expr/)) — Two intrinsic structural types sufficient for evaluation and data construction. The evaluator dispatches through type methods, so these two suffice to get the system running.
2. **Adaptive type system** — Runtime type definitions with dispatch methods (call, eval, write, length, etc.). Types and the base object share the same nested-list contract structure, extensible by appending pairs.
3. **Modular library** (`lib/`) — 50+ modules organized by domain: core operations, custom types (vectors, strings, promises), a numeric tower (bignum, float, rational, complex), system interfaces (POSIX, FFI, GC), self-hosted tools (linter, formatter, coverage, profiler, doc generator), and platform-specific code (x86_64, ARM64).
4. **FFI and native code** — Dynamic library loading via `dlopen`/`dlsym`, typed foreign calls, raw pointer operations, and a JIT compiler that compiles x-lang functions to native machine code via a data-driven assembler.

See [docs/](docs/) for complete reference documentation.

## Dialects

The library is composed into dialects that control what capabilities are loaded:

- **x-lang** (`lib/x.x`) — Core language. Bootstraps 25 modules providing combinators, list operations, sorting, strings, vectors, promises, quasiquote, and a REPL. No numeric tower or POSIX access.
- **x/and** (`lib/x-and.x`) — Stable full-stack dialect. Adds POSIX, hash tables, the JIT compiler, and a numeric tower (bignum, float, rational, complex) with compiled tokenizer analysers for fast parsing.
- **x/or** (`lib/x-or.x`) — Experimental dialect. Everything in x/and plus raw syscall tables, file I/O, sockets, character constants, and I/O handle constants.

Dialects are selected via the `-l` flag on the shell wrapper. Language personalities (R5RS Scheme, R7RS Scheme, Kernel, ASH shell, sweet expressions) are loaded as additional libraries on top of a dialect.

## Build

```sh
make clean && make
```

Requires a C89-compatible compiler. Produces the `x` binary.

## Run

The interpreter reads from stdin. Libraries are loaded by concatenation:

```sh
# Shell wrapper (recommended)
sh x.sh                     # x-lang with standard library + REPL
sh x.sh -l x-and            # x/and: full-stack with numeric tower
sh x.sh -l x-or             # x/or: experimental + file I/O

# Direct invocation
cat lib/x.x - | ./x         # x-lang with standard library
cat lib/x-and.x - | ./x     # x/and dialect
cat lib/x-or.x - | ./x      # x/or dialect

# Evaluate a file
cat lib/x.x program.x | ./x
sh x.sh -f program.x
```

The `-` in `cat ... - | ./x` connects stdin for interactive use after library loading.

## Test

```sh
make test-x                          # x-lang tests (1229 cases)
make test-c                          # C unit tests
make test                            # all tests
```

Test specs are markdown files in `tests/x/specs/` organized by category: core language, closures and applicatives, extensions (types, numeric tower, compile), standard library, end-to-end, and tools.

## Features

- **Fexpr foundation** — All primitives receive unevaluated arguments. `fn` provides applicative semantics; `op` creates user-level fexprs with access to the caller's environment.
- **Adaptive type system** — Define new types at runtime with `make-type`. Each type carries dispatch methods for call, eval, write, read, convert, and more.
- **Object system** — Classes are callable objects with message-passing dispatch (no quoting), single inheritance and `super`, encapsulated mutable members, and a `(static …)` block for static methods and class-wide members — so a class doubles as a namespace. All in x-lang, on `make-type`.
- **Module system** — `provide`/`import` with deduplication. Modules are auto-discovered.
- **Numeric tower** — Arbitrary-precision integers, IEEE 754 floats, exact rationals, complex numbers with automatic promotion.
- **JIT compiler** — Compiles x-lang functions to native x86_64/ARM64 machine code via a data-driven assembler with mmap execution.
- **POSIX interface** — Fork, exec, pipe, dup2, wait, open, close, read, write, chdir, getenv, setenv via FFI.
- **Regular expressions** — Custom type with `#/pattern/` literal syntax.
- **Self-hosted tools** — Linter, formatter, coverage analyzer, profiler, and documentation generator written in x-lang.
- **Tail-call optimization** — Trampoline-based TCO with environment save/restore.
- **C89 portable** — No external dependencies, compiles with gcc, clang, tcc, c89, c99.

## Documentation

### Guides

- [Architecture](docs/architecture.md) — System design, evaluation model, the contract pattern
- [Type System](docs/type-system.md) — Objects, types, the base, dispatch, extensibility
- [Object System](docs/object-system.md) — Classes, instances, statics, inheritance, encapsulation
- [Dialects](docs/dialects.md) — x-lang, x/and, and x/or dialect layers
- [Tutorial](docs/tutorial.md) — Getting started guide
- [Modules](docs/modules.md) — The provide/import module system

### References

- [Specification](docs/spec.md) — Normative language specification
- [Primitives](docs/primitives.md) — All C-level primitive operations
- [Standard Library](docs/standard-library.md) — Core library function reference
- [x-lang API Reference](docs/ref/x/index.md) — Auto-generated from source (`make doc-x`)
- [C API Reference](docs/ref/c/html/index.html) — Doxygen-generated (`make doc-c`)

### Tools

- [Linter](tools/README-lint.md) — AST linter for x-lang source
- [Formatter](tools/README-fmt.md) — Comment-preserving s-expression formatter
- [Coverage](tools/README-cov.md) — Library coverage analysis

## License

MIT No Attribution (MIT-0)
