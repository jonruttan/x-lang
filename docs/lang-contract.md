# The Lang Contract

x-lang is one language. A **lang** is another one running on top of it — Logo,
R5RS Scheme, Kernel: each a different surface, implemented in x-lang, loaded
over a dialect. `helium`, `xenon` and `radon` are not langs; they are dialects,
and the difference is the first section below.

This document is the terms a lang is held to, what it may rely on, and how one
is acquired as a pinned, verified bundle. It is written for someone extracting
a lang from this tree or writing a new one.

The platform already used the word before this document did: a lang announces
itself by setting `%lang-name` and `%lang-version`, which is what puts its own
name on the banner and its own prompt on the REPL.

> **Status: shipped, with one gap.** Acquisition, loading and the seam are
> gated (`Pin bundle`, `-l NAME`, `make check-pin`, `make check-seam`). What is
> still missing is on the *bundle* side, not this one: nothing generates a
> bundle tarball yet, so a publisher rolls one by hand. Each section says where
> it stands. The terms are written down first *because* the last generation of
> langs rotted while nobody was holding them to any: see [Why the last
> generation rotted](#why-the-last-generation-rotted), which is the evidence
> this document is built on.

## Dialect and lang

The line already exists in [dialects.md](dialects.md), and it is the line that
decides what can leave this repository:

| | is | may re-mean a shared spelling | can live elsewhere |
|---|---|---|---|
| **dialect** | a composition of x-lang modules; differs in what surface is *loaded* | **never** | no |
| **lang** | a different surface language, announcing itself as one | yes — that is the point | **yes** |

A `+` that means pointer arithmetic in one dialect is not a dialect, it is a
different language wearing the same clothes. That rule is what makes `he`/`xe`/`rn`
inseparable from the language: they are covered by the spec suite and
`check-dialect-cover`, and their meanings *are* the specification. A lang
is under no such obligation — Kernel's `$vau` and Scheme's `lambda` are supposed
to mean something x-lang does not — and that freedom is exactly what makes a
lang safe to ship as a separate, pinned artifact.

**So the boundary was drawn before this document, and everything on the far side
of it is a lang.** Logo included: it lives in `apps/` because it also
ships a server and a viewer, but `apps/logo/README.md` describes it as "a second
surface language" and "the worked demonstration of the claim that whole surface
languages load on top of a dialect." That is a lang's job description.

## The three pinned artifacts

x-lang already acquires two of its three parts rather than containing them. A
lang bundle is the third, and it is deliberately the *least* novel of them:

| artifact | pinned by | acquired by | status |
|---|---|---|---|
| **engine** | `tools/engine/engine.pin.xon` | `tools/engine/fetch.sh` | shipped |
| **platform boot** | `(boot …)` in `pin.xon` | `Pin boot` / `Pin fetch` | shipped |
| **library overlay** | `(root …)` in `pin.xon` | `Pin vendor` — copies from the *installed platform* | shipped |
| **lang bundle** | `lang.pin.xon` | `Pin bundle`, run with `-l NAME` | **shipped** |

Read the third row carefully, because it is the whole reason the fourth is
needed: `Pin vendor` freezes library modules by copying them out of the platform
you already have. There is today **no mechanism anywhere for acquiring a
third-party x-lang tree.** That is the gap, and it is the only genuinely missing
piece — everything else below is an arrangement of parts that already exist.

## What a bundle is

A lang bundle is an **app-shaped tree**: a directory holding one entry
file and the modules it loads.

```
x-r5rs-v0.2.0/
├── lang.xon      ; the bundle's own declaration (see below)
├── run.x                ; THE entry -- what `-l r5rs` boots
├── r5rs/                ; modules, resolved by import
│   ├── base.x
│   └── ports.x
└── tests/specs/*.spec.md
```

**The shape is not new, and that is the point.** `x.sh -l NAME` already resolves
`lib/NAME.x` first and then `apps/NAME/run.x`; Logo has ridden that seam since
#35. A bundle is the **third step**: the wrapper searches
`<root>/langs/*/lang.xon` for one declaring `NAME`, reading it
textually the way it reads every other manifest. `X_LANG_DIR` moves that
search for a project keeping its bundles elsewhere.

### A bundle does not boot itself

The third step differs from the first two in what it makes the entry, and the
difference is worth stating because it removes work rather than adding it.
`lib/he.x` and `apps/logo/run.x` are *self-booting* — they include the platform
themselves. A bundle does not. The wrapper boots the dialect the bundle
**declares**, then loads the bundle on top:

```
(def %install-root "…")        ; as always
cat lib/he.x                    ; the DECLARED dialect, in --batch so its
                                ; own launcher stays quiet
(import-path! "…/r5rs-v0.2.0")  ; the bundle's module root
cat …/r5rs-v0.2.0/run.x         ; the lang
cat lib/x/repl/launch.x         ; the prompt, when no -f was given
```

That is exactly the shape `-F` has had all along — entry in batch, file, then
launcher — so there is no new loader and no new composition.

**A bundle's entry therefore needs no root-relative literals at all.** The
platform is already up when it is read, and the bundle's own modules resolve
through the root emitted above. The one-entry-file rule below still governs
*in-tree apps*, which do self-boot; a bundle is freer than the rule requires.

A bundle declaring a dialect this tree has no entry for is refused **by name,
before anything boots**, and two bundles claiming one name are refused rather
than resolved by directory order — which one you got would otherwise depend on
the filesystem.

### One entry file, and one only

`tools/check/path-literals.sh` forbids root-relative load literals
(`(include "lib/…")`) everywhere except the boot closure and **`apps/*/run.x`** —
app entries, which are self-booting and flattened away by the amalgam generator.
Everything else must use `import` (root-resolved) or `./`-relative
`include-once` (file-relative), both of which work from any tree root.

For a bundle this stops being a lint and becomes the load-bearing rule:

> **A bundle has exactly one file that may carry root-relative literals: its
> entry. Every other file resolves its siblings by `import` or `./`-relative
> `include-once`.**

A bundle that obeys this relocates. A bundle that does not is nailed to the
directory it was written in — which is not a hypothetical failure, it is
precisely how the previous generation died.

### The declaration

`lang.xon` — xon, read with the ordinary reader and never evaluated, like
every other manifest here:

```x
(lang "r5rs")          ; the -l name, and the name the pin must agree with
(dialect he)                  ; which dialect the wrapper boots for it
(requires-release "v0.5.2")   ; the x-lang the bundle was built against
(entry "run.x")               ; loaded after the dialect, not instead of it
```

`(dialect …)` is a **requirement**, not a preference: a lang that calls
`x/sys/socket` needs radon, and declaring helium means it dies at boot on a
missing import rather than at acquisition on a legible refusal.

## The pin

A project names the langs it uses in `lang.pin.xon`, mirroring
`engine.pin.xon`'s closed vocabulary:

```x
(lang "r5rs")
(release "v0.2.0")
(bundle "sha256:…" "https://github.com/jonruttan/x-r5rs/releases/download/v0.2.0/x-r5rs-v0.2.0.tar.gz")
(source "https://github.com/jonruttan/x-r5rs.git")
```

**The digest is of the archive, and that took a change to `Sha256` to be
possible at all.** `(Sha256 hex)` bounds itself by `Str8 length`, which has
strlen semantics — so a gzip, whose fourth byte is a NUL, digested as a
three-byte fragment and compared unequal to itself. The first implementation of
this verb failed its own digest check, which is how the defect surfaced.

`(Sha256 hex-n s n)` takes the length as an argument, so the whole archive
digests in pure x. That matters beyond convenience: verification stays a
property of this library rather than of whatever the host happens to have
installed, and `tar` never runs over bytes nothing has vouched for.

**An unknown form is a loud error, never a skip** — the ruling `pin.xon` and
`engine.pin.xon` both already follow. A manifest that silently ignores what it
does not understand cannot be extended without wondering which readers obeyed
which half of it.

**There is no os/arch matrix, and the absence is the interesting part.** The
engine pin carries one `(artifact OS ARCH …)` row per platform because an engine
is a binary. A lang is pure x-lang, so there is exactly one artifact per
release and the entire platform-selection apparatus — `uname`, the contract
spellings, the source-build fallback for platforms nobody publishes for —
evaporates. Do not copy it across out of symmetry; every row of it would be a row
that cannot be wrong in an interesting way.

### Acquiring one: `Pin bundle`

```x-repl
> (import x/tool/pin)
> (Pin bundle "deps")
pin: verifying x-r5rs v0.2.0 (jit sha256)
pin: bundle matches this platform (v0.5.2)
"deps/x-r5rs-v0.2.0"
```

The order is the whole design, and it is the order of what is trusted when:

1. Read the pin. An unknown form is an error here, **before any network**.
2. **Already acquired at this release?** Honour it, no network. A tag cannot
   change its bytes — the tag *is* the identity.
3. Download the archive to a pid-tagged **temp** path.
4. **Digest it there, before `tar` is run at all.** A mismatch quarantines the
   bytes as `<archive>.rejected` — inspectable, never unpacked — and nothing is
   published. This is the discipline #145 taught the amalgam fetch, which wrote
   its target first and so made a rejected download the booted one.
5. Unpack the verified archive into a per-pid **staging** directory, and rename
   it into place only once whole. Staging is for **atomicity** here, not
   quarantine: a `tar` that dies half way (a full disk, a truncated member) must
   not leave a partial tree at the published path, where step 2 would later read
   it as a complete one.
6. Check the bundle's `lang.xon` agrees with the pin about which
   lang it is — a digest proves the bytes are the ones published, not
   that the right thing was published — and report release pairing.

**There is no unpack-before-verify window.** An earlier draft of this contract
had one, because it digested a per-file manifest rather than the archive, and it
did so because `(Sha256 hex)` could not measure a binary file. Widening `Sha256`
removed the reason, and removing the reason removed the window, a manifest file,
its generation step, and the rules that a manifest may not list itself and that
an unlisted file is a failure. The lesson is worth keeping even though the code
is gone: **a constraint that shapes a design is worth re-testing before the
design hardens around it.**

### Acquisition happens in x, not in shell

`tools/engine/fetch.sh` is shell, and its header is explicit that this is a
concession rather than a style: it "runs before there is an engine to run x
with, which is the one place in `tools/` where the charter's *logic lives in x*
cannot apply."

That exemption does not transfer. A lang is fetched with x already
running, so acquisition belongs in x — as a verb on the existing `Pin` class,
which already has pure-x `Sha256`, curl via fork/exec with no shell, and the
discipline #145 taught it: **the download lands on a temp path, is digested
there, and is renamed into place only on a match; a rejected download is
quarantined rather than deleted, because the bytes are the evidence.**

Two rules inherited from the engine fetch, for the same reasons:

- **A declared bundle that fails is an error, never a quiet fallback to source.**
- **An existing valid tree is honoured** — same digest, no network. Offline is the
  normal case for anyone who has fetched once.

## The seam

This is what a lang may rely on. It is declared in
`tools/contract/seam.x` and held to the running platform by `make check-seam`,
in every dialect:

| name | is | provided by |
|---|---|---|
| `%lang-name` | the surface's name, for the banner | `lib/x/boot/helium.x`, `radon.x` |
| `%lang-version` | its version string | same |
| `%banner` | prints the greeting | `lib/he.x`, `lib/rn.x` |
| `%repl-prompt` | the prompt string, `set!`-able | `lib/x/repl/loop.x` |
| `repl` | the read-eval-print loop | `lib/x/repl/` |
| `%batch?` | `-f`/`--batch` was passed | x-core, via `repl/banner.x` |
| `%install-root` | the installed tree's root, when installed | `lib/x/boot/module.x` |
| `import-path!` | arm an import root at runtime | `lib/x/boot/module.x` |
| `x-lib-version` | the library's version | `lib/x-core.x` |

The idiom for a bundle arming its own root, taken from `apps/logo/run.x` — the
`guard` is what makes one file work in both a repo checkout and an installed
tree:

```x
(import-path! (guard (_ "apps") (%path-join %install-root "apps")))
```

`%install-root` is the one conditional row: a checkout has none, which is why
the idiom above guards it. The gate checks that too, from the other side — a
row that quietly became unconditional would turn every lang's guard into
superstition, so it fails if a checkout starts providing one.

A lang that reads a `%`-prefixed name not in this table is relying on a
platform internal, and the platform owes it nothing. **This table is the
contract; the rest of `lib/` is not.**

**Declared, not derived**, and the departure from `check-base-routes` is worth
being explicit about. That gate derives route names from the library's own call
sites, because the caller is in this tree. A lang's call sites are *not* in this
tree and never will be — that is what makes it a lang — so there is nothing here
to derive from. `seam.x` is the other shape the repo already uses: a closed
vocabulary the language owns, like `tools/contract/features.x`.

The gate also holds this table and `seam.x` to each other. Two lists for one
fact is how they drift, and a documented seam that nothing enforces is the state
this gate was added to end.

## Release pairing: what actually keeps a bundle working

**Digest pinning freezes a bundle. It does not keep it running**, and confusing
the two is the failure this section exists to prevent. A pin guarantees you get
the same bytes; it says nothing about whether those bytes still work against a
platform that moved. Worse, a pin that verifies cleanly reads as health, so
drift accumulates quietly.

`(requires-release …)` is what makes the pairing checkable, and the machinery for
checking it is already written: `x.sh` compares a pinned boot amalgam against
`share/x/contract/release` for exactly this reason, after #435 — a library
pairing failure reproduced with the engine held constant. A bundle is the same
subject with the same failure mode.

The comparison follows the platform's existing rule: **release strings are
compared for equality and never parsed.** A mismatch is reported against a
declared waiver (`allow-release-skew`, as the boot pin already spells it), so
that running a bundle against an untested x-lang is a decision someone made
rather than something that happened.

### Why the last generation rotted

Five langs sit unbuilt outside this repository — `x-ash`, `x-krn`,
`x-r5rs`, `x-r7rs`, `x-sweet`. They are the evidence for every rule above, and
none of them failed for want of a digest:

- **Path literals in every file.** `(include "lang/krn/lib/krn-base.x")` — nailed
  to a directory layout the repo abandoned. This is the rule the one-entry-file
  clause above exists to enforce.
- **Module names moved underneath them.** They load `lib/x/posix.x`,
  `lib/x/hash.x`, `lib/x/compile.x`; those are now `lib/x/sys/posix.x`,
  `lib/x/type/hash.x`, `lib/x/tool/compile.x`. This is what `(requires-release …)`
  turns from a silent break into a refusal.
- **No CI anywhere.** They had spec suites and spec runners — genuinely good
  ones — that nothing ever ran after they left the tree. This is what per-bundle
  CI against a matrix of pinned releases is for.

The encouraging half: **the seam itself held.** `%repl-prompt`, `%lang-name`,
`%lang-version` and `%banner` are all still live and still mean what they meant.
Nothing in the old langs' *design* has expired — the ports are
mechanical. That is a strong argument for writing the seam down before it stops
being true by accident rather than by decision.

## How a lang is checked

Three questions, deliberately in three places:

**Does it acquire?** A hermetic `file://` smoke, the exact shape of
`tools/check/engine-fetch.sh` — which proves the acquisition path without a
network by pointing the pin at a local URL. This lives in x-lang, because
x-lang owns the acquisition code.

**Is it correct?** The bundle's own spec suite, run by its own CI, against a
**matrix of pinned x-lang releases** — at minimum its `(requires-release …)` and
the current release. This lives in the bundle's repository, because a
lang's definition of correct is its own business; x-lang is not the
arbiter of whether Kernel's `$vau` is right.

**Does the seam still hold?** A gate in x-lang deriving the seam from bundles'
call sites, the way `check-base-routes` derives base routes from the library's.
This is the one that would have caught all three rot modes above, and it is the
piece with the least prior art. Until it exists, the table under
[The seam](#the-seam) is documentation rather than a contract — which is why the
status banner at the top of this file says what it says.

### The spec runner: the platform publishes it

A bundle's tests need `tests/spec-runner.sh`, which is an x-lang repo asset
today. **The platform ships it; bundles do not vendor it.** Five findings settle
it; version coherence is the one that decides.

**It is already generic.** Strip the comments from the runner and grep the
logic: there is not one hardcoded spec name in it. `@lib` and `@weight` are
declared by the spec files themselves, so the runner is data-driven and the
suite-specific prose in its header is calibration notes, not behaviour. Nothing
has to be extracted from it to make it reusable.

**Sharing was the original design.** Its header states the interface — "Each
lang runner sets `SPEC_PATH`, `X_BIN`, and `LANG_LIB`, then sources this
file" — and every old lang did exactly that, in about twenty lines.

**What failed was addressing, not sharing.** The Kernel runner reached the
platform like this:

```sh
X_BIN="$SCRIPT_DIR/../../../x"
. "$SCRIPT_DIR/../../../tests/spec-runner.sh"
```

`$SCRIPT_DIR` was `lang/krn/tests`, so `../../../` was the x-lang repo root. Both
references dangled the moment the lang left that tree. Vendoring would
fix the dangle by copying 865 lines of shell and awk into every bundle — and buy
a spec-format dialect per repo, plus an N-repo re-vendor for every runner fix.

**Version coherence comes free the shared way, and only by hand the other.** A
bundle already names the x-lang it was built against, in `(requires-release …)`.
Source the runner from *that* release's install and the runner and the spec
format it implements cannot skew, because they are the same release's bytes. A
vendored runner is pinned to whatever was copied on whatever day, and nothing
relates it to the platform the bundle actually declares.

**It ships as a tool, outside the payload fingerprint.** The payload digest is
library bytes — `lib`, `apps`, `boot` — and it answers *which release is this*.
The wrapper and the engine already ship without joining it. The runner is a
tool, so it installs beside them (`share/x/test/`) and the fingerprint keeps its
current meaning.

### Running a bundle's specs

The platform answers two questions so a bundle never guesses:

| asked | answers |
|---|---|
| `x --share-dir` | the tree this x reads from — `share/x` installed, the repo root in a checkout |
| `x --engine-path` | the engine binary, after the wrapper's full discovery order |

One relative path then works in both modes: `<root>/tests/` is the repo's
`tests/` in a checkout and `share/x/tests/` in an install. The runner and its
awk harness install there; `make check-package` proves both ship and both flags
answer, on the extracted tarball rather than the staging tree.

A bundle's whole runner is about twenty lines, and not one path into the x-lang
source tree:

```sh
BUNDLE="$(cd "$(dirname "$0")/.." && pwd)"
X_ROOT="$(x --share-dir)"
X_BIN="$(x --engine-path)"
SPEC_RUNNER_DIR="$X_ROOT/tests"; export SPEC_RUNNER_DIR
LANG_LIB="$BUNDLE/tests/lib/harness.gen.x"
SPEC_PATH="$BUNDLE/tests/specs"
. "$X_ROOT/tests/spec-runner.sh"
```

Four things that are not obvious, each of which costs an afternoon:

- **`SPEC_RUNNER_DIR` is required from an installed tree.** The runner finds its
  awk harness from the directory holding the *engine* — true in a checkout,
  where the binary sits beside `tests/`, and false in an install, where the
  engine is under `libexec/x/`. A sourced script cannot portably find its own
  path, so the caller says. Unset and wrong, the runner now names the path it
  looked at instead of dying without one.
- **The harness must name the root before loading an amalgam.** An amalgam has
  zero include literals, but its deferred `import` forms resolve against the
  installed tree as it boots, and `module.x` learns where that is from
  `%install-root`. `x.sh` emits `(def %install-root "…")` ahead of every boot
  entry; a harness loading an amalgam directly must emit the same line first.
- **Load `boot/x-base.x`, not a dialect entry.** The dialect amalgams end with
  `(unless %batch? (do (%banner) (repl)))` and would start a REPL underneath the
  suite. `x-base.x` is the launcher-free one, and being an amalgam it carries no
  path literals, so it loads from any cwd. **The gap:** it is the *full tower*,
  and there is no launcher-free light amalgam — a helium-weight bundle pays for
  the tower or loads `lib/x-core.x` by absolute path with the cwd at `<root>`,
  because x-core's own includes are root-relative.
- **`# @lib` resolves against `LANG_LIB`'s directory**, not the spec's. A
  harness beside the specs is named bare — `# @lib harness.gen.x` — and a path
  that looks right relative to the spec silently produces an empty library,
  whose first symptom is `Unbound SYMBOL 'Io` rather than a missing file.

The harness is *generated* rather than committed, because it embeds two
absolute paths that are facts of the machine, not of the bundle.

## Writing or extracting a lang

The order that gets you running soonest:

1. **Make the tree relocatable first**, before it moves anywhere. One entry file
   with root-relative literals; every other file on `import` or `./`-relative
   `include-once`. Verify in an *installed* tree, not a repo checkout — the
   repo-root cwd is what hides this class of bug, and installed trees are the
   only environment where it bites.
2. **Declare the dialect you actually need**, by finding your imports rather
   than by preference. Logo's are honest and worth copying as a worked example:
   `x/num/float`, `x/reader/analyser`, `x/sys/{file,posix,socket}`, `x/type/str`
   — the socket and file imports are radon opt-ins, so Logo is a radon
   lang whatever else it might prefer to be.
3. **Take the tests with you.** A lang without a spec suite in its own CI
   is the previous generation with a fresh coat of paint.
4. **Move the registrations, not just the code.** A lang in this tree has
   rows in places that are easy to miss and loud when missed:
   `tools/contract/requires.x` (ISA needs), `tools/contract/percent-globals.x`
   (per-file budgets), the memory bucketing in `tests/spec-runner.sh`, and its
   own gate in the `gates` list.
5. **Land the extraction on a release boundary.** The payload fingerprint digests
   `lib`, `apps` and `boot`, so removing a lang from `apps/` moves it.
   That is correct behaviour — it is the fingerprint answering *which release is
   this* — but it means the removal is a release event, not a mid-cycle tidy.

The bar is lower than it looks: no engine work, no contract files, no
conformance suite. A lang is x-lang source that happens to mean something
else, and the only genuinely hard requirement is the first one.
