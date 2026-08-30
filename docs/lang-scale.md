# Scaling to Many Langs

[The Lang Contract](lang-contract.md) says what one lang is held to. This says
what has to be true for there to be twenty of them, and it exists because the
answers are different: nothing in the contract is wrong at six bundles, and
three things in it are O(N) by hand.

> **Status: Ruling 2 is shipped in two bundles; the rest is proposal.** The
> measurements are real and reproducible; the unshipped rulings are arguments.
> Each section says where it stands.

## The problem, measured

Six langs are published — `x-ash`, `x-krn`, `x-python`, `x-r5rs`, `x-r7rs`,
`x-sweet`. The cost of the seventh is not in the language. It is in everything
around it:

**The scaffolding is a copy.** `tools/bundle.sh` is 103 lines in all six
bundles and differs between any two of them by exactly **12 lines — every one
of them the lang's name or its release URL**. `tests/spec-gate.sh` is 100 lines
in the three that have it and differs by **two comment lines**. `ci.yml`,
`release.yml`, `Makefile` and `tests/spec-runner.sh` are the same story at
61–148 lines each.

That is 450–550 lines per bundle, ~90% of it identical, and the hashes
already show drift. Adding a lang means copying it. Fixing a bug in it means
six pull requests, and the bug stays fixed only in the ones that got the PR.

**One fact is written in eighteen places.** `v0.7.0` appears in about three
files per bundle — `lang.xon`, `README.md`, `.github/workflows/ci.yml`. A
platform release is therefore 18 hand edits across 6 repositories today and 60
across 20 tomorrow. This is the cost that is already being felt.

**The cross-repo gate runs every suite in sequence.** `check-langs` is the
right idea and it is on the deep tier, but `tools/contract/langs.x` documents
what running six suites back to back does to the measurement: one unchanged
x-r7rs tree reported 49, 58 and 247 failures under that load, with batches
dying mid-run. The gate that exists to detect regression is at the mercy of the
machine it runs on, and the effect grows with N.

**Half the bundles cannot report debt.** `x-ash`, `x-r5rs` and `x-r7rs` carry
`tests/contract/known-failures.txt`; `x-krn`, `x-python` and `x-sweet` do not.
Their debt can grow silently, which is the condition the ratchet was built to
end.

## What already scales

Worth stating plainly, because the rulings below build on it rather than
replace it:

| | catches | cost |
|---|---|---|
| `check-seam` | a rename in the platform breaking every lang | ~8s, fast tier |
| `check-langs` | a behaviour change the platform cannot see | six suites, deep tier |
| per-bundle CI | the bundle's own correctness, on a release matrix | per bundle |
| `requires-release` | running against an untested platform | a string compare |
| `requires-lang` | a lang's dependency on another lang | a string compare |

Four of the five ways the last generation rotted are closed by these. The
measurement in `langs.x` shows the fifth being caught in the act: six bundles
carried 175 failures between them with x-lang green at 2590/0, and pinning
x-engine-c v0.1.3 took that to 69 without a line changing in any bundle.

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
shape applied to version literals — no release string outside the manifest —
turns a platform release from 18 edits into one line per bundle, which is small
enough for a bot to open as a pull request and a human to merge without
reading twice.

### What shipping Ruling 2 taught

The split turned out to be sharper than "derive it": there are two cases, and
they want different answers.

**Derive, where something can read the manifest.** A `prepare` job reads
`(requires-release …)` and emits the CI matrix; in x-r7rs it also supplies the
`x-r5rs` checkout ref. Both bundles' release workflows do the same. This does
not guard a copy, it *removes* one — and with it the drift checks that existed
to catch the copies disagreeing.

**Gate, where nothing can.** A README is prose. `tools/check/release-refs.sh`
asserts that a version preceded by the name it belongs to is the declared one.

Three bugs, and where they came from is the useful part:

- Matching any version on a line naming x-lang fired on a line carrying
  `x-lang#527` and an **engine** version. An issue reference is not a release.
- Two versions on one line broke the regex outright: POSIX has no lazy
  quantifier, so a greedy window steps over the near version to pair a name
  with the far one. This is what forced the scan into awk.
- **CI caught the third on the gate's own header.** A flat look-back still
  spans a neighbouring pair. The README saying the same phrase *passed*,
  because its markdown padding pushed the name out of the window — it was
  right by luck. A name owns a version only when none stands between them.

**A workflow may not pin a version literally**, which covers what the scan
structurally cannot: `ref:` sits on its own line, so no per-line proximity test
can pair it with its name. Forbidding the shape was smaller than teaching the
scan about YAML.

**The cost is now visible.** The same file exists twice, and the second copy
needed all three fixes backported the day it was written. That is Ruling 1's
argument in miniature, which is why the other four bundles are deliberately
still waiting.

**Found in passing:** these workflows fire `push` only on `main`, so a
feature-branch commit is tested only if the `pull_request` event lands. One
did not, and the PR showed passing checks belonging to an earlier commit.
Green against the wrong revision is its own small version of the failure this
document is about.

## Ruling 3: tier the checks by cadence, not by repository

The sequential six-suite sweep does not belong on every commit. What belongs
where is a question about **when the answer can still change the outcome**:

| cadence | where | what |
|---|---|---|
| per commit | x-lang | `check-seam` — the rename, in seconds |
| per commit | x-lang | a load smoke per lang: does it boot and name itself? |
| **pre-release** | x-lang | the full bundle matrix, before the tag exists |
| per commit | bundle | its own suite and its ratchet |
| scheduled | bundle | against x-lang `main`, so drift is a red build |

The move that matters is **pre-release**. A bundle matrix run after tagging
reports history; run before, it can stop a release that would break six
downstreams — which is the same ruling the release workflows already follow
when they run a suite before rolling a tarball.

The load smoke is the cheap half of `check-langs`: a lang that no longer loads
is the catastrophic case, it is detectable in a second per bundle, and it does
not need a quiet machine to be true.

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

## Ruling 5: a variant is a lang that requires a lang

R5RS and R7RS are the first family, and no new concept was needed to express
the relationship: `x-r7rs` declares `(requires-lang "r5rs" "v0.2.0")` and the
platform arms the dependency's root before the dependent's own. A Python 2
beside a Python 3, or a family of shells, falls out the same way.

**Resist a variant mechanism.** The axes are already named and already
checked — a lang declares its dialect, and `check-dialect-cover` holds the
platform to all three. What grows with a large catalogue is the *matrix*
(lang × release), not the *vocabulary*. A new kind of thing in `lang.xon`
would have to be understood by every reader of every manifest, forever, to
express something two existing rows already say.

## What this does not solve

**The bundle matrix is O(N) somewhere, and this only moves it.** Twenty langs
is twenty suites before a platform release. The claim is that pre-release, in
CI, once per tag is the cheapest honest place to pay it — not that it becomes
free.

**A quiet machine is still a requirement for a trustworthy count.** Moving the
sweep off the per-commit tier reduces how often that matters; it does not make
the measurement robust. The 49/58/247 spread stands as a warning about any
number produced under load.

**Nothing here retires a bundle.** A catalogue that only grows eventually
contains langs nobody runs, and the honest end state for one of those is a
recorded, archived bundle rather than a row that quietly fails forever.
