# Boot amalgamation — design note

**Status: IMPLEMENTED** (designed and landed 2026-07-22). Companion to the
`make install` work: this is the design that retired install-time source
rewriting (the `BAKE` sed in the Makefile) by restructuring how dialects
boot, so the question "where is the library?" is answered once, as data,
instead of being carved into every installed file.

Deviations from the proposal below, discovered during implementation:

- **The generator is a line-oriented textual splicer** (`tools/amalgamate.sh`,
  sh+awk), not a reader-based x-lang tool sharing boot-order.x's form
  walker. Two reasons: a reader round-trip re-prints forms, losing source
  fidelity (reader sugar, escapes, formatting) — verbatim text is the only
  representation the interpreter is guaranteed to see identically; and
  splicing must land at STREAM top level, where "follow column-0 raw
  includes" is the entire traversal. The strict convention (a boot raw
  include sits alone at column 0) is machine-enforced by the generator
  itself, which errors on any other root-relative include in the closure.
  boot-order.x stays form-based and validates the same order separately.
- **x-core.x's `(do ...)` wrapper was flattened to top level.** A top-level
  form parses in full before it evaluates, so splicing file text inside the
  `do` would have parsed later boot sources before the reader machinery
  they depend on had evaluated. Top-level `do` was pure grouping (defs bind
  globally either way); hoisting is behavior-preserving and strictly
  relaxes parse timing.
- **App entries are amalgamated too** (`apps/*/run.x` → `share/x/boot/<app>.x`):
  they are self-booting entries with the same root-literal shape as
  dialects, which the proposal missed.
- **The `tools/` boot contracts are not installed at all** — base-paths.x
  and obj-layout.x exist only inlined inside the amalgams.
- **`%install-root` names the tree root without a trailing slash** (e.g.
  `/usr/local/share/x`); module.x joins `lib`, app entries join `apps`,
  both behind an unbound-guard so the repo case is untouched.

## Problem

An installed tree must load from *any* working directory. But the C
`include` primitive is a bare `x_sys_open(path)` — no search path — and
the boot chain is built from cwd-relative string literals: the entry
includes `"lib/x/boot/helium.x"`, x-core includes ~50 more `"lib/..."`
files, and `import`'s default root is the literal `"lib"`. The first
includes run before the string library or module system exist, so there
is no x-level place to fix this at load time; and the entry arrives via
a stdin pipe, so there is no including file to resolve against.

`make install` currently squares this by sed-rewriting the path literals
absolute in every installed `.x` file ("BAKE"). It works, but:

- The installed library is not byte-identical to the sources in git.
- The rewrite enumerates known literal shapes (`"lib/`, `"tools/`, two
  bare-root forms). A future literal with a new shape sails past it and
  breaks **only installed trees**, silently — repo, tests, and CI all
  keep passing. A footgun.

## Goal

**The installed `share/x/lib` is byte-identical to the repo's `lib/`.**
That invariant is total and machine-checkable (`diff -r`), unlike
pattern-matched rewriting, which can only be as good as its pattern
list. User path semantics (cwd-relative `include`, `File` I/O) are
untouched.

## Design

Four pieces, each small; the order they must land in is in Migration.

### 1. Module identity by name, not path (the prerequisite)

`%include-list-cell` (lib/x/boot/module.x) dedups loads today by
**filesystem path string**: x-core pre-seeds `"lib/x/type/str.x"` etc.
so a later `(import x/type/str)` — which resolves the name to that same
string — is a no-op. This couples module identity to the load root: the
moment an installed tree resolves imports against an absolute root, the
computed path no longer matches the relative pre-seed key, and every
boot module is one import away from a silent double load (the
type/list.x and ansi double-load class of bug). This coupling is exactly
why BAKE must rewrite pre-seed keys and includes with the same brush.

Fix: key the registry by **module name** (`x/type/str`), which is
root-independent. The pre-seed block in x-core.x lists names; `import`
checks the name before resolving any path; `include-once` keeps path
keying for its user-facing file semantics. Side benefit: the same module
reached via two different `import-path!` roots now dedups correctly —
a latent bug under path keying regardless of installation.

(Cheaper fallback, considered and rejected: keep path keys but build the
pre-seed strings with `(%path-join %root ...)` at boot. Works, but keeps
the identity/filesystem coupling and fixes nothing about multi-root
dedup. Name keying is the honest version.)

### 2. Amalgamated dialect entries (build products)

A generator — `tools/amalgamate.x`, written in x-lang — flattens each
dialect's boot chain (entry → body → x-core → boot files → tower →
dialect module) into **one self-contained file** with zero path
literals, emitted to `build/boot/<name>.x` (`x`, `he`, `xe`, `rn`).
Never committed; regenerated by make with a dependency on `lib/**.x`,
so drift between sources and amalgam is structurally impossible.

Generator rules, each load-bearing:

- **Splice at top level, never wrap.** No `(do ...)` around inlined
  files: the launcher `(repl)` must sit at *stream* top level (nested in
  any frame it reads that frame's EOF and exits — the #95 trap), and
  the spec harness's one-form-per-block rule is the same constraint.
- **Preserve effective order exactly.** The traversal that knows the
  effective boot order — following raw `include` verbatim, honouring
  pre-seeds, expanding `import` at its slot — already exists in
  `tools/boot-order.x`. Extract it into a shared module both the lint
  and the generator consume; two parallel order-walkers would drift.
  Order fidelity preserves the tower's parse-before-eval constraint and
  every boot-time reader-macro rule for free, because the interpreter
  sees the same stream it sees under live includes.
- **Emit provenance markers** (`; ---- lib/x/boot/data.x ----`) so
  error line numbers in an installed tree, which point into the
  amalgam, can be mapped back to sources by eye.

The tool runs on the live lib (bootstrap circularity is fine, as with
any self-hosted compiler), which means **live-include boot remains
supported forever** — it is dev mode and the generator's own runtime.

### 3. The root, injected as data

The wrapper already composes the interpreter's stdin (it cats entry +
files, and emits forms itself for `-V`). Installed mode adds **one
line** at the top of the pipe, before the amalgam:

    (def %install-root "<prefix>/share/x/")

`def` is a C primitive, so this needs no library — no chicken-and-egg.
`module.x` consults it where the import roots are built: root =
`%install-root` + `"lib"` when bound, else the literal `"lib"` as
today (unbound-symbol probe via `guard`, the established idiom).
`apps/logo/run.x` does the same for its `"apps"` root. Repo mode emits
nothing and nothing changes. This is the house shape for configuration:
the embedder supplies data on the base (`alloc-limit!` precedent), the
mechanism lives in-language.

### 4. Runtime literal sweep + ratchet

Outside boot, exactly four `"lib/..."` literals survive at runtime
(today; found by grep, not by hand):

- lib/x/platform/syscall.x:10-12 — the three per-OS syscall tables
- lib/x/tool/compile.x:248 — asm-compile

These become `./`-relative `include-once` (which resolves against the
including file — reference: include-relative rules), making them
position-independent verbatim. A new check in the `make test` gate list
then holds the line: **no root-relative path literal outside the boot
sources** — auto-discovered by the same grep, so a future `"data/..."`
literal fails the build loudly instead of breaking installed trees
silently. That closes the BAKE footgun's whole class, not one instance.

## Install, after

- `share/x/lib/` and `share/x/apps/`: **verbatim copies**. Self-check:
  `diff -r` against the source tree, in the install target itself.
- `share/x/boot/`: the generated amalgams. The wrapper's installed-mode
  ENTRY points here; repo mode keeps using `lib/<name>.x` live entries.
- `tools/base-paths.x` / `tools/obj-layout.x` need not be installed at
  all — they are boot-only contracts, inlined into the amalgams.
- The BAKE variable and its sed disappear.
- The live entry pointers (`lib/x.x` etc.) install verbatim like
  everything else; the wrapper never points at them when installed, and
  hand-catting them behaves exactly as it does today (cwd-relative) —
  inert, not a regression.

Boot also drops from ~50 file opens to one stream read per session.

## Migration (each phase lands green on the full gate)

1. **Re-key the registry by module name.** module.x, the x-core
   pre-seed block, the dialect-body pre-seeds, and the pre-seed
   invariant in boot-order.x. No intended behavior change; the suite
   plus check-boot-order is the proof.
2. **Sweep the four runtime literals** to `./`-relative; add the
   no-root-relative-literal check to the gate list.
3. **Plumb `%install-root`** through module.x and apps/logo (inert in
   repo — nothing defines it).
4. **Extract the order-walker** from boot-order.x; build
   `tools/amalgamate.x` on it; `make boot` target; a gate that boots
   each amalgam and runs a smoke (CI additionally runs the spec suite
   with `LANG_LIB` pointed at an amalgam — it is a drop-in for the
   entry the harness cats today).
5. **Rewire `make install`**: verbatim copy + `diff -r` self-check +
   amalgams + wrapper injection + installed ENTRY path; delete BAKE;
   re-run the install verification (batch smoke from an unrelated cwd:
   `-V`, helium/xenon/radon `-f` with a stdlib import, missing-lib
   inventory, decoy-`lib/` hijack case, uninstall leaves zero files).
6. **Docs**: architecture.md, dialects.md (boot description),
   contributing (the new literal rule).

## Risks

| Risk | Containment |
|---|---|
| Generator wraps or reorders a form | Splice-only rule; order-walker shared with the lint; amalgam smoke gate fails on first boot |
| Amalgam error line numbers are opaque | Provenance markers per inlined file |
| Live boot and amalgam diverge | Amalgam never committed, regenerated by make dependency; CI runs the suite against it |
| Registry re-key misses a pre-seed | check-boot-order's pre-seed invariant, re-keyed in the same phase |
| doctest re-boot SIGSEGV class | Unchanged: dialect bodies stay denylisted; build/ is outside doctest scope |

## Alternatives considered

- **Keep BAKE + a self-checking install** (abort if a relative literal
  survives). Defuses the silent miss but keeps shipping rewritten
  sources; pattern-based, so the check is still an enumeration.
- **A C-level include root** (root cell on the base consulted by the
  opener). Small, but the single open site serves user code too, so
  library-relative and cwd-relative intent collide — shadowing and
  fallback ambiguity forever, plus new C for something expressible at
  build time.
- **Wrapper `cd`s into the tree.** `import` is lazy, so the process
  must stay there all session; user programs' relative `File` I/O then
  silently reads the library tree. Disqualified.
