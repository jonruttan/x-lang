# Scaling to Many Langs

[The Lang Contract](lang-contract.md) says what one lang is held to. This says
what has to be true for there to be twenty of them, and it exists because the
answers are different: nothing in the contract is wrong at six bundles, and
three things in it are O(N) by hand.

> **Status.** Rulings 1, 2 and 5 are built: the lang kit under
> `tools/lang-kit/`, the release-refs gate in four bundles (x-coreutils,
> x-logo, x-r5rs, x-r7rs), and `requires-lang`. Rulings 3 and 4, the
> pre-release bundle run and the pins in the registry, are not, and are still
> asked for.

## The problem

Six langs were published when this was written. The cost of the seventh is
not in the language. It is in everything around it:

**The scaffolding is a copy.** `tools/bundle.sh`, `tests/spec-gate.sh`,
`ci.yml`, `release.yml`, the `Makefile` and `tests/spec-runner.sh` are the
same files in every bundle, differing by the lang's name and its release
URL, and the hashes already show drift. Adding a lang means copying them.
Fixing a bug in one means a pull request per bundle, and the bug stays fixed
only in the ones that got it.

**One fact is written in many places.** The platform release a bundle
requires appears in `lang.xon`, `README.md` and `.github/workflows/ci.yml`.
A platform release is a hand edit in each of them, in every bundle, and the
count grows with the catalogue.

**The cross-repo gate runs every suite in sequence.** `check-langs` is the
right idea and it rides gates, not gates-fast, but `tools/contract/langs.x`
records what running the suites back to back does to the count: one
unchanged tree reported different failure counts on successive runs under
that load, with batches dying mid-run. The gate that exists to detect
regression is at the mercy of the machine it runs on, and the effect grows
with N.

**Not every bundle can report debt.** A bundle without
`tests/contract/known-failures.txt` lets its debt grow silently, which is
the condition the ratchet was built to end.

## What already scales

Worth stating plainly, because the rulings below build on it rather than
replace it:

| | catches | cost |
|---|---|---|
| `check-seam` | a rename in the platform breaking every lang | gates-fast |
| `check-langs` | a behaviour change the platform cannot see | six suites, gates |
| per-bundle CI | the bundle's own correctness, on a release matrix | per bundle |
| `requires-release` | running against an untested platform | a string compare |
| `requires-lang` | a lang's dependency on another lang | a string compare |

Four of the five ways the last generation rotted are closed by these. The
record in `langs.x` shows the fifth being caught in the act: the bundles
carried failures between them while x-lang was green, and pinning a newer
engine removed most of them without a line changing in any bundle.

## Ruling 1: the scaffolding is a pinned artifact, not a copy

The platform already publishes three things a consumer acquires rather than
copies — the engine, the boot amalgam, the library overlay. **The scaffolding
is a fourth.**

Nothing in the 12 lines that differ between two `bundle.sh` copies is
information `lang.xon` does not already carry. The manifest knows the lang's
name, its dialect, its required release and its required langs. A kit
acquired by pin and parameterized from the manifest reduces a new bundle to
the only two things that are actually its own: **the language, and its specs.**

This is the ruling that changes the slope. Adding a lang stops being "copy 450
lines and remember to update them"; fixing the release roller stops being six
pull requests.

The constraint it must respect: a bundle still has to build from a clean clone,
which is already gated. An acquired kit is exactly as legitimate as an acquired
engine, and no more — verified by digest, recorded in the manifest, and
vendored into the release tarball so an unpacked bundle needs nothing.

## Ruling 2: one source of truth per fact, held by a gate

> **Shipped** in x-r5rs and x-r7rs — see [What shipping it
> taught](#what-shipping-ruling-2-taught) below. Not yet in the other four.

`requires-release` in `lang.xon` is the truth about which platform a bundle was
built against. The README and the CI matrix should **derive** it, not repeat
it.

The enforcement already exists in another form: `check-path-literals` asserts
that a path is not nailed into a file that has no business knowing it. The same
rule applied to version literals — no release string outside the manifest —
turns a platform release into one line per bundle, which is small
enough for a bot to open as a pull request and a human to merge without
reading twice.

### What shipping Ruling 2 taught

The split is sharper than "derive it": there are two cases, and they want
different answers.

**Derive, where something can read the manifest.** A `prepare` job reads
`(requires-release …)` and emits the CI matrix; in x-r7rs it also supplies
the `x-r5rs` checkout ref. The release workflows do the same. This does not
guard a copy, it removes one, and with it the drift checks that existed to
catch the copies disagreeing.

**Gate, where nothing can.** A README is prose. `tools/check/release-refs.sh`
asserts that a version preceded by the name it belongs to is the declared
one. Three rules keep the scan honest: an issue reference such as
`x-lang#527` is not a release; a name owns a version only when no other name
or version stands between them, which is why the scan is in awk rather than
a regex; and a workflow may not pin a version literally, because `ref:` sits
on its own line, where no proximity test can pair it with its name.

## Ruling 3: arrange the checks by cadence, not by repository

The sequential six-suite sweep does not belong on every commit. What belongs
where is a question about **when the answer can still change the outcome**:

| cadence | where | what |
|---|---|---|
| per commit | x-lang | `check-seam` — the rename |
| per commit | x-lang | a load smoke per lang: does it boot and name itself? |
| **pre-release** | x-lang | the full bundle matrix, before the tag exists |
| per commit | bundle | its own suite and its ratchet |
| scheduled | bundle | against x-lang `main`, so drift is a red build |

The move that matters is **pre-release**. A bundle matrix run after tagging
reports history; run before, it can stop a release that would break six
downstreams — which is the same ruling the release workflows already follow
when they run a suite before rolling a tarball.

The load smoke is the cheap half of `check-langs`: a lang that no longer loads
is the catastrophic case, it is cheap to detect, and it does not need a
quiet machine to be true.

## Ruling 4: the registry carries pins, not just directories

`tools/contract/langs.x` is already the registry. It records where a bundle
sits on disk and what its suite last reported, and it is honest that those
counts are "against whatever revision of each bundle is checked out".

Adding the published pin URL to each row fixes three things at once:

- the pre-release matrix gets its input list,
- the counts can be measured against a **released** bundle rather than
  whatever happens to be in a working copy,
- and `x -l foo` gains something better to say than that it found nothing —
  it can name where `foo` comes from.

Discovery is not a nice-to-have at twenty langs. A user who has to know a URL
to install a lang is a user who only ever installs the langs they already knew
about.

## Ruling 5: a dependent lang is a lang that requires a lang

R5RS and R7RS are the first case, and no new concept was needed to express
the relationship: `x-r7rs` declares `(requires-lang "r5rs" "v0.2.0")` and the
platform arms the dependency's root before the dependent's own. A Python 2
beside a Python 3, or several related shells, falls out the same way.

**Resist a dependency mechanism.** The axes are already named and already
checked — a lang declares its dialect, and `check-dialect-cover` holds the
platform to all three. What grows with a large catalogue is the *matrix*
(lang × release), not the *vocabulary*. A new row in `lang.xon`
would have to be understood by every reader of every manifest, forever, to
express something two existing rows already say.

## What this does not solve

**The bundle matrix is O(N) somewhere, and this only moves it.** Twenty langs
is twenty suites before a platform release. The claim is that pre-release, in
CI, once per tag is the cheapest honest place to pay it — not that it becomes
free.

**A quiet machine is still a requirement for a trustworthy count.** Moving the
sweep so it no longer runs on every commit reduces how often that matters; it does not make
the count robust. A count produced under load says more about the load than
about the bundle.

**Nothing here retires a bundle.** A catalogue that only grows eventually
contains langs nobody runs, and the honest end state for one of those is a
recorded, archived bundle rather than a row that quietly fails forever.
