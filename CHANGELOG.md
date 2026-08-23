# Changelog

All notable changes to this project will be documented in this file.
This project adheres to [Semantic Versioning](http://semver.org/).

## [Unreleased]

The object model's second architecture: one routing model with four doors,
and the composition features that shape dispatch tables without changing how
routing works.

### Added

- **Traits and first-class delegation** — `def-trait` defines a behaviour bundle and `with` composes it into a class; `delegates` makes forwarding a declared relationship rather than hand-written pass-through methods.
- **Generic functions** — `def-generic` and `on` give multi-argument dispatch as the cold path beside message passing's hot one: pointwise specificity, from-lattice tie-break, and teaching errors when no method applies. `x/num/tower` is the worked example, and the tower's mixed-type policy on generics is now stated rather than implied.
- **Records** — `def-record` for lightweight named-field data types; `Tls` ported onto it as the first occupant.
- **Open classes** — `def-method!` and `def-static!` add to a class after its definition, with a `%missing` hook for selectors that resolve to nothing.
- **Two-tier privacy** — `(private …)` and `(protected …)` blocks, enforced at the dispatch door. Reflection is the documented escape hatch; a leading `%` stays what it always was, a naming convention.

### Changed

- **The C engine is a separate repository** — [x-engine-c](https://github.com/jonruttan/x-engine-c), consumed here as the `ext/x-engine-c` submodule with `ext/x-expr` nested inside it. `make` builds the engine there and copies `x-bin` to this repo's root, so the wrapper, the spec runners and every `tools/check/*.sh` script are unchanged. Clone with `--recursive`.

  The contract manifests travel **with the engine**, in its `tools/contract/`: an engine's description of itself is stronger there than as a copy the library keeps, because a private layout copy is right about *some* engine and not necessarily the one running. `lib/x-core.x` includes `base-paths.x` and `obj-layout.x` from there as the first things it loads, and `pin.x` reads `isa.x` at runtime. `check-isa`, `check-obj-layout` and `check-base-paths` are the engine's own gates now; `check-prim-coverage` stays here, because most primitives are reachable only through the library and the honest answer needs both spec suites.

  The engine is still built with this repo's `git describe` passed down as `X_RELEASE`.

- **x-lang reaches its engine through one path** — `engine`, a `.gitignore`d symlink in the repo root that `make` points at whatever the tree builds against: the submodule, a checkout named by `X_ENGINE_DIR`, or an unpacked engine release. Everything downstream uses that one spelling — the boot's contract includes, the JIT's `-I` flags, the gates, the conformance runner — so a second implementation needs no edit to `lib/`. An engine directory either has sources (built here) or ships a binary (used as-is); the build asks which rather than assuming. Once pointed somewhere explicitly the link stays there, and `make install` stamps the ISA fingerprint from the engine it actually built against, not from a hardcoded submodule path.

- **Object model v2** — message passing now runs over flat per-class dispatch tables (the hot path), with `method-of` as the sanctioned de-dispatch door; value-call subject-last is routing sugar into the same door; generic functions are the multi-argument cold path; and the C ops cell's seven spellings shim into the tower's generics, so promotion has one authority. Composition (`with`/`delegates`), contracts, records, open classes and `%missing` are table-shaping features that never change routing. Measured: a 110-entry static back-hit went 231 → ~100 µs/call, and `method-of`-hoisted calls sit at ~31 µs against a plain `fn`'s ~21.
- **Static members inherit**, with shadow-on-write, and classes are tracked in a registry.
- **Stored methods are applicative** — the stale wrap sites are gone.
- **`%this-class` box replaces the `%super-class` binding**; member and static writes go in place through `%box-put!`; the dispatch arg frame is tail-evaluated.
- **Library version 0.5.0** — `x-lib-version` had read `0.3.0` since before v0.4.0 shipped, so the banner and `x -V` under-reported the library by two releases while claiming precision. `docs/spec.md`, `docs/standard-library.md` and the README's maturity line move with it.

- **The pin records which engine a project was verified against** — a lock's
  `(engine-release …)`, compared before a pinned amalgam boots and refused on a
  mismatch (`--allow-release-skew` waives it, loudly). x-lang no longer stamps
  its own tag onto the engine it builds: `x-engine-c` has a version line of its
  own, so an installed tree now carries two facts — `contract/release` for the
  library and `contract/engine-release` for the engine — and each refusal names
  which one failed. Both rows are optional; a lock written before them announces
  that the pairing is unchecked rather than being refused.

- **The engine is acquired, not carried** — the `ext/x-engine-c` submodule is
  gone. `make engine` fetches the release `tools/engine/engine.pin.xon` names
  for your platform and verifies it against a recorded digest; `make
  engine-source` clones that release and builds it, which is what a platform
  with no published engine (the Pi, 32-bit) takes automatically and what the
  sanitizer, coverage and engine-hacking flows ask for by name. A tree that has
  never acquired one prints those options instead of failing obscurely. Cloning
  x-lang no longer needs `--recursive`, and building it no longer needs a C
  compiler.

### Fixed

- **Releases can be told apart, and a mismatched pin refuses instead of crashing** (#435) — the ISA fingerprint is the C surface, which is deliberately fixed: it is byte-identical across v0.3.1-rc10, v0.4.0 and this tree, as are the obj-layout, base-paths and base-layout contracts, so nothing anything compared could tell two releases apart. A boot amalgam from one release therefore booted against another release's **library** with the pairing guard passing, and died mid-boot on a dereferenced string. (The original report called this an amalgam/engine pairing; reproducing it with the engine held constant showed otherwise — swapping the engine changes nothing, swapping `lib/` and `apps/` decides everything, because an amalgam is self-contained only over its `include` closure and resolves its imports against the installed tree as it boots. See #467.) Three things now carry release identity: the engine reports its own tag as `x-release` (`x -V` prints it), an installed tree is stamped with that tag and with a **payload fingerprint** — one digest over everything the release ships as library — and `pin.release.xon` publishes the same payload fingerprint beside the ISA one. The wrapper compares the lock's release tag against the engine's before the amalgam reaches it, and refuses the pair, naming both tags and both remedies; `--allow-release-skew`, or `(allow-release-skew)` in the manifest, waives it loudly for anyone who means it. `(Pin verify)` reports the same comparison without enforcing it. The tag comparison works on locks written long before this change, because `Pin boot` has always recorded it.
- **`Pin sync` classifies a project's own modules and never vendors them** (#223) — and `check`'s audit half arms the project's own roots too, so a project whose sources import its own modules can finally sync and check. Previously sync copied the project's modules into its own overlay, where the stale copies shadowed the real files.
- **`Pin boot` writes the lock where the guard will find it** (#313's write side) — the boot pin's engine-pairing guard no longer silently stops firing when overlay roots are reordered.
- **A forked child dies on any failure before exec** — no more half-configured child continuing into the parent's program.

## [0.4.0] - 2026-08-20

The first release since 0.2.0: the 0.3.x development line and the 0.3.1
release candidates, shipped together. Reproducibility is the theme — a
project can now freeze the language it runs on, and a release ships the
engine to run it.

### Added (reproducibility)

- **Project pinning** — a `pin.xon` manifest (`root` overlay, `src` scan tree, `boot` entry) and the `Pin` verbs over it: `init`, `boot`, `sync`, `check`, `vendor`, `verify`, `closure`, `fetch`, `resolve`, `unused`. Two tiers, because there are two kinds of drift: an **overlay pin** freezes the library modules a project imports — vendored closure-wise, digests in a lockfile — and a **boot pin** freezes the language itself by committing a released amalgam. The lockfile records the release tag, that release's ISA fingerprint, and the amalgam's digest; the wrapper arms both pins, announces them on stderr, and refuses to boot an amalgam whose fingerprint doesn't match the running engine.
- **Versioned module lines** — `import-version-once` / `import-version` select among sibling `@`-suffixed version files by spec string (`"1.3"`, `"1.3.*"`, `"^1"`, `"*"`). Files are append-only, so a fix is a new patch file and every import whose spec admits it picks the fix up on its next run; dedup keys the base name, and a loaded version that doesn't satisfy a later spec is a loud error naming both sides. `Pin resolve` is the dry run, `Pin unused` the safe-removal answer (#214, #215, #216).
- **Release engineering** — every tag now publishes per-platform prebuilt binary tarballs (Developer ID signed and notarized on macOS) beside the dialect amalgams, each with a coreutils-checkable `.sha256` sidecar, so a release runs with no toolchain and no compile. `bootstrap.sh` covers the from-source path in one command: clone with submodules, build the C89 engine, and optionally install under a user prefix.

### Added (networking and codecs)

- **A networking tier** — a plain HTTP/1.1 client over `Socket` (#374), then the REST tier on top: https via libssl FFI, DNS, the verbs, and `Rest` (#412), with basic auth, bearer-token auth, and auto-followed redirects.
- **Codecs** — zlib through the dlopen FFI (#373), CSV (#372), binary struct pack/unpack with `File stat`/`lstat` adopting it (#371), and base64 and hex (#362).

### Added (standard library and reader)

- **`$"…"` string interpolation** — holes hold code, and the literal scans as one token instead of shattering into fragments (#292); the quote family's char codes become char literals. Adopted across the library wherever an output call was a text template (#291).
- **Library growth** — `Path` (#225), a `Proc` tier over `Sys` with one correct spawn shape (#226), `File read-all`/`write-all`, and the coverage tail: `Pq`, `Deque`, `Counter`, `Random uuid`, `Str8 wrap`/`fill` (#375), `from-iso`, UDP and unix sockets, `Proc` options, `walk`, `glob`, `relpath`, `copy`, `temp` (#364).
- **Consolidation** — canonical membership/assoc/find helpers replacing 32 private copies (#227), one shared xon codec with a single reader door (#230), and one dirent decoder replacing a drifted pair (#228).


### Changed (dialect names — #95)

- **Noble-gas dialect names** — the dialects are now **helium** (`lib/he.x`, light/default — the old `lib/x.x` surface, byte for byte), **xenon** (`lib/xe.x`, stable full tower — the old `x-and`), and **radon** (`lib/rn.x`, experimental — the old `x-or`). Atomic weight = library weight, radioactivity = instability; and the governing rule: dialects may differ in what surface is loaded, never in what a shared spelling means. `x-lang` reverts to being the language's name only; banners show the full element word (`xenon v0.3.0 on x-lang`); `-l` flags stay terse (`-l xe`). The module layer follows: `x/and` → `x/xe`, `x/or` → `x/rn`.
- **Old spellings retired** — `-l x-and` / `-l x-or` and `(import x/and)` / `(import x/or)` no longer resolve (transitional shims existed only within this release cycle); an unknown `-l` name fails with the wrapper's inventory listing. `lib/x.x` remains as the default pointer (bare `sh x.sh` boots helium), and `check-doc-vocab` now ratchets the retired spellings out of `lib/`.
- **Dialect bodies** — each dialect's composition lives in `lib/x/boot/{helium,xenon,radon}.x`; each entry is a body-include plus the top-level launcher (a `(repl)` cannot ride a nested `include`: it would read the included file's EOF instead of the session's stdin).
- **Examples reorganized** — `examples/and/` → `examples/xe/`, `examples/or/` → `examples/rn/`.
- **Library version 0.3.0.**

### Added

- **x86_64 assembler parity** (`lib/x/platform/x86_64.x`) — `cmp` (rr/ri), the six conditional branches (`b/eq b/ne b/lt b/ge b/gt b/le` as Jcc rel32, sharing arm64's mnemonic names), a `b` alias for `jmp`, and per-arch `asm-prologue!`/`asm-epilogue!` (SysV frame + rbx/r12-r14) and `asm-load-imm64!`. The JIT codegen module (`asm-compile.x`) remains arm64-only (registers hard-wired) — tracked separately.
- **Arch-tagged specs** — the spec runner skips `<name>.<arch>.spec.md` files on non-matching hosts (`uname -m`, arm64/aarch64 and x86_64/amd64 normalized); asm specs split into `.arm64.`/`.x86_64.` variants since the scenarios are ABI-specific (A64's x0 arg-and-return duality vs SysV's rdi-in/rax-out)

- **GC hook/root registration API** — `heap-mark-hook!`, `heap-free-hook!`, `heap-mark-root!` primitives wired through to x-expr's heap-group extensible lists; `lib/x/sys/gc.x` is now a thin re-export layer
- **Optional build modules under `opt/`** — first occupant is `opt/x-prim/signal.c`; gated by `X_SIGNAL` (default on), `make X_SIGNAL=` drops the module and compiles the eval poll out
- **`examples/logo/ch1.logo`** — Chapter-1 programs from *Turtle Geometry* (ARCR/ARCL, RAY, POLY/NEWPOLY, POLYSPI/POLYSPII, INSPI)
- **x-spec coverage for GC hook & root API** — `tests/x/specs/applicative/gc-hooks.spec.md` (STRESS-only)
- **Object-oriented class system** (`lib/x/type/class.x`) — classes are themselves callable `%class` objects; instances are `%object`. Message-passing dispatch with literal selectors (`(obj name args)`, no quotes — the `call` handler is an operative), single inheritance with `super`, and a `(static …)` block of static methods + class-wide members so a class doubles as a namespace (`(Class name)`, `(Class new …)`). Members are declared directly in the class body (no wrapper) with a uniform form — `name` | `(name default)` | `(name default "desc")` — identical in the static block; instance members gain optional default values. Access is encapsulated (external reads/writes only via dispatch; method-internal `(member 'm)`/`(set-member! 'm v)` for the private-data pattern). `(help Class)` lists members and methods grouped static-vs-instance, merged across the inheritance chain and sorted by name. Spec: `tests/x/specs/ext/object.spec.md`; guide: `docs/object-system.md`
- **Quote reader** (`lib/x/type/lit-reader.x`) — `'expr` is reader shorthand for `(lit expr)` (`'sym`, `'(a b)`, `''x`, and `'` as a terminating macro char). The analyser is JIT-compiled in x/and and x/or so it doesn't slow tokenizing. Spec: `tests/x/specs/core/quote-reader.spec.md`

### Changed

- **Renames across the surface** — `Bignum` → `Bigint` (#356), `Token` → `Analyser` and `StrUTF8` → `StrUtf8` (#359), the cross-class verbs unified (#358), and the R7RS method names retired (#357). Pre-1.0 surface churn, done in one pass rather than a drip.
- **A bare `make` no longer mutates the binary** — the strip is stamp-gated (#367), and per-variant object suffixes retired the `clean-obj` brackets (#329).
- **Renamed `x_base_*` → `x_interp_*`** across the interpreter source tree; the file formerly at `src/x-base.c` is now `src/x-interp.c`. `x_base_*` names are reserved for x-expr's library-level skeleton (file descriptors, hooks, heap-group); `x_interp_*` covers the environment/control/extras half this project fills in.
- **GC hook & root lists moved from x-interp's `extras` group into x-expr's `heap-group`** — one canonical storage location for everything GC, registered by name via `x_heap_{mark,free}_hook_add()` / `x_heap_mark_root_add()` instead of raw `(rest (rest …))` path-walking from x-lang
- **Lazy doc metadata processing** — `(doc …)` forms stash raw metadata at load time; the full processor runs only on first `(help)`/`(apropos)`/`(modules)` invocation (~1s startup savings)
- **Syscall name tables compacted** — x86_64 (267 entries) and i386 (256 entries) shifted from `(list (lit name) ;N …)` to `(lit (name name …))`; ~1000 lines lighter, same in-memory shape
- **`lib/x-and` / `lib/x-or` module-loading layer tightened** — drop duplicate posix re-imports (x-core already loads it); pre-compile quasi/unquote reader analysers in x-or so subsequent file parses aren't ~20% slower; make x/or's system extensions (syscall/file/socket) opt-in to save ~660 lines per startup

### Changed (CI)

- **`make test-asan` promoted to a hard CI gate** — the AddressSanitizer baseline reached zero (112 findings at the gate's introduction → 0): the under-read fixes below plus pinned `ASAN_OPTIONS` (`detect_stack_use_after_return=0`; stack-copying call/cc is fundamentally incompatible with ASan's fake stack, as with any fiber library). A red ASan job is now a real memory-safety regression.

### Performance

- **sha256 gains a JIT** — verifying a released amalgam went from minutes (and a ~2 GB peak) to seconds. The JIT reads bytes directly, the last interpreted tenth of the digest compiles away, the `H` shuffles fold into the compiled loop, and the build is gated on payload size so a small artifact still verifies in pure x (#123, #324).
- **x86-64 JIT parity** — the backend reaches parity with arm64 and the JIT spec suite stops being arm64-only.
- **Hot-path sweep** — the pin closure walk drops its quadratic copies and per-node dispatch (#340), `List` family walks become iterative inner loops with one normalization (#336), the regex matcher stops rebuilding group splices (#337), bigint division carries an MSB view instead of re-reversing per digit (#341), `and`/`or` become nested `if` in per-element loops (#343), int-only sites fetch cached int prims (#335), and the doc, fmt, cov and lint walks shed per-node work (#338, #339, #342, #344).
- **Doc sweeps batch** — ~5 engine boots instead of ~98, and the `**` glob hole closed (#321, #322).

### Fixed

- **The pin lifecycle is verified-or-nothing** — loud on every bad input, at every verb (#145, #421).
- **Negative float literals** — the float analyser only entered on a digit, so `-7.5` was never claimed by the float type and fragmented into `-7`, a stray `.`, and `5`. A `-` entry state (requiring a digit next, so the minus operator stays a symbol) fixes it; pure x-lang, no C.
- **Dotted bodies error instead of crashing** — `(do 7 . 5)` / `(begin 7 . 5)` (e.g. from a malformed literal under a lib without the float type) walked the improper tail into the unchecked `rest` prim and evaluated a value word as an expression (SIGSEGV). The check lives at the x level, in `do`/`begin`'s boot walker: the C core is the processor and does not bounds-check; the walker that accepts the program does. Boot-safe via catalog-fetched type prims and per-dialect probe handles (reader cells and pair-prim cells carry different types).
- **`%` on floats returned garbage** — the float type registered `+ - * / < =` ops but not `%`, so `(% 1.2 1.4)` fell through to `x_prim_mod`'s integer fallback: value-word modulo on two float *payload pointers* (`(gcd 1.2 1.4)` famously yielded `8`). Floats now dispatch `%` to a new `d%d` FFI convention (`fmod`, matching `%`'s truncated-division semantics; `-lm` added for Linux). Rational and complex still lack `%` ops and inherit the garbage fallback — noted for the tower's next pass.
- **Lint spec batch footprint: ~5 GB → ~0.8 GB** — every one of the 31 tests raw-`include`d the whole lint tool (~150 MB of objects each, never collected: the harness doesn't GC between snippets), so the batch OOM'd any small-RAM box. macOS *appeared* fine only because memory compression hid it (peak footprint told the truth). Now loads once per batch via `# @lib ../tests/x/lib/lint.x`, matching every other tool spec. Investigation notes: object counts and sizes are identical across platforms, and jemalloc matched glibc byte-for-byte — there was no leak and no allocator pathology, just honest accounting on Linux.
- **Type-field reads on non-type tags** — six sites (`type?`, `type-name`, `units`, `length`, and the `write`/`display` hook dispatch) navigated `x_type_field_*` on whatever sat in an object's type slot. A child base's slot holds the `x_eval_obj` sentinel (a static atom tagging the raw string `"BASE"`), so e.g. `(pair? (Base make))` read 8 bytes past the tag string (ASan global-buffer-overflow) and worked only because the garbage compared unequal. All six now use `x_type_op_try`'s documented guard: only a pair-tree type has fields; sentinel-typed objects get defined fallbacks (`type?` → `#f`, atom units/length, default repr).
- **call/cc vs AddressSanitizer** — under ASan the capture size went negative (instrumented frames live on ASan's heap-side fake stack, breaking `&local` ordering against the stack base) and the segment copies tripped the `memcpy` interceptor on other frames' redzones. The capture/restore functions are now exempt (`no_sanitize_address`, which also keeps the setjmp frame in the captured segment) and copy through an uninstrumented byte loop under ASan; plain builds are unchanged (`memcpy`, empty attribute).
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
