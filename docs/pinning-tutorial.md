# Pinning, step by step

A walkthrough of pinning for project authors: setting up a new pinned
project, retrofitting an existing one, daily work, and pinning the
platform itself. The reference lives in [modules.md](modules.md)
("Pinning"); this page is the path through it. Every command and output
shown here was run as written. (`x` below is the installed command; in
a repo checkout spell it `sh x.sh`, run from the repo root.)

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

Say `myproj/` will depend on `x/type/dict` and must keep today's dict.

**1. Vendor the module.** From the repo (or an installed x), start a
*fresh* session and import the pin tool *first* — the tool snapshots
the boot floor when it loads, so nothing you imported earlier can
distort what it considers pinnable:

```
$ x
> (import x/tool/pin)
> (Pin vendor "myproj/deps" 'x/type/dict)
("x/type/dict.x" "x/type/hash.x")
```

Vendor copied **two** files, not one: `dict.x` and its import
`hash.x`. That is the point — vendoring is *closure-wise*. A lone
vendored module would still resolve its own imports against the live
platform and silently mix old code with new dependencies. (Everything
else dict imports is boot floor under this dialect, so it stays with
the platform.)

The overlay now looks like:

```
myproj/deps/
├── pin.lock.xon         ; written by vendor: sha256 per file
└── x/type/
    ├── dict.x
    └── hash.x
```

**2. Declare the manifest.** One file, one form:

```
$ cat > myproj/pin.xon
(root "deps")
```

`pin.xon` is **xon** — x object notation: data read with the ordinary
reader and never evaluated. `(root "deps")` adds `myproj/deps/` as an
import root ahead of the platform library. That's the entire manifest
vocabulary today.

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

**4. Commit the pin.** `pin.xon`, `deps/` — lockfile included — go in
your project's version control. They *are* the pin.

## Retrofit an existing project

You have a working project and want to freeze what it uses today.

**1. Inventory your imports.** Grep is honest enough:

```
$ grep -rh "^(import " myproj --include="*.x" | sort -u
(import x/type/dict)
(import x/type/set)
(import x/core/list)
```

**2. Ask what each would pin.** `Pin closure` is the dry run of
`vendor` — same walk, no copies:

```
> (import x/tool/pin)
> (Pin closure 'x/type/dict)
("x/type/dict.x" "x/type/hash.x")
```

**3. Vendor the non-floor ones.** A boot-floor import needs no
vendoring and `vendor` will tell you so by refusing:

```
> (Pin vendor "myproj/deps" 'x/core/list)
*** ERROR: pin: unpinnable (boot floor): x/core/list
```

That error is information, not failure: `x/core/list` ships inside the
dialect's boot — under *this* dialect your program always gets the
platform's copy, and freezing it means a platform pin (below). Vendor
the rest:

```
> (Pin vendor "myproj/deps" 'x/type/dict)
("x/type/dict.x" "x/type/hash.x")
> (Pin vendor "myproj/deps" 'x/type/set)
("x/type/set.x")
```

Repeated vendors into one overlay merge cleanly — the lockfile upserts
per file.

**4. Manifest, run, verify** — exactly as in the fresh-project steps:
write `(root "deps")` into `myproj/pin.xon`, run your program, look for
the `pinned:` line. Then prove the overlay is intact:

```
> (Pin verify "myproj/deps")
3
```

Three files checked against the lockfile, tree exactly matching. You
are pinned.

## Daily work

- **The notice is your dashboard.** Every pinned run prints
  `pinned: <path>` to stderr. No line, no pin — check where you ran
  from and where `pin.xon` lives.
- **Compare against the live platform** with one flag: `x --no-pin -f
  main.x` runs as if the pin didn't exist. The fastest answer to "is
  this bug ours or did the library move?"
- **Update a pin deliberately.** There is no auto-update: re-vendor
  from the platform you now want (`(Pin vendor "deps" 'x/type/dict)`
  again, in a fresh session), rerun your tests, commit the new
  `deps/`. The lockfile diff *is* the upgrade review.
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
amalgam. Every release tag publishes each dialect's full boot as one
self-contained file, plus `SHASUMS` and `pin.release.xon` (per-file
digests and the **ISA fingerprint**: the digest of the C-surface
manifest the amalgams were built against).

Fetch and verify in one step:

```
> (import x/tool/pin)
> (Pin fetch "boot" "v0.4.0" 'xe)
pin: verifying boot/xe.x (pure x-lang sha256; an amalgam takes minutes)
pin: isa fingerprint matches this tree
"boot/xe.x"
```

Be warned about the honest cost: the digest is pure x-lang and an
amalgam takes it *minutes* (tracked for improvement in #123). No curl
on the machine? `fetch` prints the URLs and stops — download by hand,
then check with coreutils beside the files: `sha256sum -c SHASUMS`.

Run the pinned platform with the direct pipe (an amalgam has zero path
literals):

```
$ cat boot/xe.x main.x | ./x --batch
```

Read the fingerprint line for what it is: **matches this tree** means
your current engine speaks the amalgam's C contract; **DIFFERS** means
the platform has drifted since that release — not an error, but your
pinned amalgam should run against its own release's engine, not
today's build.

## When something looks wrong

| You see | It means | Do |
|---|---|---|
| no `pinned:` line | probe found no `pin.xon` walking up from the program | check the manifest's location; remember the REPL probes the *cwd* |
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
| `pin.xon` | project manifest — `(root "DIR")`, first listed wins |
| `--no-pin` | wrapper flag: ignore any manifest this run |
| `(Pin closure 'name)` | dry run: the files a vendor would copy |
| `(Pin vendor "deps" 'name)` | copy the closure + write the lockfile |
| `(Pin verify "deps")` | recompute digests; overlay must equal the lock |
| `(Pin fetch "boot" "vX.Y.Z" 'xe)` | download + verify a released amalgam |
| `pin.lock.xon` | the overlay's integrity record (generated) |
| `pin.release.xon` | a release's digests + ISA fingerprint (published) |
| `(help Pin)` | the class's own documentation, in-session |
