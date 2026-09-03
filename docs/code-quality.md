# Code Quality Criteria

What counts as a defect in `.x` source, how each is measured, and what the
fix is. Every criterion here was checked against the corpus and, where it
makes a performance claim, benchmarked. Several plausible rules were tested
and rejected; they are listed too, so they do not come back.

Scope: the first-party `.x` corpus across x-lang and the language bundles —
340 files, 69,227 lines, 4,491 top-level definitions, measured 2026-09-02.
Vendored `deps/` and generated `build/` trees are out of scope.

## Start here: `match` is the multi-way conditional

The corpus is written in deeply nested `if`. Corpus-wide: **7,697 `if`
against 71 `match`**, and `match` appears in only 23 of 340 files.
`x-python/runtime.x` has 1,167 `if` and zero `match`.

There is a good reason for avoiding `cond`, `and` and `or` — see below — and
that reason got generalised into "nest `if`". That generalisation is wrong.
`match` is an **engine primitive**; `if` and `let` are *derived from it*
([`lib/x/core/control.x`](../lib/x/core/control.x)), and it sits in the ISA
spine. It evaluates clause tests in the engine until one is truthy, with no
per-arm frame — so a flat `match` is *cheaper* than the nested `if` chain it
replaces, as well as being flat.

Measured, 40 arms over an integer key, 10,000 lookups, xenon dialect:

| form | time | depth |
|---|---|---|
| nested `if` ladder | 896,834 µs | 40 |
| **`match`** | **604,905 µs** | **1** |
| `Dict get` | 3,082,385 µs | 1 |

`match` is **1.5× faster than the nested `if` ladder** and 5× faster than a
`Dict`. This is the highest-value change available in the corpus: it is a
win on clarity and on speed at the same time, everywhere, with no tradeoff
to weigh.

Shape:

```x
(match
  ((= c 40) 'lparen)
  ((= c 41) 'rparen)
  (#t       'other))     ; (#t …) is the else clause
```

**One thing to verify before applying it in tokenizer callbacks.**
[`contributing.md`](contributing.md) bans `cond` and `convert` there, to
avoid GC corruption, and prescribes "nested `if` and direct C primitives".
`match` *is* a direct C primitive, so the ban should not extend to it — but
that is an inference, not a tested fact. Confirm it under AddressSanitizer
before converting a reader or tokenizer callback.

## Why not `cond`, `or`, `and`

Unlike `match`, these are **interpreted operatives that `eval` each arm**,
and their cost is documented in the source:

- [`lib/x/core/boolean.x`](../lib/x/core/boolean.x) — `and`/`or` walk arms
  through `eval`; the arm rides a parameter because a `let` cost ~170
  objects per `or` arm.
- [`lib/x/core/syntax.x`](../lib/x/core/syntax.x) — `cond`'s previous body
  "allocated ~3,000 objects per cond EVALUATION", and `cond` runs everywhere
  in `lib`.

So: reach for `match`, not `cond`. The existing avoidance of `cond` was
correct; the conclusion drawn from it was too broad.

## Tier 1 — structural

### 1.1 Multi-way dispatch on one variable → `match`

A chain of `(if (test k …) … (if (test k …) …))` branching on **one
variable** is a multi-way conditional written as a tower.

**Threshold:** 4 or more arms. There is no `hot` exemption: `match` is
faster. Hot code is a reason to convert *first*, not to skip.

A chain is not ended by an arm whose test is an inlined `or` over the same
variable — `(if (Str8 =? n "a") #t (Str8 =? n "b"))` still selects one arm of
the same dispatch, and the linter counts through it. A compound over two
*different* variables is a real decision and does end the chain.

**Worst cases, measured:** `%py-op-start?` (16 arms), `%py-esc-at` (12),
`%py-str-attr` (26, and string-keyed — see 1.2), `special?` in
`x-make/expand.x` (9), `%cc-escape` (8), `%py-format-spec` (8).

### 1.2 …unless the keys are strings and numerous → table

`match` and `if` both compare arms linearly. When each arm costs a *string*
comparison rather than a free C `=`, that linear walk dominates and a hash
lookup wins. Measured, 25 arms over a string key, 4,000 lookups:

| form | time |
|---|---|
| nested `if` ladder | 7,316,704 µs |
| `match` | 6,896,734 µs |
| **`Dict get`** | **2,748,768 µs** |

**Threshold:** ≥15 arms **and** string keys → build a `Dict` once at load.
Below that, or with integer/character keys, `match` wins — the same `Dict`
was 5× *slower* than `match` on integer keys.

Confirmed working in the default (helium) dialect:

```x
(import x/type/dict)
(def %str-attrs (Dict make 32))
(%str-attrs set! "upper" (fn (_ s) (Str8 upcase s)))
(def %py-str-attr (fn (_ s name) (%str-attrs get name)))
```

Note `set!`, not `set`. A miss answers nil, which is already the
"no such attribute" path.

Exactly one definition in the corpus meets this bar: `%py-str-attr`, 26
string arms — every `"".upper()` in a Python program walks it. Every other
ladder found is keyed on characters or integers and wants `match` instead.
**Check the key type before converting** — this is exactly where a plausible
rule goes wrong, and the linter reports the two cases as different kinds so
the distinction cannot be lost.

### 1.3 Length and depth together, never either alone

Long-and-flat is fine: 17 definitions exceed 60 lines at depth ≤8, and they
are data tables (`x86_64-syscall-names`, `%arm64-table`, `%isa-catalog`).
Splitting those makes them worse.

Deep-and-short is usually fine: 279 definitions sit at depth ≥12 under 40
lines, mostly tight recursive walkers.

**Threshold:** depth ≥12 **and** ≥500 nodes — **16 definitions**.

Size is counted in **nodes, not lines**. The linter reads forms as data and
has no line numbers, and nodes are the better measure anyway: density across
the findings runs from 4.8 to 9.7 nodes per line, so a line count is partly
measuring the formatter. Quoted data counts as one node — a literal table is
not something the reader holds — but an inner `def` counts in full. Bodies
here are written as runs of inner-`def` bindings (`%cc-lower-loop` has
eighty), and an early version that skipped their subtrees scored that
377-line function at almost nothing.

**The 500 is calibrated, not guessed.** At 250 the rule found 83
definitions — a smooth decay with no natural gap, median 349 — and the low
end is not defective: `%sh-expand-dollar` (`x-ash/eval.x`, 15d/266) uses
`cond`, keeps its two helpers local in a `let`, and says why in a comment.
Depth does not separate that from `%cc-lower-loop`, which is the same 15 deep
and seven times the size. **Size is the discriminator; depth only excludes
the flat data tables.** A report that flags good code is one people learn to
skip.

**The 16, worst first:**

| definition | file | depth | nodes |
|---|---|---|---|
| `%cc-lower-loop` | `x-cc/build.x` | 15 | 1824 |
| `%py-str-attr` | `x-python/runtime.x` | 36 | 1471 |
| `%py-format-spec` | `x-python/runtime.x` | 26 | 1288 |
| `%cc-fold-stmts` | `x-cc/build.x` | 20 | 958 |
| `%build-class` | `x-lang lib/x/type/class.x` | 22 | 877 |
| `%py-strformat-kw` | `x-python/runtime.x` | 16 | 811 |
| `%py-format` | `x-python/format.x` | 13 | 753 |
| `%interp-forms` | `x-lang lib/x/reader/lit-reader.x` | 15 | 707 |
| `%cc-lower-e` | `x-cc/build.x` | 20 | 668 |
| `%cc-macro-subst` | `x-cc/lex.x` | 19 | 613 |
| `%cc-extract` | `x-cc/build.x` | 22 | 610 |
| `%dec-parse` | `x-lang lib/x/num/decimal.x` | 20 | 599 |
| `%awk-p-primary` | `x-awk/parse.x` | 14 | 553 |
| `%py-fmt-one` | `x-python/format.x` | 13 | 549 |
| `%cc-lex-go` | `x-cc/lex.x` | 21 | 539 |
| `%sha-jit-make` | `x-lang lib/x/codec/sha256-jit.x` | 12 | 514 |

**Fix:** apply 1.1 first — some of the depth *is* ladder, and `%py-str-attr`
appears on both lists. What remains, extract as named top-level `%`-helpers
(not inner `def`; see 2.4).

### 1.4 Duplicated bodies

Repeated normalised blocks of 6+ lines: present within `x-ash/eval.x` and
`x-awk/lex.x`, and across bundles — `x-awk/eval.x` and `x-cc/eval.x` share
one.

**Fix inside a bundle:** extract a helper. **Across bundles:** it belongs in
`lib/`, or it is coincidence — two tokenizers that skip whitespace the same
way are not sharing a concept. Check before moving.

### 1.5 Private re-implementation of a library name

[`lib/x/tool/lint.x`](../lib/x/tool/lint.x) defines its own `%length` and
`%last`. Reach for `apropos` before writing a helper.

**Exemption:** the boot layer, which cannot import what does not exist yet,
and any helper whose comment states why the library version is wrong here.
State it; do not leave the reader guessing.

## Tier 2 — noise

Mechanical, no performance dimension, no judgment required.

### 2.1 `(- 0 N)` for a negative literal

73 occurrences across 14 files. The reader takes `-1` directly and
`(eq? -1 (- 0 1))` is `#t` — verified. `(- 0 1)` is a function call standing
in for a literal.

### 2.2 `(if (not X) A B)`

261 occurrences across 59 files. Write `(if X B A)`, or `unless` when there
is no else arm. `not` is an interpreted predicate, so the inverted `if` is
shorter *and* cheaper.

### 2.3 `first`/`rest` chains

464 chains of `(first (rest (rest …)))`; 188 are three or more `rest` deep.
Past two levels the reader is counting parens to recover an index. Use an
indexed accessor, or destructure once into named locals at the top of the
body.

### 2.4 `def` inside a body

An inner `def` in tail position binds **globally** — `lint.x` already warns
(`%lint-leak!`), and a body-level `(def lit …)` has clobbered the quote
operative. It also invites duplication: two branches of `%py-str-attr` each
define their own `go`.

**Fix:** lift to a top-level `%`-helper, or bind with `let`.

## Tier 3 — cold code only

### 3.1 Hand-inlined `or` and `and`

`(if a #t (if b #t c))` is `(or a b c)` spelled out — 137 occurrences across
22 files.

Unlike Tier 1, this one has a real tradeoff: `or`/`and` are interpreted and
cost per arm, so in an eval loop or per-character tokenizer the inlined form
is correct. In CLI parsing, error formatting, or setup code it is noise.

Mark the deliberate cases (below); unmarked occurrences are findings.

## The `hot` marker

The performance justification for a flat form already lives as a comment
beside the code. Make it machine-readable rather than keeping a list
elsewhere that goes stale — a duplicated fact is a bug here:

```x
; lint: hot -- runs per input byte; an interpreted or costs ~170 objects/arm
(def %py-lex-char
  (fn (self s i n) …))
```

`; lint: hot` on the line above a `def` exempts that definition from Tier 3.
It must carry a reason on the same line: the marker is a claim about
measurement, and if you cannot say what runs per what, the code is not hot.

Prefer the per-definition form. A file-level marker in the header comment is
allowed but blunt — `x-python/runtime.x` carries real perf notes in only two
regions, so marking the file would excuse 3,600 lines to protect 40.

It does **not** exempt Tier 1. Those fixes are faster than what they replace.

## Not criteria

Measured and rejected. Do not reintroduce without new evidence.

| Rejected | Why |
|---|---|
| Raw `if` count | 7,697 occurrences; the overwhelming majority are ordinary two-way branches. |
| Raw definition length | The longest definitions are data tables. |
| Nesting depth alone | 279 deep-but-short walkers are idiomatic. |
| Comment density | Lowest scorers are `syscalls-*.x`, correctly. |
| `(do …)` blocks | 939 occurrences, overwhelmingly ordinary sequencing. |
| "Use `cond`" | Interpreted; measurably worse. `match` is the answer. |
| "Ladders → `Dict`" | 5× *slower* than `match` on integer keys. Only for ≥15 string arms. |

## Baseline

Measured 2026-09-02, so progress is checkable rather than asserted.

| Criterion | Count | Files |
|---|---|---|
| 1.1 ladders ≥4 arms (`ladder`) | 26 | 13 |
| 1.2 string-keyed ladders ≥15 arms (`ladder-dict`) | 1 (`%py-str-attr/26`) | 1 |
| 1.3 depth ≥12 and ≥500 nodes (`shape`) | 16 | 12 |
| 2.1 `(- 0 N)` | 73 | 14 |
| 2.2 `(if (not …))` | 261 | 59 |
| 2.3 `rest` chains ≥3 | 188 | 30 |
| 3.1 inlined `or`/`and` | 137 | 22 |

Highest concentrations of 1.3: `x-cc/build.x` (4) and
`x-python/runtime.x` (3). An earlier line-based count put this backlog at 68
across 41 files; that threshold (≥40 lines) sits around 200–400 nodes, in
the band the calibration above rejects.

**These counts are a snapshot of a live tree.** `x-cc` was being edited by
another session during the scan — `%cc-lower-loop` grew from 1822 to 1824
nodes mid-run — so re-measure before working from the table rather than
trusting a figure to the node.

The 1.1 / 1.2 figures are the linter's, counted structurally. An earlier
textual scan of the same corpus reported 28 findings across 17 files and it
was wrong in both directions: it credited `%op-precedence`
([`x-logo/logo/expr.x`](../../languages/x-logo/logo/expr.x)), which is
already a `match`; it counted comparisons anywhere in a definition rather
than arms of one chain (`codec/csv.x`, whose "12-arm ladder" is `match`
clauses); and it claimed 47 arms for `%py-jit-compile!`, which is not a
ladder at all. Nothing textual survives here — the numbers above come from
`tools/dev/lint.sh --warnings`.

**Where the ladders are.** All but one live in the language bundles:
`x-python` (14 across three files), `x-cc` (4), `x-grep` (2), `x-make` (2),
`x-coreutils`, `x-sed`, `x-sweet` (1 each). x-lang's own `lib/` yields a
single finding — `%lint-min-len/6`, in the linter itself. `x-ash`, `x-krn`,
`x-logo`, `x-r5rs` and `x-r7rs` are clean.

## Enforcement

Rules land in [`lib/x/tool/lint.x`](../lib/x/tool/lint.x), which already
carries scope, shadowing, unused-binding and leaked-`def` analysis, and
which the bundle repos run through `tools/dev/lint.sh`. Construct metadata
belongs in [`lib/x/constructs.x`](../lib/x/constructs.x), which already
records `match` as `(branch . clauses)`.

1.1, 1.2 and 1.3 are implemented: warning kinds `ladder`, `ladder-dict` and
`shape`, one finding per definition, named `NAME/ARMS` and
`NAME/DEPTHd/NODES` so the numbers survive. They are
advisory, so a file carrying one still passes. Advisory warnings are
dropped along with the output of a file that verdicts `ok`, so read them
with the flag added for this:

```sh
sh tools/dev/lint.sh --lib --warnings lib/x/tool/lint.x
```

The ladder helpers are per-node walk core, so they stay as `%`-defs rather
than `Lint` statics — the grounds the file's existing walk already stands
on — and `tools/contract/percent-globals.x` carries the ratchet and its
reason.

New rules are **report-only** until the Tier 1.3 backlog is cleared: they
warn, with counts, and `make lint` stays green. Flipping them to failures is
a separate change, made when the count reaches zero.

Do not add a new tool. There are already 39 checks in `tools/check/` and
five dev tools in `tools/dev/`; a fortieth that overlaps them is the
duplicated-fact problem in another form.
