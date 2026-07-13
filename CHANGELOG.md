# Changelog

All notable changes to this project will be documented in this file.
This project adheres to [Semantic Versioning](http://semver.org/).

## [Unreleased]

### Added

- **x86_64 assembler parity** (`lib/x/platform/x86_64.x`) — `cmp` (rr/ri), the six conditional branches (`b/eq b/ne b/lt b/ge b/gt b/le` as Jcc rel32, sharing arm64's mnemonic names), a `b` alias for `jmp`, and per-arch `asm-prologue!`/`asm-epilogue!` (SysV frame + rbx/r12-r14) and `asm-load-imm64!`. The JIT codegen module (`asm-compile.x`) remains arm64-only (registers hard-wired) — tracked separately.
- **Arch-tagged specs** — the spec runner skips `<name>.<arch>.spec.md` files on non-matching hosts (`uname -m`, arm64/aarch64 and x86_64/amd64 normalized); asm specs split into `.arm64.`/`.x86_64.` variants since the scenarios are ABI-specific (A64's x0 arg-and-return duality vs SysV's rdi-in/rax-out)

- **GC hook/root registration API** — `heap-mark-hook!`, `heap-free-hook!`, `heap-mark-root!` primitives wired through to x-expr's heap-group extensible lists; `lib/x/sys/gc.x` is now a thin re-export layer
- **Optional build modules under `opt/`** — first occupant is `opt/x-prim/signal.c`; gated by `X_SIGNAL` (default on), `make X_SIGNAL=` drops the module and compiles the eval poll out
- **`examples/logo/ch1.logo`** — Chapter-1 programs from *Turtle Geometry* (ARCR/ARCL, RAY, POLY/NEWPOLY, POLYSPI/POLYSPII, INSPI)
- **x-spec coverage for GC hook & root API** — `tests/x/specs/applicative/gc-hooks.spec.md` (STRESS-only)
- **Object-oriented class system** (`lib/x/type/object.x`) — classes are themselves callable `%class` objects; instances are `%object`. Message-passing dispatch with literal selectors (`(obj name args)`, no quotes — the `call` handler is an operative), single inheritance with `super`, and a `(static …)` block of static methods + class-wide members so a class doubles as a namespace (`(Class name)`, `(Class new …)`). Members are declared directly in the class body (no wrapper) with a uniform form — `name` | `(name default)` | `(name default "desc")` — identical in the static block; instance members gain optional default values. Access is encapsulated (external reads/writes only via dispatch; method-internal `(member 'm)`/`(set-member! 'm v)` for the private-data pattern). `(help Class)` lists members and methods grouped static-vs-instance, merged across the inheritance chain and sorted by name. Spec: `tests/x/specs/ext/object.spec.md`; guide: `docs/object-system.md`
- **Quote reader** (`lib/x/type/lit-reader.x`) — `'expr` is reader shorthand for `(lit expr)` (`'sym`, `'(a b)`, `''x`, and `'` as a terminating macro char). The analyser is JIT-compiled in x/and and x/or so it doesn't slow tokenizing. Spec: `tests/x/specs/core/quote-reader.spec.md`

### Changed

- **Renamed `x_base_*` → `x_interp_*`** across the interpreter source tree; the file formerly at `src/x-base.c` is now `src/x-interp.c`. `x_base_*` names are reserved for x-expr's library-level skeleton (file descriptors, hooks, heap-group); `x_interp_*` covers the environment/control/extras half this project fills in.
- **GC hook & root lists moved from x-interp's `extras` group into x-expr's `heap-group`** — one canonical storage location for everything GC, registered by name via `x_heap_{mark,free}_hook_add()` / `x_heap_mark_root_add()` instead of raw `(rest (rest …))` path-walking from x-lang
- **Lazy doc metadata processing** — `(doc …)` forms stash raw metadata at load time; the full processor runs only on first `(help)`/`(apropos)`/`(modules)` invocation (~1s startup savings)
- **Syscall name tables compacted** — x86_64 (267 entries) and i386 (256 entries) shifted from `(list (lit name) ;N …)` to `(lit (name name …))`; ~1000 lines lighter, same in-memory shape
- **`lib/x-and` / `lib/x-or` module-loading layer tightened** — drop duplicate posix re-imports (x-core already loads it); pre-compile quasi/unquote reader analysers in x-or so subsequent file parses aren't ~20% slower; make x/or's system extensions (syscall/file/socket) opt-in to save ~660 lines per startup

### Fixed

- **def-class heap under-read on bare members** — `%collect-methods` tested `(eq? (first (first forms)) (lit method))` without a `pair?` guard, so a bare member name (a symbol) had its name buffer dereferenced as an object — an out-of-bounds read that 64-bit malloc tolerates (garbage compares unequal, so bare members were skipped *by luck*) but ASan flags and 32-bit/Pi can segfault on. This was the tracked "eq?/match under-read" blocking `make test-asan` from hard-gating.
- **call/cc reinvocation segfault on Linux/gcc** — the stack capture's lower bound came from `&local`, missing frame slots the compiler placed below it (gcc spills `p_base`/`cont` there); clang's register allocation masked it. Capture now bounds from a non-inlinable callee frame, and the restore descent keeps a two-pad margin so the memcpy can't clobber the live restore frame.
- **A64 detection on GNU triplets** — `%asm-arm64?` matched only Darwin's "arm64" spelling, loading the x86_64 backend on aarch64 Linux
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
