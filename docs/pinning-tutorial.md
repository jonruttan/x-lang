# Pinning, step by step

A walkthrough of pinning for project authors: setting up a new pinned
project, retrofitting an existing one, daily work, and pinning the
platform itself. The reference lives in [modules.md](modules.md)
("Pinning"); this page is the path through it. Every command and output
shown here was run as written. (`x` below is the installed command; in
a repo checkout spell it `sh x.sh`, run from the repo root.)

> **Requires x-lang ≥ v0.3.1-rc2.** The `Pin` authoring API
> (`closure`/`vendor`/`verify`/`fetch`) landed in v0.3.1; on v0.3.0 or
> earlier `(import x/tool/pin)` provides only the manifest runtime and
> `(Pin …)` raises `Unbound SYMBOL 'Pin`. Check with `(help Pin)`.
>
> **The manifest-driven verbs (`sync`/`check`/`boot`) and the `(src …)`
> form need a newer x still.** The manifest vocabulary is *closed* — an
> unknown form is a loud error, which is what catches typos — so a
> `pin.xon` carrying `(src …)` is refused outright by any x that
> predates it, with `pin: unknown form`. That cuts both ways: the
> project's own x, *and* whatever x your CI installs from a release.
> Adopt `(src …)` only once the release your project pins to has it,
> or the pin will refuse to arm on the very machine it was meant to
> make reproducible.

## What pinning buys you, in one minute

The library evolves. A program written today imports `x/type/dict` and
gets today's dict; after next month's release the same import gets next
month's. Usually that is what you want. When it isn't — a shipping tool,
a long-lived script, a project that must not move — you **pin**: keep
the exact module files your project was written against in the project
itself, and have `import` resolve them there.

Two tiers, because there are two kinds of drift:

- **Overlay pins** (this tutorial, mostly) freeze *library modules* —
  anything you `import` that is not part of the running dialect's boot.
- **Platform pins** freeze the *boot itself* — the dialect, the tower,
  the core semantics — by running a released amalgam (one
  self-contained boot file) with its matching engine.

Two structural limits to know up front:

- **The boot floor is unpinnable by overlay.** Modules the dialect
  boots with (all of `x/core/*`, the boot files, the tower under
  xenon/radon) are pre-registered before your overlay is consulted; an
  overlay copy of one is silently inert, and the vendor tool refuses
  the seed outright. Freezing those means a platform pin, not files.
- **One version per name per session.** `import` dedups by module
  name, first load wins — you cannot run two versions of one module in
  the same session.

## Pin a fresh project

Say `myproj/` depends on `x/type/dict` and must keep today's dict.

**1. Declare the manifest.** One file, two forms — where the pin goes,
and where your code lives:

```
$ cat > myproj/pin.xon
(root "deps")
(src "src")
```

`pin.xon` is **xon** — x object notation: data read with the ordinary
reader and never evaluated. `(root "deps")` adds `myproj/deps/` as an
import root ahead of the platform library; `(src "src")` tells the pin
tool where to read your imports from.

**2. Sync.** From the repo (or an installed x), start a *fresh*
session, unpinned, and import the pin tool *first* — the tool snapshots
the boot floor when it loads, so nothing you imported earlier can
distort what it considers pinnable:

```
$ x --no-pin
> (import x/tool/pin)
> (Pin sync "myproj")
("x/type/dict.x" "x/type/hash.x")
```

You never named a module. `sync` read the manifest, scanned `src/` for
every `(import ...)`, and vendored what it found — which is **two**
files, not one: `dict.x` and its import `hash.x`. That is the point —
vendoring is *closure-wise*. A lone vendored module would still resolve
its own imports against the live platform and silently mix old code
with new dependencies. (Everything else dict imports is boot floor
under this dialect, so it stays with the platform.)

This is also why there is nothing to maintain by hand later: when a
source file grows a new import, you re-run `sync`. The imports **are**
the dependency list, so there is no second list to keep in step.

The project now looks like:

```
myproj/
├── pin.xon              ; you write this
├── deps.lock.xon        ; generated: sha256 per file, named for deps/
├── src/
└── deps/
    └── x/type/
        ├── dict.x
        └── hash.x
```

The lock sits *beside* the overlay and is named for it. An integrity
record kept inside the tree it describes reads as part of the payload —
and two overlays sharing a parent would otherwise share one lock.

**3. Run.** Given an ordinary program —

```
; myproj/main.x
(import x/type/dict)
(def d (Dict make 8))
(d set! 'greeting "hello from a pinned dict")
(display (d get 'greeting))
(newline)
```

— nothing about running it changes:

```
$ x -f myproj/main.x
pinned: /path/to/myproj/pin.xon
hello from a pinned dict
```

The wrapper found `pin.xon` beside your program (it walks up from the
*program's* directory, git-style — not from wherever you happen to
run), announced it on stderr, and armed the root before your first
form. `(import x/type/dict)` now loads `deps/x/type/dict.x`; every
other import falls through to the platform. From now on the platform's
dict can change freely; yours doesn't.

**4. Check it, then commit it.** One call answers the whole integrity
question, and it is what CI should run:

```
> (Pin check "myproj")
()
```

Empty means the overlay matches its lock byte for byte *and* no import
falls through to the live platform. A half-pin — an import you added
but have not synced — comes back named:

```
> (Pin check "myproj")
pin: audit -- 1 import(s) fall through to the platform (absent from myproj/deps):
x/type/set.x
("x/type/set.x")
```

Then `pin.xon`, `deps.lock.xon` and `deps/` go into version control.
They *are* the pin.

## Retrofit an existing project

You have a working project and want to freeze what it uses today. This
is the case `sync` exists for: the code already states its dependencies.

**1. Declare where things live.**

```
$ cat > myproj/pin.xon
(root "deps")
(src ".")
```

`(src ".")` scans the whole project; point it at a subdirectory if your
sources live in one.

**2. Sync.** One call, whatever the project imports:

```
> (import x/tool/pin)
> (Pin sync "myproj")
("x/type/dict.x" "x/type/hash.x" "x/type/set.x")
```

Boot-floor imports are skipped, not refused — `x/core/list` ships
inside the dialect's boot, so under *this* dialect your program always
gets the platform's copy, and freezing it means a platform pin (below).
You do not have to know which of your imports those are; `sync` does.

**3. Check.**

```
> (Pin check "myproj")
()
```

Empty: the overlay matches its lock, and nothing falls through. You are
pinned.

If you need finer control than "everything the project imports" — a
single module, or a dry run of what a vendor *would* copy — the
lower-level surface is still there: `(Pin closure 'name)`,
`(Pin vendor "deps" 'name)`, `(Pin verify "deps")`. `sync` and `check`
are those verbs driven from the manifest.

## Daily work

- **The notice is your dashboard.** Every pinned run prints
  `pinned: <path>` to stderr — and a boot-pinned project prints a
  second line, `pinned boot: <path>`. No line, no pin — check where
  you ran from and where `pin.xon` lives.
- **Compare against the live platform** with one flag: `x --no-pin -f
  main.x` runs as if the pin didn't exist. The fastest answer to "is
  this bug ours or did the library move?"
- **Update a pin deliberately.** There is no auto-update: re-vendor
  from the platform you now want (`(Pin vendor "deps" 'x/type/dict)`
  again, in a fresh session), rerun your tests, commit the new
  `deps/`. The lockfile diff *is* the upgrade review. If the new
  version dropped a dependency, the re-vendor says so and drops it from
  the lock; delete the named file, since an orphan left in the overlay
  still shadows the platform and `verify` will flag it as unlisted.
- **Verify on suspicion, and in CI.** `(Pin verify "deps")` recomputes
  every digest and walks the tree; a modified, missing, or *unlisted*
  file (something shadowing that the lock never blessed) is a loud,
  named error. It's cheap on normal overlays — wire it into your
  project's test entry.
- **Don't hand-edit the overlay.** The overlay must be exactly the
  lock, so `verify` treats your hand-tuned copy as tampering. If you
  need a patched module, that's a fork you own: keep it as a normal
  overlay file *and re-vendor honestly* — vendor first, then edit,
  then accept that `verify` will flag it (or re-lock by re-vendoring
  your edited tree with a future tool). Today: patched modules and
  verify don't mix; choose one.

## Pinning the platform

When the *language* must not move — not just a library — run a released
platform. Every release tag publishes two kinds of artifact, built from
the same tagged source:

- **per-platform binary tarballs** (`x-<tag>-<os>-<arch>.tar.gz` +
  `.sha256` sidecar): the full install tree — wrapper, engine, library
  — relocatable, no toolchain, no compile;
- **amalgamated boot entries** (each dialect's full boot as one
  self-contained file), plus `SHASUMS` and `pin.release.xon` — per-file
  digests and the **ISA fingerprint**: the digest of the C-surface
  manifest the amalgams were built against.

(`v0.4.0` below stands in for whichever tag you are pinning; check the
[releases page](https://github.com/jonruttan/x-lang/releases) for what
each tag publishes.)

**Start with the tarball — you never have to build an engine to pin
the platform:**

```sh
tar -xzf x-v0.4.0-<os>-<arch>.tar.gz
sha256sum -c x-v0.4.0-<os>-<arch>.tar.gz.sha256   # verify the download
xattr -dr com.apple.quarantine x-v0.4.0           # macOS only (Gatekeeper)
x-v0.4.0/bin/x -f main.x                          # or add bin/ to PATH
```

That alone pins engine *and* library to the release: the tarball's
wrapper finds its own engine and library beside itself, and your
project's `pin.xon` overlay works unchanged through it.

To pin the boot **inside your project's tree** (so the repo itself
records it), name the amalgam in the manifest once:

```
(root "deps")
(src "src")
(boot "boot/xe.x")
```

then pin it to a release — fetched, verified, and recorded in one call:

```
> (import x/tool/pin)
> (Pin boot "v0.4.0" "myproj")
pin: verifying myproj/boot/xe.x (jit sha256)
pin: isa fingerprint matches this tree
"myproj/boot/xe.x"
```

`boot` takes the amalgam's name from the manifest — no dialect symbol
to repeat — and lifts the release's three facts (tag, ISA fingerprint,
amalgam digest) into `deps.lock.xon`, then discards the downloaded
release manifest. Two records of the same thing drift; one does not.
A later `sync` carries those lines through untouched, so growing an
import never silently unpins the language underneath it.

No curl on the machine? The fetch prints the URLs and stops — download
by hand, then check with coreutils beside the files: `sha256sum -c
SHASUMS`.

Then declare it beside your overlay roots — both tiers, one manifest:

```
; pin.xon
(root "deps")
(boot "boot/xe.x")
```

```sh
$ x -f main.x
pinned: /path/to/myproj/pin.xon
pinned boot: /path/to/myproj/boot/xe.x
```

The wrapper boots your amalgam *and* arms the overlay — two notices,
two tiers. (The `(boot ...)` form is the one form the wrapper itself
consumes, so it must sit alone on its own line; `--boot FILE` on the
command line overrides it.)

The raw engine pipe still works (an amalgam has zero path literals):

```
$ cat boot/xe.x main.x | ./x-bin --batch
```

— but know what it skips: no wrapper means no probe, no overlay
arming, no notices. A project pinned at both tiers should run through
the manifest, not the pipe.

Read the fingerprint line for what it is: **matches this tree** means
your current engine speaks the amalgam's C contract; **DIFFERS** means
the platform has drifted since that release — not an error, but your
pinned amalgam should run against its own release's engine: the
release tarball above, which carries the fingerprint by construction.

## When something looks wrong

| You see | It means | Do |
|---|---|---|
| no `pinned:` line | probe found no `pin.xon` walking up from the program | check the manifest's location; remember the REPL probes the *cwd* |
| no `pinned boot:` line | the manifest has no `(boot ...)` alone on its own line | the wrapper extracts that one form textually — one line, one string |
| `boot entry does not exist` | `(boot ...)` or `--boot` names a missing file | fetch the amalgam first, or fix the path (relative paths resolve against `pin.xon`'s directory) |
| `pin: unknown form` | the manifest has a form outside the vocabulary | `pin.xon` is data — only `(root "DIR")` today |
| `pin: root does not exist` | manifest names a missing overlay dir | fix the path (relative roots resolve against `pin.xon`'s own directory) |
| `unpinnable (boot floor)` | that module ships in the dialect's boot | nothing to vendor; freeze it via a platform pin if you must |
| `verify failed` + `modified:` | a vendored file's bytes changed since lock | re-vendor to restore, or treat as the tamper it looks like |
| `verify failed` + `unlisted:` | a file in the overlay the lock never blessed | remove it, or vendor it properly |
| `digest mismatch` on fetch | the download doesn't match the release manifest | do not boot it; retry, and distrust the transport |
| pinned module behaves *new* | its import wasn't in the overlay (hand-copied, not vendored?) | vendor the closure — that's the whole reason `vendor` walks it |

## The surfaces, at a glance

| Surface | What |
|---|---|
| `pin.xon` | project manifest — `(root "DIR")` first listed wins; `(src "DIR")` where your code is; `(boot "FILE")` pins the boot |
| `--no-pin` | wrapper flag: ignore any manifest this run |
| `--boot FILE` | wrapper flag: boot FILE (a pinned amalgam) this run; overrides the manifest |
| `x-<tag>-<os>-<arch>.tar.gz` | a release's wrapper+engine+library, relocatable — the no-toolchain platform pin |
| `(Pin sync)` | vendor whatever `(src ...)` imports — the everyday verb |
| `(Pin check)` | verify the lock **and** audit for half-pins — the CI verb |
| `(Pin boot "vX.Y.Z")` | fetch, verify and record the release's amalgam |
| `(Pin closure 'name)` | dry run: the files a vendor would copy |
| `(Pin vendor "deps" 'name)` | copy one module's closure + write the lockfile |
| `(Pin verify "deps")` | recompute digests; overlay must equal the lock |
| `(Pin audit "deps" "src")` | name imports that fall through to the platform |
| `(Pin fetch "boot" "vX.Y.Z" 'xe)` | download + verify an amalgam, no recording |
| `<overlay>.lock.xon` | the overlay's integrity record (generated, beside it) |
| `pin.release.xon` | a release's digests + ISA fingerprint (published) |
| `(help Pin)` | the class's own documentation, in-session |
