# Code Quality Criteria

What counts as a defect in `.x` source, and what the fix is. The linter
(`lib/x/tool/lint.x`, run as `tools/dev/lint.sh`) finds the structural ones
and names each finding by the definition it is in. The scope is the
first-party `.x` corpus, x-lang and the language bundles; vendored `deps/`
and generated `build/` trees are out of it.

## Start here: `match` is the multi-way conditional

A chain of `if`s nested through their else branches is a multi-way
conditional written as a tower. `match` is the form for it: an engine
primitive that `if` and `let` are derived from
([`lib/x/core/control.x`](../lib/x/core/control.x)), which tests its clauses
in the engine until one is truthy, with no frame per arm. A flat `match` is
cheaper than the chain it replaces as well as flat, so there is no hot-path
reason to keep a chain.

```x
(match
  ((= c 40) 'lparen)
  ((= c 41) 'rparen)
  (#t       'other))     ; (#t …) is the else clause
```

`cond`, `and` and `or` are not the answer. They are interpreted operatives
that `eval` each arm, and their cost is documented beside them in
[`lib/x/core/boolean.x`](../lib/x/core/boolean.x) and
[`lib/x/core/syntax.x`](../lib/x/core/syntax.x). The avoidance of `cond` in
the corpus was right; the habit of nesting `if` that grew from it was not.

In a tokenizer callback, confirm `match` under AddressSanitizer before
converting: [`contributing.md`](contributing.md) bans `cond` and `convert`
there, and `match` is a direct primitive and should be fine, but that is an
inference until checked.

## 1. Structural

### 1.1 A multi-way test on one value is a `match`

A chain of `(if (test …) … (if (test …) …))` with three or more nested `if`s
is a `match`. The arms do not have to test the same variable: four arms of
one decision are four arms however they are spelled. A chain is not ended
by an arm whose test is an inlined `or` over the same variable; a compound
test over two different variables is a real decision and does end it.

The linter reports it as `ladder`, one finding per definition, named
`NAME/ARMS`.

### 1.2 A lookup by name is a class

A chain that compares one **string** against one name after another, to
choose a function, is not a conditional. It is a dispatch, and the class
system is the dispatcher. The names become static methods of a class, and
the call is the lookup:

```x
(def-class PyStr ()
  (static
    (method upper (self s) …)
    (method lower (self s) …)
    (method strip (self s) …)))

(PyStr upper s)        ; the lookup; a miss raises, naming the class and the name
```

The dispatcher keeps its own tables, so nothing is built at load and the
chain is gone at three names or at thirty. Do not build a `Dict` of
functions instead: that is the same dispatch table written by hand, with
its own construction, its own miss handling and no `help`.

A `match` is still right when the arms test a value rather than select a
function by name: a character against its escapes, an integer code against
its meaning.

The linter reports a string-keyed chain as `dispatch`, named `NAME/ARMS`.

### 1.3 Length and depth together, never either alone

A long, flat definition is usually a data table and is fine; splitting one
makes it worse. A deep, short definition is usually a tight recursive walker
and is fine too. The defect is both at once: a body that is deep **and**
large.

The linter measures size in nodes, not lines, since the formatter decides
the lines. Quoted data counts as one node; an inner `def` counts in full.
Both spellings of a definition are read, `(def NAME body)` and the
`(def NAME ())` plus `(set! NAME body)` pair a self-referential function
uses. The finding is `depth`, named `NAME/DEPTHd/NODES`.

**Fix:** apply 1.1 and 1.2 first, since some of the depth is a chain. What
remains, extract as named top-level `%`-helpers, not inner `def`s (see 2.4).

### 1.4 Duplicated bodies

A block repeated within a bundle wants a helper. A block repeated across
bundles belongs in `lib/`, or is a coincidence: two tokenizers that skip
whitespace the same way are not sharing a concept. Check which before
moving anything.

### 1.5 Private re-implementation of a library name

Reach for `apropos` before writing a helper. The boot layer is exempt, since
it cannot import what does not exist yet, and so is a helper whose comment
says why the library's version is wrong here. Say it; do not leave the
reader guessing.

## 2. Noise

Mechanical, with no performance dimension and no judgement needed.

### 2.1 `(- 0 N)` for a negative literal

The reader takes `-1` directly. `(- 0 1)` is a function call standing in for
a literal.

### 2.2 `(if (not X) A B)`

Write `(if X B A)`, or `unless` when there is no else arm. `not` is an
interpreted predicate, so the inverted `if` is shorter and cheaper.

### 2.3 `first`/`rest` chains

Past two levels of `(first (rest (rest …)))` the reader is counting parens
to recover an index. Use an indexed accessor, or destructure once into
named locals at the top of the body.

### 2.4 `def` inside a body

An inner `def` in tail position binds globally; the linter warns
(`%lint-leak!`), and a body-level `(def lit …)` has clobbered the quote
operative. It also invites duplication, each branch defining its own
helper. Lift it to a top-level `%`-helper, or bind with `let`.

## 3. Cold code only

### 3.1 Hand-inlined `or` and `and`

`(if a #t (if b #t c))` is `(or a b c)` spelled out. Unlike the structural
rules, this one has a real tradeoff: `or` and `and` are interpreted and cost
per arm, so in an eval loop or a per-character tokenizer the inlined form is
correct. In option parsing, error formatting or setup code it is noise.

Mark the deliberate cases; unmarked occurrences are findings.

## The `hot` marker

The performance reason for a flat form lives as a comment beside the code,
in a form the linter reads, so there is no list elsewhere to go stale:

```x
; lint: hot -- runs per input byte; an interpreted or costs an allocation per arm
(def %py-lex-char
  (fn (self s i n) …))
```

`; lint: hot` on the line above a `def` exempts that definition from
criterion 3. It must carry a reason on the same line: the marker is a claim,
and if you cannot say what runs per what, the code is not hot.

Prefer the per-definition form. A file-level marker in the header comment is
allowed but blunt, and excuses a whole file to protect a few lines.

It does **not** exempt 1.1 to 1.5. Those fixes are faster than what they
replace.

## Not criteria

Considered and rejected. Do not reintroduce without a reason the earlier
one did not have.

| Rejected | Why |
|---|---|
| Raw `if` count | the overwhelming majority are ordinary two-way branches |
| Raw definition length | the longest definitions are data tables |
| Nesting depth alone | deep, short walkers are idiomatic |
| Comment density | the lowest scorers are the syscall tables, correctly |
| `(do …)` blocks | overwhelmingly ordinary sequencing |
| "Use `cond`" | interpreted, and worse than the chain; `match` is the answer |
| "A chain becomes a `Dict`" | a dispatch table written by hand; a lookup by name is a class (1.2) |

## Enforcement

Rules live in [`lib/x/tool/lint.x`](../lib/x/tool/lint.x), which already
carries scope, shadowing, unused-binding and leaked-`def` analysis, and
which the bundles run through `tools/dev/lint.sh`. Construct metadata lives
in [`lib/x/constructs.x`](../lib/x/constructs.x).

1.1, 1.2 and 1.3 are implemented, as the warnings `ladder`, `dispatch` and
`depth`. They are advisory, so a file carrying one still passes; a bundle
that wants them to fail runs the kit's lint with `--strict`. Advisory
warnings are dropped with the output of a file that verdicts `ok`, so read
them with the flag for it:

```sh
sh tools/dev/lint.sh --lib --warnings lib/x/tool/lint.x
```

Flipping a rule from a warning to a failure is a separate change, made when
the corpus is clean of it.

Do not add a new tool. The checks in `tools/check/` and the dev tools in
`tools/dev/` are many already; one more that overlaps them is the
duplicated-fact problem in another form.
