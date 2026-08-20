# x-lang Modules

*Part of the C implementation of x-lang: computational expressions over a minimal, type-agnostic core.*

## Module System

x-lang provides a simple module system based on three forms: `provide`, `import`, and `include`. The system supports include-once deduplication and a module registry for discovery.

### `provide`

Declares a module and registers its exported symbols:

```
(provide x/core/list
  map filter fold sort reverse append ...)
```

`provide` records the module name and its export list in the module registry. It does not affect evaluation — any definitions in the file are already bound in the environment by the time `provide` runs at the bottom of the file.

### `import`

Loads a module by name, with deduplication:

```
(import x/type/vector)
(import x/num/float)
```

`import` dedups by **module name**: if the name is already in the
loaded-module registry it is a no-op; otherwise it registers the name,
resolves it to a file path through the search roots (e.g., `x/core/list`
becomes `lib/x/core/list.x`), and loads the file. Name-keyed identity is
what makes an installed tree work — the same module reached through a
different root (repo `lib/` vs an installed absolute root) is still the
same module.

### `import-version-once` / `import-version`

A module may exist in several **versions at once**, as sibling files — the
bare file is version 0, and `@`-suffixed files carry dotted versions with
missing components meaning 0:

```
x/type/thing.x          version 0        (every unversioned module)
x/type/thing@1.3.x      version 1.3.0
x/type/thing@1.3.1.x    version 1.3.1
```

`import-version-once` selects among them by a **spec string** — the version
is an argument, never part of the module name, and every version file
`(provide)`s the base name:

```
(import-version-once maze/grid "1.3")     ; exactly 1.3.0
(import-version-once maze/grid "1.3.*")   ; newest 1.3.*  — picks up patches
(import-version-once maze/grid "^1")      ; newest within major 1
(import-version-once maze/grid "*")       ; newest present
```

The spec must be a string literal: `3.1` the float is `3.10` the float, so
only a string can spell a version. Resolution walks the import roots in
order; the **first root holding any satisfying candidate wins**, even if a
later root holds a higher version — root order is precedence (the overlay
shadows the platform), exactly as with `import`. Exact specs probe the
literal filename first and fall back to the scan, so equivalent spellings
(`3.1` on disk vs `"3.1.0"` requested) unify numerically.

Fixes flow through resolution, not mutation: files are append-only, a bug
fix is a new patch file, and every import whose spec admits it selects it
on its next run. Byte-exact reproducibility remains vendoring's job
(`Pin sync` resolves the constraint and the lockfile digests the chosen
file).

Dedup keys the **base name**, once per session, with a contract: if the
module is already loaded and the loaded version **satisfies** the spec,
no-op; loaded and *not* satisfying — or loaded bare, its version
unknowable — is a loud error naming both sides. (A later bare
`(import name)` still no-ops silently; that is `import`'s own contract,
unchanged.) `import-version` is the raw re-evaluating sibling, mirroring
`include` vs `include-once`; it re-records the version it loads.

One prose rule rides along: in this ecosystem the series spelling "1.x"
collides with a literal filename — write `1.*`.

Two observability surfaces live on `Pin` (`import x/tool/pin`):
`(Pin resolve 'maze/grid "1.3.*")` is the dry run — the file the spec
would load, resolved against the current roots, nothing loaded.
`(Pin unused "src")` is the safe-removal answer: the version files no
import in the scanned sources selects. Provably neutral — resolution
takes the newest satisfying candidate per root, so a file it lists
cannot change any scanned import's outcome by being removed. The answer
is relative to the sources scanned; an external consumer's specs are
invisible to it.

### `include`

Raw file inclusion without deduplication:

```
(include "lib/x/core/list.x")
```

`include` always loads the file. Use `import` instead unless you specifically need to reload.

### `include-once`

Like `include`, but tracks which paths have been loaded and skips duplicates:

```
(include-once "./support.x")
```

`include-once` dedups by **path** (it loads files, not modules) and is the
right tool for non-module files. For library modules always use `import` —
the two registries are separate, so an `include-once` of a module file does
not make a later `import` of that module a no-op. Root-relative literals
like `"lib/..."` are boot-closure-only (`make check-path-literals`): they
resolve against the process cwd and break installed trees.

### Module Naming Convention

Module names map directly to file paths:

| Module Name | File Path |
|-------------|-----------|
| `x/core/list` | `lib/x/core/list.x` |
| `x/num/float` | `lib/x/num/float.x` |
| `x/type/vector` | `lib/x/type/vector.x` |
| `x/sys/posix` | `lib/x/sys/posix.x` |

The resolution rule is: `lib/<module-name>.x` where slashes in the module name become directory separators.

Two extensions to the rule:

- **Search roots** — `(import-path! "path/to/root")` adds a search root, so
  `(import my/module)` can resolve outside `lib/` (e.g. an application tree).
  The default root is `lib`.
- **Relative includes** — an `include-once`/`import` path starting with `./`
  or `../` resolves against the *including file's* directory, not the working
  directory. Raw `include` paths stay verbatim.

## Pinning

A project can pin the library modules it depends on: keep the exact
module files it was written against in its own tree, and have `import`
resolve those names there instead of in the installed library. Pinned
code then keeps its behaviour as the library evolves. (This section is
the reference; for the guided path — new project, retrofit, daily
work — see [Pinning, step by step](pinning-tutorial.md).)

### The manifest: `pin.xon`

A project declares its pins in a `pin.xon` file at its root. The
`(Pin init)` writes a commented starter manifest and refuses to
overwrite one; the file is three forms you can equally write by hand. The
manifest is **xon** — x object notation: a sequence of x-lang data forms
(with `;` comments), read with the ordinary reader and **never
evaluated**. Its consumers interpret a closed vocabulary; an unknown
form is a loud error, not a skip.

The pin vocabulary:

```
; pin.xon
(root "deps")       ; overlay root, relative to this file's directory
(boot "boot/xe.x")  ; boot entry: run this amalgam as the boot
```

- `(root "DIR")` — adds an overlay root to the import search roots.
  A relative `DIR` resolves against the manifest's own directory; an
  absolute one is used as-is. The directory must exist, and holds
  module files in the standard name layout (`deps/x/core/list.x` pins
  `x/core/list`). Roots listed first win, and every overlay root takes
  precedence over the platform library.
- `(boot "FILE")` — names the boot entry: the wrapper boots `FILE` (a
  fetched, verified amalgam — see below) instead of the platform's
  entry, and everything else still happens — the overlay roots arm,
  both pins are announced. A relative `FILE` resolves against the
  manifest's directory. A missing file is a loud error, never a
  fallback to the platform entry. This is the one form the *wrapper*
  consumes (it must choose the entry before the pipe exists), so it
  must sit alone on its own line; `--boot FILE` on the command line
  overrides it.

An overlay tree only needs the modules being pinned — anything not
found there falls through to the platform library. Note that a pinned
module's own `import`s also resolve through the roots, so a pin that
must not mix with newer dependencies should vendor its import closure.

A complete pinned project:

```
myproj/
├── pin.xon              ; (root "deps")
├── main.x               ; (import x/type/dict) ...
└── deps/
    └── x/type/dict.x    ; the exact dict.x this project was written against
```

```sh
x -f myproj/main.x
# pinned: /path/to/myproj/pin.xon      <- stderr notice
```

`main.x`'s `(import x/type/dict)` loads `deps/x/type/dict.x`; every
other import falls through to the installed library.

### Vendoring the closure

The platform ships the vendor tool: the `Pin` class in `x/tool/pin`.
It computes a module's **import closure** statically — the module, its
transitive imports (including imports inside deferred `fn` bodies), and
any `./`-relative include siblings — by reading sources with the
reader, never loading them, and copies the closure into an overlay
root, preserving the layout:

```
> (import x/tool/pin)            ; FIRST import of the session
> (Pin vendor "deps" 'x/type/dict)
("x/type/dict.x" ...)
> (Pin closure 'x/type/dict)     ; the same list, without copying
```

Vendoring the closure is what keeps a pin honest: a pinned module's own
imports resolve through the same roots, so vendoring only the module
itself would silently mix it with newer dependencies.

Two rules the tool enforces:

- **The boot floor is skipped, and a boot-floor seed is refused.** A
  module pre-seeded by the running dialect's boot is unpinnable (the
  pin boundary), so a vendored copy of one is dead weight. The floor is
  snapshotted when `x/tool/pin` loads — which is why a vendor session
  should be fresh, with the tool imported first.
- **Nothing is skipped silently.** A path the static walk cannot
  resolve — a computed include, an absolute or root-relative literal —
  is a loud error, never a silently unvendored dependency.

### The lockfile and verification

`vendor` also writes `<root>/pin.lock.xon` — xon, like the manifest,
with one `(file "REL" "sha256:HEX")` entry per vendored file (the
digest is `Sha256` from `x/codec/sha256`, pure x-lang), plus one
`(seed "NAME" "REL" ...)` entry per vendor recording what that vendor
claimed. `NAME` is the module name, or `project:DIR` for
`vendor-project`. `verify` recomputes it all:

```
> (Pin verify "deps")
5
```

Every lockfile entry must exist and match its digest, and **every file
in the tree must be listed** — an unlisted file is a rogue shadow ready
to win root precedence, so the overlay must be exactly the lock. A
missing lockfile, a missing or modified file, or an unlisted file is a
loud error naming each offender; on success `verify` returns the file
count. Verification runs are honest by construction: the hash module
loads eagerly with `x/tool/pin`, before any overlay root is armed, so
an overlay cannot shadow the hasher that checks it.

The seed records are what make a *re-vendor* honest. Repeated vendors
into one overlay accumulate, so the file list alone cannot say which
vendor put a file there — and without that, a dependency dropped
upstream stayed in the tree *and* the lock, still shadowing the
platform, with `verify` calling the pair clean because both had gone
stale together. Re-vendoring a seed now replaces that seed's claim: a
file no remaining seed claims leaves the lock and is named on stderr.
It is not deleted — the overlay is the project's tree — so `verify`
reports it as unlisted until you remove it. Entries written before
seeds existed are unattributed and kept as-is, so an older overlay
keeps verifying and keeps merging.

### Vendoring and auditing a whole project

`vendor` pins one module; a project imports many. `vendor-project`
scans a source tree for every `(import NAME)` and vendors the **union**
of their closures in one call — the retrofit that would otherwise be a
`grep` for imports plus one `vendor` each:

```
> (import x/tool/pin)            ; FIRST import of the session, unarmed
> (Pin vendor-project "deps" "src")
("x/type/dict.x" ...)
```

The scan follows only `(import NAME)` into the library; a project's own
`./`-relative includes are its own files, not dependencies. Like
`vendor`, run it from a fresh unarmed session so names resolve to the
platform being vendored *from*, and boot-floor seeds are skipped.

`audit` closes the **half-pin** gap: because an armed pin only prepends
overlay roots, an import of a module the overlay does *not* carry
silently falls through to the live platform. `audit` scans the same
project closure and reports every required file missing from the
overlay:

```
> (Pin audit "deps" "src")       ; () when the pin is complete
()
```

It returns the list of missing root-relative paths (empty means
complete) and prints a notice when non-empty, so CI can fail an
incomplete pin with a guard like
`(if (null? (Pin audit "deps" "src")) ok (error "half-pin"))`. The
source directory defaults to `"."`.

### Pinning the platform: released amalgams

Overlay pins cannot cross the pin boundary — the boot set itself.
Pinning the *platform* means running a pinned boot: every release tag
publishes the amalgamated boot entries (each dialect's full boot as one
self-contained file), together with `SHASUMS` and `pin.release.xon` —
per-file sha256 digests plus two whole-release facts: the **ISA
fingerprint**, the digest of the C-surface manifest the amalgams were
built against, and the **payload fingerprint**, one digest over
everything the release ships as library (`lib`, `apps`, `boot`). The two
answer different questions. The ISA fingerprint answers *will this
amalgam run on this engine's C surface* — and because that surface is
deliberately fixed, it is identical across releases whose library
changed completely. The payload fingerprint answers *which release is
this*, and changes whenever the shipped bytes do. An amalgam has zero
path literals, so a verified download boots directly against a
matching engine binary:

```sh
sha256sum -c SHASUMS            # verify the download
cat xe.x program.x | ./x-bin --batch
```

The same release ships that matching engine as a relocatable per-platform
tarball (`x-<tag>-<os>-<arch>.tar.gz`) — built from the same tagged
source, so it carries the release's fingerprints by construction. An
installed tree records them beside its library, in
`share/x/contract/`: `isa.sha256`, `payload.sha256`, and `release` (the
tag). The engine reports its own tag as `x-release`, which `x -V`
prints. The engine and the amalgams are two separately verified
artifacts that pair through the release tag; you never have to build the
engine to pin the platform.

The platform can also fetch and verify in one step:

```
> (import x/tool/pin)
> (Pin fetch "boot" "v0.4.0" 'xe)
pin: verifying boot/xe.x (pure x-lang sha256; an amalgam takes minutes)
pin: isa fingerprint matches this tree
"boot/xe.x"
```

`fetch` downloads the tag's `pin.release.xon` and the named entry (curl
via fork/exec — no shell; absent curl it prints the URLs and stops:
transport is optional, verification is not), digests the download with
the pure-x `Sha256` against the manifest, and errors on any mismatch —
the file is left in place, named, and must not be booted. The release's
ISA fingerprint is compared against the local `tools/contract/isa.x` when one
exists; drift is reported, not an error — a pinned platform pairs with
its own release's engine. A trailing base-URL argument overrides the
default release home (a mirror, or `file://` in the smoke).

Both tiers compose through the manifest: declare the fetched amalgam
with `(boot "boot/xe.x")` beside the `(root ...)` forms, and the plain
`x -f main.x` boots the pinned platform *and* arms the overlay,
announcing both. The direct `cat` pipe above remains the zero-wrapper
path, but it bypasses the wrapper — no probe, no arming, no notices —
so a project pinned at both tiers should run through the manifest.

### Probing and arming

The shell wrapper probes for `pin.xon` starting from the **program's**
directory (`-f`/`-F`), or the current directory for a REPL, walking up
parent directories git-style. A found manifest is always announced —
one `pinned: <path>` line on stderr, plus a `pinned boot: <path>` line
when a boot entry is pinned — and `--no-pin` skips the probe entirely.

The wrapper interprets two manifest forms itself, both extracted
textually (never evaluated), because both must be decided before the
pipe exists — the loader runs too late for either: `(boot "FILE")`,
which names the boot entry, and `(allow-release-skew)`, which waives the
release pairing refusal described below. Everything else stays interpreter-side: the wrapper
hands the manifest's path over as data (`(def %pin-file "<path>")`
ahead of the boot entry) and loads `x/tool/pin` right after boot,
before the first user form. That loader — always resolved from the
platform library, never from an overlay — reads the manifest, checks
the vocabulary (including the shape of `(boot ...)`), and arms the
roots via `import-path!`. Because nothing in the manifest is
evaluated, a manifest can only do what pinning does: redirect import
resolution into its own project's files, and select which verified
boot to run.

### Release pairing

A pinned boot amalgam and the engine that runs it must come from the
same release. An amalgam binds against far more than the C surface —
boot structure, object-model conventions, the library it will import
from — so a mismatched pair does not fail cleanly; it segfaults
mid-boot. The ISA fingerprint cannot catch this, because the C surface
it digests is identical across releases the library changed completely
between.

The release tag is the key that can. `Pin boot` records it in the lock
(`(release "vX.Y.Z")`), `make install` stamps the engine's own into
`share/x/contract/release`, and the wrapper compares the two before the
amalgam reaches the engine — the last point where a refusal can still
prevent the crash:

```console
$ x -f main.x
Error: pinned boot amalgam is from a different release than this engine
  amalgam: /proj/boot/he.x
  its release:  v0.4.0
  this engine:  v0.5.0
  ...
  Fix by moving the pin:  (Pin boot "v0.5.0")
```

Both remedies are real ones: move the pin to the engine you have, or
install the engine the pin names. When neither is wanted, the waiver is
`--allow-release-skew` for one run, or `(allow-release-skew)` in the
manifest for a project that makes the choice repeatedly. Neither is a
fix — the pairing that crashes still crashes — so the wrapper stays
loud about proceeding.

The check runs in installed mode only, and is silent when either side
has nothing to say: a lock written before the tag was recorded, or a
tree installed before it was stamped, prints an *unchecked* notice
rather than passing quietly. `(Pin verify)` reports the same comparison
without enforcing it, alongside the payload fingerprint — which catches
the narrower case of a tree carrying the right tag and the wrong bytes.

### The pin boundary

Two structural rules bound what an overlay can change:

- **One version per name per session.** `import` dedups by module name,
  first load wins — two versions of the same module cannot coexist in
  one session.
- **The boot set is unpinnable.** Modules loaded by the boot closure
  are pre-registered in the loaded-module registry, so an `import` of
  them is a no-op before any search root is consulted. An overlay copy
  of a boot module is ignored by construction; pinning the platform
  itself means running a different boot entry, not overlaying files.

`make check-pin` smokes all of this end to end (overlay resolution,
root precedence, the unpinnable core, the closed vocabulary,
`--no-pin`, the boot+overlay composition, and both pairing guards).

### Bootstrap Sequence

The bootstrap loader `lib/x-core.x` loads modules in a specific order:

1. **Boot phase** — Loads the boot layer via raw `include`: two repo contracts (`tools/contract/base-paths.x`, `tools/contract/obj-layout.x`) and the seven `lib/x/boot/` files (`registry.x`, `operatives.x`, `data.x`, `reflect.x`, `printer.x`, `string.x`, `module.x`). These establish the catalog, the object layout, printing, and the minimum needed for `provide`/`import` to work.

2. **Pre-registration** — Every library path x-core loads (all its raw `include`s, the boot files, and `lib/x-core.x` itself) is pre-registered in the include-list, so `import` calls within those modules are no-ops (the paths are already marked as "included"). Raw `include` does not register a path, so this parallel list is the registration; `make check-boot-order` enforces that the two stay in sync.

3. **Module loading** — Each module is loaded via `include` in dependency order. Modules use `import` for their own dependencies (which resolve as no-ops due to pre-registration) and `provide` at the bottom to register their exports.

This pre-registration pattern is also used by the dialect bodies (`lib/x/boot/xenon.x`, `lib/x/boot/radon.x`) to register their additional modules before loading them.

### Discovery

List all registered modules at the REPL:

```
> (modules)
```

This returns the module registry — an association list of `(name . exports)` pairs.

Look up documentation for a specific function:

```
> (help 'map)
```

### Writing a Module

A typical module file:

```
; my-module.x -- Description of what it does
;
; Requires: list.x (map, filter)

(import x/core/list)

(doc (def my-function
  (fn (_ x y)
    (map (fn (_ a) (+ a y)) x)))
  (param x LIST "Input list")
  (param y INTEGER "Value to add")
  (returns LIST "List with y added to each element")
  "Add y to every element of x.")

(provide x/my-module my-function)
```

Key conventions:
- Comment at the top naming the file and its dependencies
- `import` dependencies before use
- Every `fn` receives itself as argument 0 — write `(fn (_ a) ...)` (or name
  it `self` for recursion). Omitting the self slot does not error: the
  arguments shift by one and the function silently computes garbage.
- Wrap definitions in `(doc ...)` for automatic documentation generation
- `provide` at the bottom listing all public exports
