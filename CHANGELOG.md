# Changelog

All notable changes to this project will be documented in this file.
This project adheres to [Semantic Versioning](http://semver.org/).

## [0.2.0] - 2026-04-04

### Added

- **Module system** — `provide`/`import` with include-once deduplication and module registry; `(modules)` discovery command
- **JIT compiler** — Data-driven assembler (x86_64, ARM64) with mmap execution; compiles x-lang functions to native code
- **Numeric tower** — Arbitrary-precision integers (bignum), IEEE 754 floats via FFI, exact rationals, complex numbers with automatic promotion
- **Regex type** — Custom type with `#/pattern/` literal syntax and compiled pattern matcher
- **POSIX wrappers** — fork, exec, pipe, dup2, wait, open, close, read, write, chdir, getenv, setenv via FFI
- **Hash tables** — FNV-1a hash function for strings
- **Dialect system** — x-lang (core), x/and (stable full-stack), x/or (experimental)
- **Self-hosted tools** — Linter, formatter, coverage analyzer, profiler, documentation generator
- **Documentation system** — `(doc ...)` forms with `(param ...)`, `(returns ...)`, `(note ...)` metadata; auto-generated Markdown reference
- **Doxygen integration** — Comprehensive C API documentation with HTML and man pages
- **Language specification** — Normative spec (`docs/spec.md`) mapping 1:1 to 1229 test cases
- **Compiled analysers** — Tokenizer analysers compiled to native code for fast parsing of numeric types
- **Vector literals** — `#()` reader syntax
- **Promise type** — Lazy evaluation with delay/force
- **Self-parameter recursion** — Functions receive self-reference as first parameter for anonymous recursion

### Changed

- **Nil is NULL** — Migrated from `p_base`-as-nil to `nil = NULL`; `()` parses to NULL
- **Library reorganization** — Split monolithic `lib/x.x` into 50+ modular files under `lib/x/`
- **Boot sequence** — Self-bootstrapping boot modules (`operatives`, `data`, `string`, `module`)
- **Naming overhaul** — `cons`/`car`/`cdr` renamed to `pair`/`first`/`rest` throughout; `string-*` renamed to `str-*`
- **Primitive migration** — 24 C primitives moved to x-lang implementations

## [0.1.0] - Initial

### Added

- Atom/pair bootstrap with union-based object model (x-expr submodule)
- Adaptive type system with runtime type definitions
- Fexpr-based evaluation: `fn` (applicative), `op` (operative), `wrap`/`unwrap`
- Standard library with combinators, list operations, sorting, strings, vectors
- Tail-call optimization via trampoline
- Error handling with `guard`
- Quasiquote with unquote and splicing
- S-expression tokenizer with type-dispatched readers
- BST-backed environment for O(log n) symbol lookup
- C89 portable, no external dependencies
