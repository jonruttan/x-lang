# Changelog

All notable changes to this project will be documented in this file.
This project adheres to [Semantic Versioning](http://semver.org/).

## [Unreleased]

### Added

- **GC hook/root registration API** — `heap-mark-hook!`, `heap-free-hook!`, `heap-mark-root!` primitives wired through to x-expr's heap-group extensible lists; `lib/x/sys/gc.x` is now a thin re-export layer
- **Optional build modules under `opt/`** — first occupant is `opt/x-prim/signal.c`; gated by `X_SIGNAL` (default on), `make X_SIGNAL=` drops the module and compiles the eval poll out
- **`examples/logo/ch1.logo`** — Chapter-1 programs from *Turtle Geometry* (ARCR/ARCL, RAY, POLY/NEWPOLY, POLYSPI/POLYSPII, INSPI)
- **x-spec coverage for GC hook & root API** — `tests/x/specs/applicative/04-gc-hooks.spec.md` (STRESS-only)

### Changed

- **Renamed `x_base_*` → `x_interp_*`** across the interpreter source tree; the file formerly at `src/x-base.c` is now `src/x-interp.c`. `x_base_*` names are reserved for x-expr's library-level skeleton (file descriptors, hooks, heap-group); `x_interp_*` covers the environment/control/extras half this project fills in.
- **GC hook & root lists moved from x-interp's `extras` group into x-expr's `heap-group`** — one canonical storage location for everything GC, registered by name via `x_heap_{mark,free}_hook_add()` / `x_heap_mark_root_add()` instead of raw `(rest (rest …))` path-walking from x-lang
- **Lazy doc metadata processing** — `(doc …)` forms stash raw metadata at load time; the full processor runs only on first `(help)`/`(apropos)`/`(modules)` invocation (~1s startup savings)
- **Syscall name tables compacted** — x86_64 (267 entries) and i386 (256 entries) shifted from `(list (lit name) ;N …)` to `(lit (name name …))`; ~1000 lines lighter, same in-memory shape
- **`lib/x-and` / `lib/x-or` module-loading layer tightened** — drop duplicate posix re-imports (x-core already loads it); pre-compile quasi/unquote reader analysers in x-or so subsequent file parses aren't ~20% slower; make x/or's system extensions (syscall/file/socket) opt-in to save ~660 lines per startup

### Fixed

- **Op lexical scope** — operative bodies now capture the environment at `(op …)` definition time, not the caller's environment at call time. Co-issue: a C-spec for `procedure_call` / `operative_call` was updated to match.
- **BST insert mutates in place** — `x_alist_bst_insert` no longer path-copies, so fn closures that captured a BST snapshot at definition time stay valid as later globals are added. This was the root cause of an intermittent turtle test failure (`>=` unbound during `include-once` of `float.x`).
- **`syscall-id` self-parameter** — was declared `(fn (call) …)` which left the actual argument slot empty; one-arg call sites were working by accident. Now `(fn (_ call) …)` per x-lang `fn` convention.
- **Heap-hook registration** (in x-expr submodule) — `x_heap_*_hook_add` and `x_heap_mark_root_add` were replacing the whole stack-cell slot instead of pushing into its current list. After one registration, the slot was a one-deep cons cell whose first IS the hook, and the collector walk crashed on the first non-pair internal field. Fixed to push into `first(cell)`.
- **`(heap-collect)` is now atomic** — the env/ctrl/extras base-tree cells and eval-list scratch cells are allocated `X_OBJ_FLAG_NONE`, so they survive a sweep only by being marked. The old `heap-collect = (applicative heap-mark heap-sweep)` let `x_eval_body` push a fresh eval-list cell *between* the mark and the sweep; that cell was allocated after the mark (so nothing marked it — conservative C-stack scanning is part of the mark and had already run), got freed mid-traversal, and the next pop dereferenced freed memory (any `(heap-collect)` invoked from inside a `begin`/`do`/op body — including the spec runner's per-test wrapping — could SIGSEGV). `heap-collect` is now a single C primitive doing mark+sweep with no allocation between; its mark marks its own in-flight frame. The raw `(heap-mark)`/`(heap-sweep)` remain exposed but are low-level. GC hooks are now driven through the TCO trampoline so a value-returning hook body doesn't leave a half-finished call for the sweep to free.

### Submodule

- **ext/x-expr** bumped twice (3083f8a → 53e74f5 → 31b29bc) to pick up: comprehensive Doxygen documentation, `x_obj_push_field`/`x_obj_pop_field` exports + OOM-via-`x_obj_error` in `x_obj_alloc`, static-library build (`make lib`) + `make install`/`uninstall` + `make doc`, README rewrite with quick-start + API table + examples/hello.c, GitHub issue/PR templates, contributing guide, and the per-pass GC hook/root list fields plus their registration helpers and the push-into-first fix above.

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
