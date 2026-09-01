# Changelog

All notable changes to this project will be documented in this file.
This project adheres to [Semantic Versioning](http://semver.org/).

## [Unreleased]

**The exact tower is exact at every magnitude.** Rational arithmetic
silently answered wrong values once cross products passed 2^63 (two ~1e13
denominators multiply to ~1e26): the `%rat-*` internals used the raw C
binaries, which wrap. They now go through the public promoting operators,
and `%gcd` reduces by `%int%` instead of reconstructing `a - b*(a/b)` (the
reconstruction product wrapped for bigint-sized operands). Two bigint
defects fell out of the same probe: `%would-overflow-add?`'s negative
threshold itself wrapped for subtrahends past 2, promoting nearly every
negative subtraction; and demotion only ever fired for single-limb
results, so any bigint ≥ the limb base — including 17-19 digit literals
straight from the reader — stayed a *stealth bigint* that printed like an
int but failed `eq?` and raw slot ops (`str->number`'s own overflow verify
among them: an 11-digit all-nines parse raised a spurious "integer
overflow"). Subtraction gets its own exact `%would-overflow-sub?`, the
demotion window now spans every length that could round-trip, and both
bigint construction paths route through it. Pinned in
`tests/x/specs/ext/rational.spec.md` and `ext/bigint.spec.md`.

## [0.9.0] - 2026-08-31

**Logo left, and the platform grew the row that let it.** `apps/` is empty:
its only occupant is [x-logo](https://github.com/jonruttan/x-logo) now,
arriving green at 83 tests / 0 failed with its examples and its pty contract
intact. Minor rather than patch, and the reason is one seam addition —
`%lang-root`, the bundle's own directory — plus `%batch?` recovering the
meaning it is documented to have. Both are new surface a lang may rely on,
which is what a minor bump is for.

Removing a lang from `apps/` moves the payload fingerprint, so this release
*is* the extraction rather than a tidy that followed one. x-logo declares
`(requires-release "v0.9.0")` because nothing earlier can serve its viewer.

### Added

- **Logo left the tree, and is [x-logo](https://github.com/jonruttan/x-logo).**
  It was the last occupant of `apps/`, and the reason that directory exists —
  `-l` resolving `apps/NAME/run.x` was added for it. Its own README always
  described it as "a second surface language", which is a lang's job
  description, so [the lang contract](docs/lang-contract.md) named it as the
  obvious extraction the day that document was written.

  **It arrived green: 83 tests, 0 failed** — the same 83 that ran here as
  `lib/logo.spec.md`, against the same turtle kernel, through the bundle's own
  harness. The pty contract came too and reports what it always did (7 ok, 1
  known-fail), and the `examples/logo/ch1.logo` pin came with it. Nothing about
  the language changed; what changed is that it is now acquired, pinned, and
  run against a matrix of platform releases rather than only against the tip of
  this tree.

  **`apps/` stays, empty.** The second resolution step is documented behaviour
  and still gated; what left is its only occupant, not the mechanism. See
  [apps/README.md](apps/README.md) for what belongs there and what should be a
  bundle instead — the short version is that an app entry is self-booting and
  therefore nailed to this tree, so anything wanting its own version number
  wants to be a lang.

- **A bundle can find the data it ships: `%lang-root`** (`x.sh`, a `bundle`
  row in `tools/contract/seam.x`). `import` answers *where do my modules come
  from*, and a `./`-relative `include-once` reaches a sibling source file.
  Neither means *the bytes of that file*, and Logo is the first lang to need
  that — `serve.x` hands `viewer.html` to a browser.

  The three ways to do it without this row are all wrong in the same
  direction: a cwd-relative literal works only from the tree root, a path
  joined onto `%install-root` finds the *platform's* tree rather than the
  bundle's, and reading `%import-roots-cell` is a platform internal the seam
  does not cover. The first of those is not hypothetical — it is exactly how
  Logo's viewer came to be broken in every installed tree, which is the one
  environment nothing ran in.

  So the wrapper says it, once, because the wrapper is the only thing that
  ever knows: it is what searched `langs/*/lang.xon` and found the directory.
  Emitted for the bundle whose entry is about to run and never for a
  `(requires-lang …)` dependency — to the bundle that needs it, a required
  lang is a library.

  **The gate needed a bundle, so there is one.** `%lang-root` is bound only
  while a bundle is loaded, which is a third class beside `always` and
  `installed`, and a class nothing can probe is documentation rather than a
  contract. `tools/contract/bundles/seamprobe/` is nine lines whose only job
  is to be loaded: `check-seam` now asserts the name is absent from a bare
  `he`/`xe`/`rn` *and* present under `-l seamprobe`.

- **Arbitrary-precision decimal floating-point, the sixth tower stage**
  (`x/num/decimal.x`, class `Decimal`, literal suffix `d`). It exists because
  the tower had no exact answer for a decimal *fraction*. Bigint takes the
  integers as far as they go and float is a double, so `(+ 0.1 0.2)` is
  `0.30000000000000004` and always will be — 0.1 is not a binary fraction.
  `(+ 0.1d 0.2d)` is `0.3d`, exactly, and stays exact however long the sum
  runs.

  A value is a significand times a power of ten, stored canonically: trailing
  zeros are stripped and the exponent raised to match, so `1.50d` and `1.5d`
  are the same pair, zero has one spelling, and `=` is a pair compare rather
  than a walk. The significand is an ordinary exact integer, so it promotes to
  bigint on its own — the type is decimal *floating* point, not a fixed number
  of digits.

  **What rounds is stated, and it is nearly nothing.** `+`, `-`, `*` and `%`
  are EXACT: the significand grows to whatever the answer needs. `/` cannot be
  — 1/3 has no finite decimal — so division is the operation that rounds, to
  `(Decimal precision)` significant digits, half-even; `sqrt` rounds for the
  same reason. This is deliberately *not* Python's `decimal`, which rounds
  every operation to the context: a context that silently truncates an addition
  is a footgun in a language whose whole numeric story is that the tower widens
  rather than wraps.

  It sits above float in the promotion chain, and the reason is that the
  widening is exact rather than conventional: every finite double is a finite
  decimal, because `m * 2^-k` is `m * 5^k * 10^-k`. So `(Decimal from 0.1)` is
  `0.1000000000000000055511151231257827021181583404541015625d` — the double's
  true value, not its 17-digit short form — and a mixed pair promotes without
  inventing digits. Complex still absorbs decimal, as it absorbs every real.

  The literal takes a trailing `d` and only scores when the suffix is there, so
  it never contests a token the float reader wants: `1.5` is a float, `1.5d` is
  a decimal, and the four-character claim beats the three-character one on the
  same digits. `write` keeps the suffix, for the reason floats keep their point
  — a printed `1.5` would read back as a double. `(Decimal ->str x)` is the
  suffix-free text.

  `x/num/tower` carries it across all seven generics, and `x/num/decimal`
  registers rational and complex through the pact rather than importing them,
  so the module stands on bigint and float alone.

  **`ln`, `exp` and `log10` come with it, as series rather than as a door.**
  Float's twenty math methods are each one `dlsym`, because libm computes in
  doubles; nothing computes in 34-digit decimals, so these are implemented
  here. All three reduce the argument into a window where a series converges
  quickly, run at the precision plus ten guard digits, and round once at the
  end — `exp` by halving until the Taylor series is forty terms and squaring
  back (dividing a decimal by a power of two is exact), the logarithms by
  folding the significand into `[0.3, 3)` and running one shared `atanh`.
  They agree with the published constants to the last digit: `(Decimal exp
  1d)` is e to 34 places, `(Decimal ln 2d)` is 0.6931471805599453094172321214581766.

  Two decisions in there are worth naming. The fold window is `[0.3, 3)` and
  not the obvious `[1, 10)` because inside it the exponent is *zero*: an
  argument near 1, where `ln m` and `e·ln 10` would cancel completely and the
  answer's leading digits would be guard digits, never meets `ln 10` at all.
  And an exact power of ten answers `log10` from its own exponent, because
  canonical storage has already stripped it to a significand of 1 — `(Decimal
  log10 1000d)` is `3d`, not three followed by thirty-three zeros and a doubt.

  **Two rewrites underneath them, together a 75x.** `ln 2d` at 34 digits took
  9.8s when it first worked; it takes 0.13s.

  The first was rounding, and it made everything else faster too. Rounding a
  magnitude to N significant digits was `q = m / 10^(d-N)` with the
  remainder — two of bigint's *general* multi-limb long divisions, measured at
  **129ms per call** where the multiply feeding it took 3.5. Every series term
  rounds once, so that one line was the entire cost of a logarithm. A divisor
  *below* bigint's base is a single limb and takes its fast path, so the
  discarded digits now come off a limb's worth at a time. That alone took
  `ln 2d` to 0.9s, and `/`, `sqrt`, `round` and `rescale` ride the same path.

  The second was the series themselves, which no longer compute in decimals.
  A term is an integer at a fixed scale — `v` stands for `v · 10^S`, one `S`
  per series — so addition is integer addition with no alignment, no exponent
  arithmetic, no instance to build and canonicalise, and no rounding, and a
  term that divides down to zero has fallen off the working precision, which
  is the stopping condition for free. Only multiplication does anything: the
  product sits at `2S` and comes back with one drop. A term went from ~19ms to
  ~3.

  The scale is the accuracy argument, and the two series choose differently.
  `atanh` scales *relative* to its argument, so a `z` near zero — `ln` of an
  `x` near 1 — keeps a full working precision instead of being measured
  against a 1 it is nowhere near. `exp` scales absolutely, because its
  accumulator starts at 1 and stays within a factor of e of it; its squarings
  are the one place fixed point is wrong (each doubles the *magnitude*, which
  only an exponent can carry for free) and they stayed in decimals.

  Both rewrites were checked against the code they replaced rather than
  assumed: the rounder over 500 random and deliberately tie-heavy magnitudes,
  the series over 140 random arguments spanning 1e-40 to 1e3 including the
  near-zero scale case. No disagreement in either, and every published
  constant still lands on the same digits.

### Fixed

- **`%batch?` means "a file was supplied" again, for bundles too.** `banner.x`
  documents it that way and every dialect entry uses it that way, but the
  bundle path passes `--batch` unconditionally — it is what keeps the
  *dialect's* launcher quiet while the bundle loads on top — so every bundle
  saw `true` whether or not the user named a file.

  The two questions were the same question until bundles existed. x-sweet's
  `(unless %batch? (%banner))` has silently never fired for want of the
  distinction, and x-logo's entry has to choose between its REPL and its batch
  reader on exactly this fact: with the wrong answer it consumes the launcher
  `x.sh` appended and reads it as a Logo program, which is silent and prints
  nothing. `x.sh` now restores the flag's documented meaning after the dialect
  boots, rather than by withholding `--batch`, which is still doing its other
  job.

### Changed

- **The engine pin moves to x-engine-c v0.1.6**, and x-r7rs goes from 43
  failures to **27** without a line changing in it.

  v0.1.5 adds `(base def-global)`: an operative can define for its caller,
  whatever the frame depth. `def` decides global-versus-local by save-stack
  depth, so a `define` written as an operative — which Scheme's and Kernel's
  both are — binds in its own frame and loses the binding when that frame pops.

  The sixteen are all of `error`, `error objects` and `guard`. `guard` is the
  live case: R7RS `guard` and x's `guard` are different forms sharing a name,
  so providing one means shadowing the other, and shadowing interposes exactly
  the frame that broke the `eval!` workaround. x-r7rs changed nothing — it
  already preferred the primitive and fell back when it was absent.

  `tools/contract/langs.x` ratchets that budget to 27.

  **The pin names v0.1.6 rather than v0.1.5**, and the extra release is one
  line. v0.1.5 added the primitive to the engine's `isa.x` without regenerating
  its `x-engine.xon`, so it shipped the digest of the *previous* manifest and
  `check-engine-contract` refused it — the gate doing exactly its job, on the
  first pin bump that could reach it. v0.1.6 is that file regenerated; nothing
  in the built engine differs.

  `tests/x/fixtures/engine-min` grows the same row. The paper engine declares
  `core` and no more, `def-global` is tagged `spine`, and a group missing one
  coordinate is not a capability — so the fixture stopped claiming `core` the
  moment the vocabulary grew. `check-second-engine` predicted this in its own
  header, which is the argument for fixtures over remembering.

## [0.8.1] - 2026-08-30

`syntax-rules` works. The reader stopped claiming the dot, and x-r5rs went
green without a line changing in it.

### Changed

- **The engine pin moves to x-engine-c v0.1.4**, and x-r5rs goes green without
  a line changing in it — 667/9 to **667/0**.

  v0.1.4 stopped the dot being a token *kind*. It sat in
  `X_SEXP_LIST_CHARS_STR` beside the brackets, so the analyser scored it on
  sight: correct for `(` and `)`, which really are always single-character
  tokens, and false for `.`, which separates a pair only when nothing follows
  it. Every token *beginning* with a dot was taken whole as the separator, and
  the reader's internal marker was returned to the caller as a value — so
  `(first (rest (lit (a ... b))))` segfaulted on a raw C satom.

  All nine of x-r5rs's remaining failures were ellipsis patterns, and R5RS's
  macro layer is written entirely in them, so one reader fix moved every one.
  `tools/contract/langs.x` ratchets that budget to 0: a zero is a claim, not a
  hope, and it is what makes a tenth failure loud.

  The engine takes no view on `...` — it is a symbol the reader does not
  recognise and passes through, exactly like `.foo`. One reading changes with
  it: `(a.b)` is the symbol `a.b` rather than an improper list, which was an
  accident of the delimiter set rather than deliberate syntax.

## [0.8.0] - 2026-08-30

### Added

- **The lang kit: the platform ships a bundle's checks, as it already ships the
  spec runner** (x-lang#546). `tools/lang-kit/` installs to
  `share/x/tools/lang-kit`, beside `tests/spec-runner.sh` and outside the
  payload fingerprint for that file's own reason — the digest is library bytes
  and answers *which release is this*, while a tool ships with the wrapper and
  the engine.

  `docs/lang-contract.md` settled the ruling for the runner: **the platform
  ships it; bundles do not vendor it.** The runner was the first thing every
  bundle would otherwise have copied, and it is not the only one. Across the
  six published bundles `tools/bundle.sh` is 103 lines and differs between any
  two by exactly 12 — every one of them the lang's name or its release URL —
  and `tests/spec-gate.sh` differs by a single line of header comment.

  The first member is `release-refs.sh`, chosen because its evidence is the
  freshest rather than because it is the largest: it was written twice within a
  day, and the second copy needed three fixes backported the same afternoon —
  an issue reference mistaken for a release, a greedy regex window pairing a
  name with the wrong version, and a look-back that spanned a neighbouring
  pair. A seventh bundle would have been a seventh copy of all three.

  It is generic over the manifest rather than per bundle: the table of versions
  to check is read from `lang.xon` — `(requires-release …)` plus any
  `(requires-lang …)` — so one file serves a bundle declaring one and a bundle
  declaring two.

  **Two ways to reach it, and the second is not a convenience.** A bundle's
  specs job has already checked x-lang out; its contract job has not, and does
  not need to, because this check reads a manifest and greps a tree. Making a
  one-second text check depend on a built engine would be a regression dressed
  as consistency. So `X_LANG_KIT` names a checkout's `tools/lang-kit` directly,
  and everything else asks `x --share-dir` — the addressing the runner already
  uses, and the failure the contract calls "addressing, not sharing".

  **For bundle authors:** a bundle that sources the kit declares
  `(requires-release "v0.8.0")` or later. Earlier releases do not carry it, and
  the shim says so by name rather than failing obscurely.

### Fixed

- **`(Num expt b -1)` no longer takes the machine down** (x-lang#545). The
  parameter was documented "Non-negative integer exponent" and nothing checked
  it. A negative exponent never reaches the `(= exp 0)` base case — it walks
  *away* from zero — and every even step squares the base, so the recursion
  allocated bignums that doubled in width until memory was gone. That is what
  made it dangerous rather than merely wrong: a plain infinite recursion trips
  the spec runner's timeout, while this one exhausts memory first, and
  `alloc-limit!` is calibrated in objects, so a handful of enormous bignums
  reaches far more RAM than the object count implies.

  It was reachable by accident: `2 ** -1` is ordinary Python and `(expt 2 -1)`
  is ordinary Scheme, and any lang implementing exponentiation on top of
  `Num expt` inherited it.

  `expt` now raises `err:value` on a negative exponent, the same shape
  `Num isqrt` already used for a negative input. The doc stated the contract;
  this enforces it rather than changing it — a caller wanting Python's or
  Scheme's answer needs a float, which is the caller's decision to make and not
  a silent reinterpretation here.

## [0.7.1] - 2026-08-30

### Changed

- **The engine pin moves to x-engine-c v0.1.3**, and x-ash goes from unusable
  to two failures without a line changing in it. v0.1.2's
  `x_prim_make_token_base` segfaulted on the first character of any input:
  it assigned to the boolean singletons' *cells* rather than through them, and
  never created the read buffer `make_base` gives itself. An isolated tokenizer
  base is the one thing x-ash cannot do without, so nearly its whole suite was
  red for a reason that was never x-ash's.

  | | before | after |
  |---|---:|---:|
  | x-ash | 80 failed | **2** |

  x-ash's two are its own string readers, a bundle bug its README documents.

  v0.1.3 also names the buffer sizes it had scattered as bare literals — the
  reader's buffer was 256 bytes in `make-base` and 65536 in the CLI, filling
  the same field.

- **`tools/contract/langs.x` corrects two attributions and one number**, and
  the corrections are the point of a file whose budgets are supposed to be
  measured rather than transcribed.

  x-r5rs's 37 → 9 was credited to this pin. It was not the engine: v0.1.3
  changed four files, none of them the reader, and
  `src/x-token/sexp/list.c` is byte-identical to v0.1.2's. The 28 came from
  x-r5rs itself — R5RS §6.6 ports rewritten against `File` (21), and exactness
  under §6.2.5 (7). The nine that remain say so: they are the **ellipsis**
  group, which is exactly what a pair-dot fix would have removed.

  `(base def-global)` was described as shipping in v0.1.3. It is not in v0.1.3;
  it is proposed and unmerged.

  x-r7rs's budget moves 58 → **43**. 58 is what that suite reports when
  something else is running — an orphaned engine holding a core has made it say
  49, 58 and 247 for one unchanged tree, with batches dying mid-run.
  `check-langs` runs six suites in sequence, which is precisely that condition.
  Measured twice on a quiet machine it is 43, on both engines.

## [0.7.0] - 2026-08-29

0.6.0 let a lang leave the tree. This one is about langs that build on **each
other**, and about the platform noticing when it breaks one.

A lang can now name another in its manifest, at an exact version, and be
refused at startup rather than discovering the gap as an unbound symbol
somewhere inside itself. `make check-langs` runs every bundle's own suite
against this working tree, which is the first time anything here notices a
behaviour change a bundle cares about — measured when the gate was written:
x-lang green at 2590/0 while the six bundles carried 175 failures between them,
with nothing here saying so. And the two lines at the top of every lang
extraction — a second `(include "lib/x-core.x")` — no longer segfault, which is
the first wall a new bundle hits and the one that told it nothing.

`Indent` is the same story one layer down: Logo and x-sweet each owned a copy
of the indentation algorithm, disagreeing at the edges, and now drive one
module.

Minor rather than patch. A new public reader module, a new manifest row, a new
wrapper flag and a new gate — new surface of this size belongs in the minor
under the SemVer this file adheres to, and nothing published depends on what
changed underneath it.

### Added

- **`make check-langs` — every lang bundle's suite, against your working tree.**
  `check-seam` catches a rename in eight seconds and cannot catch anything else:
  a behaviour change, an arity change, a reader that scores a tie differently
  all leave this tree green while a bundle in its own repository breaks, and
  each bundle's CI runs on its own schedule against a *release*, so the break
  surfaces weeks later as somebody else's mystery. Measured when the gate was
  written: x-lang green at 2590/0 while the six bundles carried **175 failures**
  between them, with nothing here saying so. Budgets live in
  `tools/contract/langs.x` and may only shrink, the rule `percent-globals.x`
  runs on. Advisory about presence — a bundle not on the disk is announced and
  skipped, because this tree must build for someone who cloned nothing else —
  and strict about regression. Deep tier; `LANGS='krn sweet'` runs a subset and
  `X_LANGS_DIR` moves where bundles are found.

- **`Indent` — the stack discipline under indentation-sensitive grouping**
  (`lib/x/reader/indent.x`). Logo and x-sweet each owned a copy of it, reached
  by different routes and disagreeing at the edges; both now drive this one.
  Two layers: **measurement** (`advance` / `scan` / `measure`) answers what
  column a line begins at, and **the stack** (`make` / `feed` / `close-all`)
  answers what opened and what closed. `feed` returns zero or more `close`
  events followed by exactly one `open` or `same`, so no caller counts levels
  itself — the loop both previous implementations owned. The two policy
  questions the surfaces disagreed on are constructor parameters, not
  assumptions: the tab stop, and what a dedent matching no open level means
  (`open`, `close` or `error`). Defaults are SRFI-110's, which are also
  Python's. `advance` / `scan` / `measure` / `classify` are registered under
  catalog ns `indent` for per-character callers who must not dispatch, the
  discipline `x/reader/analyser`'s terminators already use. (#520)

- **A lang may require another, and `lang.xon` says so** —
  `(requires-lang "NAME")`. x.sh resolves it exactly as it resolves `-l`,
  depth-first and transitively with a cycle guard, and arms each required
  root *before* the requiring bundle's own — `import-path!` prepends, so a
  bundle still wins any name it shares with something it builds on. A
  missing lang is a refusal at startup naming what is wanted and who asked,
  rather than an unbound symbol somewhere inside it. Before this, x-r7rs
  found the x-r5rs it extends by probing sibling paths in two separate
  places, which recorded nothing about *what* was needed and would have been
  re-derived by every dependent. The same argument `(dialect ...)` already
  makes: a requirement belongs in the manifest. (#526)

- **A required lang may be pinned to an exact version** —
  `(requires-lang "r5rs" "v0.1.0")`, compared for **equality and never
  parsed**, as `(requires-release ...)` already is. Ordering and ranges would
  need a version algebra and, with it, a resolver; equality plus
  `--allow-lang-skew` is smaller and says what it means. What it compares
  against is **derived, not declared**: a bundle carries no version row of
  its own, because such a row can only be true at the one commit that gets
  tagged — before the tag the tree claims a release that does not exist, and
  after it every commit claims one it is not. Instead a bundle's
  `make install` and `tools/bundle.sh` stamp a `version` file from
  `git describe` and from the tag, the same split as this tree's own
  `$(X_RELEASE)` → `<lib>/contract/release`. A lang that reports no version
  is refused as its own case, because it means a checkout rather than an
  install and the fix is different. (#526)

### Changed

- **Logo's indent-to-blocks is an adapter now.** `apps/logo/indent.x` keeps what
  was ever Logo's — what a block is, and where the tokens go — and its
  `(indent-level . tokens-reversed)` stack and `%pop-to` are gone. Its two
  answers are stated rather than implied by a loop: a tab is one column (a tab
  stop of 1), and a dedent to a column no open block sits at opens a block
  there (`open`). `apps/logo/types.x` measures the leading run with the shared
  `scan`, which hands back the column and the end index separately — the loop it
  replaces stepped an index and returned it as a column, which is correct only
  while a tab is worth one. (#520)

### Fixed

- **A tab advances to the next tab stop; it does not add the tab width.**
  x-sweet advanced its column by 8 on a tab where SRFI-110 — and CPython, and
  every editor — advance to the next multiple of 8. Those differ whenever a tab
  is not first on the line: for `<space><tab>x`, +8 says column 9 and a tab stop
  says 8. Neither suite had a tab case in it, so nothing caught it in either
  direction. The shared module carries the corrected reading, and it subsumes
  Logo's answer rather than overruling it — the next multiple of 1 after n is
  n+1. (#520)

## [0.6.0] - 2026-08-28

The release that lets a surface language leave the tree. A **lang** — Kernel,
Scheme, Logo — can now be built, published, acquired, installed and run from
its own repository, and the platform is held by a gate to what it promises
one. The five 2024-era personalities rotted because nothing held either side
to anything; this is the machinery that would have caught all three ways they
died.

### Added

- **A lang is a pinned, verified artifact** — the third acquired thing, after
  the engine and the boot amalgams. `(Pin bundle "deps/langs")` reads a
  project's `lang.pin.xon`, downloads the tarball its `(bundle "sha256:…"
  "URL")` row names, digests it **before `tar` runs**, and publishes it only
  once the whole tree verifies. A mismatch quarantines the bytes as
  `.rejected` rather than deleting them. The terms both sides are held to are
  [The Lang Contract](docs/lang-contract.md). (#521, #533)
- **`x --install-lang URL`, with nothing cloned** — fetches a published
  `lang.pin.xon`, then the tarball it names, and installs to
  `<install-root>/langs/<name>`. Install and pin answer different questions
  and the contract now says so: an install is one unversioned copy for the
  machine and the prompt, a pin is a digest-frozen tree for one project. A
  failed upgrade leaves the working install untouched. (#534)
- **`-l NAME` runs an acquired lang** — the third resolution step after
  `lib/NAME.x` and `apps/NAME/run.x`. Unlike those, a bundle does not boot
  itself: the wrapper boots the dialect its `lang.xon` **declares**, arms the
  bundle's module root, and loads it on top — the shape `-F` has always had.
  So a bundle needs no root-relative literals at all. A dialect this tree
  cannot supply, and two bundles claiming one name, are refused before
  anything boots. (#530)
- **The seam gate** — `tools/contract/seam.x` declares the eleven names a lang
  may rely on, and `make check-seam` holds the running platform to them in
  every dialect. A lang lives in its own repository, so a rename here that
  drops `%repl-prompt` or `import-path!` breaks it silently while this tree
  stays green. Declared rather than derived, because a lang's call sites are
  not in this tree and never will be. (#531)
- **`(Sha256 hex-n s n)`** — the digest, with the length given. `hex` bounds
  itself by `Str8 length`, which has strlen semantics, so binary input digests
  as its leading fragment: a gzip whose fourth byte is a NUL digested as three
  bytes. Both engines were already length-driven and byte-accurate; only the
  derivation was narrow. The JIT's adoption check gained two binary vectors,
  since proving the two engines agree on text proved nothing about the case
  this was added for. (#524)
- **`x --share-dir` and `x --engine-path`** — a tool outside this repository
  can ask where x reads its tree from and which engine it runs, instead of
  guessing. The shared spec runner now installs to `<share>/tests/`, so a lang
  runs its own suite with the platform's runner rather than vendoring 865
  lines of it. (#514, #532)

### Changed

- **A personality is a lang** — 154 occurrences across 25 files. Nobody is
  involved, and the word was long for something the seam had been calling
  `%lang-name` all along. `surface` was unavailable: it is already
  load-bearing for the C surface the engine contract is built on, and taking
  it would give one word two concepts. The Linux `personality` syscall keeps
  its name, because it is the kernel's and not ours. (#530)
- **Acquired things live in `deps/`, not `build/`** — the engine, its sources
  and lang bundles. `build/` is what this project *produces*; none of these is
  built here, and filing them under output is why `engine` needed a symlink to
  be findable at all. Sixteen files reach the engine through `engine/` or
  `$(ENGINE_DIR)` and not one of them changed — the link's own promise, kept.
  (#533)
- **The heavy-spec default is sized to the box** — `SPEC_HEAVY_JOBS` is 2 only
  where there is memory for two big heaps (~13GB), 1 below 24GB, and 1 when
  the size cannot be established. The runner's own comment said to lower it on
  a small box; a default that is safe only when the caller remembers a comment
  is a note, not a guard. CI is unaffected: both legs set it explicitly.
  (#529)

### Fixed

- **Logo's viewer was broken in every installed tree** — `serve.x` read its
  template from a cwd-relative `"apps/logo/viewer.html"`, which resolves only
  when the cwd is the repo root. Every test and every developer run found it;
  no installed user did. The path-literal ratchet could not see it, because it
  matches `include` *forms* and a data path is neither — so that gate grew a
  section for app data paths. (#512)
- **`--share-dir` refused to answer from outside the tree**, which is the one
  thing it exists for. Mode detection is cwd-based by design, so from outside
  a checkout it took the installed branch and computed a `share/x` no checkout
  has. Found by the first lang to use it, which had worked around it by
  `cd`-ing to the wrapper's directory first. (#532)
- **The seam was missing the printer, the reader and `eval!`** — x-krn sets
  `%repl-print` on its first line of real work, and its `$define!` turns on
  `eval!`: 59 of 72 specs fail without it. The table had been written by
  reading what the platform *offers*; a lang reaches for what it *needs*.
  (#532)
- **A bundle tarball may have a top-level directory** — `git archive
  --prefix=NAME/` is how a publisher rolls one, and every tarball the feature
  was developed against was flat. Descended one level, and only when
  unambiguous. (#533)

## [0.5.2] - 2026-08-26

The first release shaped by a second engine: two undeclared assumptions
became declared capabilities, eight unwritten laws became written ones with
conformance checks, and a pinned project now runs the release it names
instead of reporting an errand.

### Added

- **A pinned project reaches for the release its lock names** — when the
  installed library is not the release a lock records, the wrapper no longer
  refuses with an errand: it fetches that release into a per-user cache
  (`$XDG_CACHE_HOME/x/releases`) — verified before unpacked, staged and
  published atomically — and hands the whole invocation to it. Fetching asks
  consent: `--fetch-release`, or one question on a terminal. Nothing global
  changes; the re-exec'd wrapper runs its own guards against its own matched
  tree, and `--allow-release-skew` still means "run THIS install". The
  refusal survives for the unresolvable cases and now names the flag. (#499)
- **A version file may import a lower version of itself** — a higher major
  can be a subclass of the lower one rather than a copy: while a version
  file's body is mid-load, its own self-name import resolving strictly lower
  loads that file by path, once, with the higher `provide` shadowing the
  lower. Chains (`@3` over `@2` over `@1`) fall out of the same rule; outside
  a self-load the loud version contract is unchanged. (#503)
- **The native-extension lanes are declared capabilities** — `native/cc` (the
  engine ships its C headers, so `x/tool/compile.x` can build against them)
  and the jit/asm lane are now stated in the engine contract instead of
  assumed. The compiled tower falls back to the interpreted one on an engine
  that hosts no C, and the jit/asm specs skip against an engine that never
  claimed the lane — both assumptions had silently encoded "the engine is
  x-engine-c".
- **The engine laws** — behavioural laws the library depends on that the
  contract's resolve-checks could never see (a row can resolve and still do
  nothing), each one found broken by a second engine. Stated in
  `docs/engine-laws.md` and checked by conformance: the stamping law (a value
  carries its base's type), the evaluator's state rides the base, evaluation
  and application are type handlers, the callable state spine, and the rest.

### Changed

- **One naming scheme for every engine** — the glossary is the ruling record:
  type behaviour is a *handler* (the private 'hook' retires), the type is
  neither a "tree" nor a "struct", and the `-ts` suffix retires with the
  phrase it abbreviated. The engine contract's covers rows use the ISA's own
  spellings. (#497, #498)

### Fixed

- **Logo's alist prune walks the type-alist route, not the C layout** — the
  raw `first`/`rest` walk encoded x-engine-c's base spine (the one thing
  decision L1 says a caller must not do) and pruned through the wrong cell on
  any other layout. The `(B cell 'type-alist)` door resolves whichever engine
  is underneath.

## [0.5.1] - 2026-08-25

### Fixed

- **`(Pin boot "v0.5.0")` failed for every project** — `pin: unknown
  release-manifest form`. v0.5.0's `pin.release.xon` carries the
  `(engine-release …)` row the release script now emits, but the pin
  tool's manifest parser predated the row and refused the whole
  manifest. The parser reads it now, optional like `layout` — a manifest
  without the row still parses, a missing value reads back as nil. And
  since the pin tool ships inside releases, the fix has to *be* a
  release: v0.5.0 itself cannot be pinned, and this line exists so the
  v0.5.x series can be.

## [0.5.0] - 2026-08-24

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

- **The C engine is a separate repository, and this tree carries no engine at all** — [x-engine-c](https://github.com/jonruttan/x-engine-c), with its own version line and published releases. `make engine` reads `tools/engine/engine.pin.xon` — a declared release tag plus one artifact row per platform, digests taken from the release's own sha256 sidecars — fetches the tarball, verifies it, and unpacks it; `make engine-source` clones the sources instead for platforms with no published artifact. `x-bin` is copied to this repo's root as before, so the wrapper, the spec runners and every `tools/check/*.sh` script are unchanged. This release pins [x-engine-c v0.1.2](https://github.com/jonruttan/x-engine-c/releases/tag/v0.1.2), whose v0.1.1 and v0.1.2 lines are this release's own finds: a prim walked off a dotted argument list (#487) and the FFI called a nil function pointer (the #171 class) -- both uncatchable SIGSEGVs, both now catchable raises.

  The contract manifests travel **with the engine**, in its `tools/contract/`: an engine's description of itself is stronger there than as a copy the library keeps, because a private layout copy is right about *some* engine and not necessarily the one running. `lib/x-core.x` includes `base-paths.x` and `obj-layout.x` from there as the first things it loads, and `pin.x` reads `isa.x` at runtime. `check-isa`, `check-obj-layout` and `check-base-paths` are the engine's own gates now; `check-prim-coverage` stays here, because most primitives are reachable only through the library and the honest answer needs both spec suites.

  The engine declares its own release: `x -V` prints the library's release and the engine's side by side, and a released engine ships no C — the C-suite gates announce-and-skip here, its own repository having ratcheted them on the build that produced the artifact.

- **x-lang reaches its engine through one path** — `engine`, a `.gitignore`d symlink in the repo root that `make` points at whatever the tree builds against: a fetched release, a checkout named by `X_ENGINE_DIR`, or any unpacked engine directory. Everything downstream uses that one spelling — the boot's contract includes, the JIT's `-I` flags, the gates, the conformance runner — so a second implementation needs no edit to `lib/`. An engine directory either has sources (built here) or ships a binary (used as-is); the build asks which rather than assuming. Once pointed somewhere explicitly the link stays there, and `make install` stamps the ISA fingerprint from the engine it actually built against, not from a hardcoded path.

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

- **A dotted argument list raises instead of killing the interpreter** (#487) — `(= 1.5 1.5)` segfaulted, uncatchably, from ordinary source text: with no float module loaded `1.5` reads as the dotted pair `(1 . 5)`, and a primitive walking its argument spine tested only for the *proper* ending. A proper list bottoms out at nil; an improper one bottoms out at an atom, which was then read as a pair — the tail integer's value word dereferenced as a pointer. No `guard` could catch it, because a prim call never enters the applicative walk #69 guarded. Which primitives crashed was decided by the library, not the engine: `+` and `<` raised cleanly because the tower shadows them, while the unshadowed `%isa-keep` entries `=`, `eq?` and `same?` reached C directly. Fixed in the engine ([x-engine-c#5][e5]) by hoisting #69's own structural test into one guard every C spine walker shares, and picked up here by pinning [v0.1.1][e011]. A satisfied arity still ignores a junk tail, and a non-pair *argument* remains the unchecked contract it always was.

[e5]: https://github.com/jonruttan/x-engine-c/pull/5
[e011]: https://github.com/jonruttan/x-engine-c/releases/tag/v0.1.1

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
- **Release engineering** — every tag now publishes per-platform prebuilt binary tarballs (Developer ID signed and notarized on macOS) beside the dialect amalgams, each with a coreutils-checkable `.sha256` sidecar, so a release runs with no toolchain and no compile. `bootstrap.sh` covers the from-source path in one command: clone, acquire the engine the pin names, build it (a ~4-second C89 compile), and optionally install under a user prefix.

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
