# Crafting a lang

`docs/lang-contract.md` says what a lang bundle **is** — the files, the
declarations, what the platform ships and what a bundle must never vendor.
This document says how you actually **build** one, distilled from building
x-python: a Python 3 surface taken from a stub that answered
`#<python: not implemented>` to everything, to a language with containers,
classes, exceptions, comprehensions, slicing, and a working REPL — 426 specs
green — in the space of a few days.

Almost every rule below was learned by getting it wrong first.  Where that
happened, the mistake is stated with its mechanism, because the mistakes are
the transferable part: the next lang author will be tempted by the same wrong
turns, and a rule without its failure mode reads as style advice and gets
ignored.

## 1. The shape of a bundle

A lang is a bundle: `lang.xon` declares it, `run.x` is the entry, the
implementation lives in one directory named for the lang, and
`tests/spec-runner.sh` sources the **platform's** runner and vendors nothing.

```
lang.xon                (lang "python") (dialect xe) (requires-release "…") (entry "run.x")
run.x                   imports the implementation, wires the REPL
python/tokens.x         the reader: token types on an isolated base
python/indent.x         (historical) line structure — now a name, see §4
python/types.x          the lang's values, as x types
python/runtime.x        what the lang's operators and rules MEAN
python/parse.x          grammar → emitted x forms
tests/spec-runner.sh    sources the platform runner; sets policy knobs
tests/specs/*.spec.md   the hand-written suite — the real construction record
```

Two rules from the contract bear repeating because they bite in practice:

- **No path into the x-lang source tree.**  `x.sh` arms the bundle's import
  root and answers `--share-dir`; a bundle that reaches for
  `../../../lib` works in one checkout and dangles everywhere else.
- **The platform ships the runner; bundles do not vendor it.**  Your
  `tests/spec-runner.sh` is a dozen lines of policy (which files, which
  knobs) that sources the shared one.

## 2. Build against a scoreboard, construct against specs

Before x-python had a tokenizer it had a conformance suite: 657 upstream
MicroPython test programs, each pinned by commit and sha256, each with its
expected output taken from a real CPython run on the same machine.  A stub
that answers everything the same way scores 0 — and 0 against a suite that
runs is worth more than green against six hand-picked cases.

But learn what that scoreboard is **for**.  Each conformance case compares a
whole program's whole stdout, so one missing feature zeroes a sixty-line
program: a `dict` group scoring 0/19 says nothing about dicts when every case
also needs `str()`, `while`, `+=` and `er.args`.  Whole-program comparison
forbids partial credit by design.  So:

- The conformance suite is a **regression detector and a shopping list**,
  never a progress meter.
- Construction happens against **hand-written specs**, added with each
  feature, each one a `.spec.md` case with prose saying *why* the behavior is
  what it is.  x-python's suite grew from 0 to 426 cases this way, and the
  spec prose is now the best documentation the bundle has.
- When choosing what to build next, **count the corpus** instead of trusting
  the per-group scores: "`type` appears in 28 of 112 files" chooses better
  than "the class group is at 0%".

## 3. Where the seams go

The five-module split is not aesthetic; each boundary is a fact about the
system:

- **tokens.x** owns everything that must be decided *while reading
  characters* — a column can only be measured before the whitespace is gone.
- **types.x** owns representation: what the lang's values *are*.
- **runtime.x** owns meaning: what the lang's operators and rules *do*.  The
  parser emits calls to named functions (`%py-add`, not `+`), and every one
  is a place where a lang rule can be stated.  A parser that emits the host's
  operators is writing a different language wearing the same clothes.
- **parse.x** owns grammar only.  It should know nothing about
  representation — x-python's parser never sees a tag or a type handle.

## 4. The reader is the engine's loop — use it

The single largest structural lesson.  x-python first hand-wrote a
recursive-descent pass over a flat token list, in interpreted x, scanning for
closing brackets at 26 call sites and carrying a bracket-depth counter through
its line-structure pass.  None of the other bundles has such a pass, and the
reason is that the engine already provides the loop.

### The analyse protocol

A token type registers `analyse` and (optionally) `read` handlers on an
isolated base — `(Base make-tok)` — via `(Base make-type …)`.  The analyse
handler is called once per character and returns one of three things: another
state function (keep consuming), a score (accept), or nil (reject).

- `(%score-set score 1 buffer)` accepts **including** the current character.
- `(%buffer-unread buffer)` first accepts **excluding** it — how a token that
  ends at a delimiter gives the delimiter back.
- A **negative** score is "matched and discarded" — whitespace, comments.
- The score's magnitude is the match length, so contests between types are
  settled by **longest match**.
- **Discarding is "matched, with no read handler."**  A negative score does
  not suppress a type that has a reader; if you need a line-shape that
  vanishes (blank lines, comment-only lines), give it its **own reader-less
  type** whose analyser claims exactly those shapes.

Idioms that matter: the accept is the *return value* of `%score-set` — wrap
it in a sequencing form that returns nil and you have written a reject.  And
state builders that close over the current character must copy it
(`(+ chr 0)`), never capture the callback's own binding.

### Nesting is free: groups and blocks

`(prim-ref 'tok 'read)` reads the next expression *from the same buffer*, and
a `read` handler may call it.  So a delimited region collects its own
contents by recursing through the engine's reader:

- **Brackets**: an opener's read handler loops `tok read` until it sees its
  closer token, and the bracketed run becomes ONE token with its contents
  nested inside.  Strings are consumed by the string types before the group
  handler ever asks, so `["]"]` needs no quote tracking — the problem is not
  solved, it never exists.  Implicit line joining falls out: a newline inside
  a group never reaches the line-structure machinery.
- **Indentation** is a delimitation question too — a column opens and closes
  a region the way a bracket does — so blocks work the same way: the newline
  type measures the column (through the shared `x/reader/indent` stack, so
  tab policy has one answer across langs), and on an `open` recurses to
  collect a `(tok-block …)`.  One read returns one token and a single dedent
  can close several blocks, so the surplus lives in an "owed" counter that
  each enclosing block loop collects.

After this conversion, x-python's line-structure pass went from 134 lines to
a name, four closing-bracket scanners were deleted rather than moved, and
comma-splitting needed no depth count — an inner group is a single token.

### What the reader cannot do

**Precedence.**  Scoring answers one question — *where does this token end* —
which is longest-match on boundaries.  A bracket or an indented run fits
because it is self-delimiting.  Precedence is a *ranking between tokens
already read*, and there is no place in analyse/read to say "I built this
wrong, re-parent it": analyse returns a state, a score, or nil; read returns
a value.  Nesting is not ranking.  x-sweet's curly reader confirms this by
refusing — it folds `{a + b + c}` only when every operator is identical and
otherwise hands `$nfx$` to the program.  Keep operator precedence in a
recursive-descent ladder over the (now nested) token stream, as x-ash does.

### Read handlers and errors

**A read handler cannot raise.**  The C reader loop is driving, and an error
unwinding out of a handler through it takes the interpreter down rather than
reaching any guard.  Worse, a value *caught* across that boundary arrives as
nil — the payload does not survive the trip.  So a reader-detected error
(x-python's `IndentationError`) is carried out as **data**: a flag the
tokenize entry point re-raises once reading is over and x is driving again.

## 5. Values go on the type system, not the class system

x's class system is for types written in x, resolved when a file loads.  A
lang's values are built at run time and follow the lang's own rules — one
level lower is the level that fits.  The door is the **two-argument**
`make-type` (catalog `type`/`make`), which registers on **the base it is
called in** — the running base, where the numeric tower already lives.

Two prims, and the difference decided a failed design:

| prim | registers onto | use for |
|---|---|---|
| `base-make-type` | the base you name | token types on the isolated reader base |
| `make-type` | the base it is called in | the lang's VALUE types |

x-python first tried a child base per lang (`Base make` + `base-make-type` +
`Base eval`) and reached 190/232 specs before discovering that a child base
has no numeric tower — float and bigint are library types registered on
whichever base loaded them.  The wrong conclusion ("this design cannot work")
was written into a doc and survived a day; the capability it asked for
already existed under a name in another catalog namespace.  **Before
concluding the engine cannot do something, grep all of `src/x-prim/*.c` —
the namespace/member pair is often not what the C name suggests — and look
for a library type that already does the thing** (`x/num/rational.x` and
`x/type/vector.x` were working models of everything x-python needed).

What the handlers buy, mapped from Python:

| lang feature | type slot |
|---|---|
| `repr` / `str` | `write` / `display`, calling back into the lang's repr per element |
| `len(x)` | `length` |
| `x[i]`, and calling a class `Foo()` | `call` |
| iteration | `iter` |
| `a + b` on your types | `%type-push-op` |

Details with teeth:

- **Handler arity is `(fn (_ self) …)`** — first parameter is the TYPE.
  Getting it wrong reads a non-pair and segfaults rather than raising.
- **Mutation needs a cell.**  A mutable container's instance holds a cell
  whose rest is the payload, so `append` mutates the cell and every reference
  sees it.  An immutable type (tuples) skips the cell — the instance IS the
  value.
- **The iterator contract: exhaustion rides the STATE.**  A step answers
  `(value . next-state)` and only a nil *pair* ends the walk, so a nil
  *value* (Python's `None`) is an ordinary element.  x-python registered
  value-terminated steppers, nothing consumed the slot, and the bug sat
  invisible until specs exercised it: **a registered handler nobody steps is
  untested code that looks done.**
- **Push ops only onto types you invented.**  A type's ops fire when
  *either* operand carries the type, so pushing `*` onto the host's string
  type changes what `*` means for every string in the process.  The lang's
  rules for host types stay in runtime functions behind a predicate.
- **`write-to-str` closes the str/repr gap.**  `(prim-ref 'io 'write-to-str)`
  runs the writer with its sink redirected into a string, so the same type
  handlers that print also render — nested containers come out right with no
  second rendering path.
- Classes are callable values: `Foo()` needs no parser special case, just a
  `call` handler.  A constructor entry keyed by a name no lang identifier
  can spell (`"%ctor"`) lets builtin type objects convert instead of
  allocate.  A `qualname` slot travels with the class because the display
  prefix is a fact the constructor's *caller* knows.

## 6. The rules that bite

Every one of these cost a debugging cycle, most of them with the symptom far
from the cause.

**The `%`-globals share one flat namespace across the bundle.**  x-python
collided four times (`%py-len`, `%py-elems`, `%py-names-of`, `%py-block-of`),
and one collision presented as a *syntax* error from a runtime-only edit.
Grep the bundle before defining a name.  The platform's
`check-percent-globals` gate holds per-file budgets, shrink-only — when it
rejects your new globals, the intended fix is fewer names, not a bigger
budget.

**`def` decides global-vs-local by save-stack depth.**  In a called function
body, under TCO, a `def` can bind globally — clobbering a module name on
every call — or locally inside a guard handler's frame — vanishing with it.
Use `let` for function locals (binds in-frame unconditionally).  Use the
`base/def-global` door when something evaluated at depth (a REPL loop, a
guard handler) must define for the session.

**A raise skips your restore.**  Any save/restore around a parse or eval
leaks when the body raises — x-python's lexical-class cell leaked out of a
failed parse and a later `super()` error reported the wrong context.
Per-run state gets **reset at the entry point**, not restored at exits.

**Nothing collects unless you ask.**  x has no automatic collection: every
sweep in the tree is a hand-placed `(Heap collect)` — one at the end of the
boot amalgams, one at the top of each REPL turn (`lib/x/repl/loop.x`), and
`lib/x/codec/sha256.x` schedules its own inside the digest loop.  So the
interactive session is fine and *everything else accumulates until the process
exits*.  A lang that replaces the REPL loop (§7) inherits that turn sweep as a
duty: forget it and a long session, or a `-f` script with a loop in it, grows
without bound.  The platform's own note calls the per-turn sweep "the seat is
quiet" — the previous turn's eval has finished and no reader is mid-flight,
which is what makes everything unreachable there genuinely dead.

**An isolated tokenizer base does not survive collection.**  This is the one
that turns the rule above into a dilemma, and it is a platform defect rather
than a rule to code around.  A base from `(Base make-tok)` with a type
registered on it reads correctly, survives one collect, and dies on the read
after a few more.  Minimal, with no bundle code involved:

```x
(def collect (prim-ref (lit heap) (lit collect)))
(def read-str (prim-ref (lit tok) (lit read-str)))
(def b (Base make-tok))
(Base make-type b "W"
  (list (pair (lit analyse) (fn (_ buffer score chr) (%score-set score 1 buffer)))
        (pair (lit read)    (fn (_ . args) (lit w)))))
(read-str (Base raw-of b) "a")        ; fine
(collect) (read-str (Base raw-of b) "a")   ; fine
(collect) (collect) (read-str (Base raw-of b) "a")   ; dies
```

The consequence is structural, not cosmetic: **a lang that brings its own
tokenizer base cannot take the per-turn sweep**, so its sessions and its batch
runs accumulate, and its spec suite must set `SPEC_SEAM_COLLECT=0` (the
per-snippet collect kills the tokenizer specs first).  x-ash is the bundle
this bites; if your lang builds on `(Base make)` — the shared base, with the
sexp types already registered — you are not affected, and that is one more
reason to want the shared base if your surface can tolerate it.

**Whole-file paren balance can lie.**  Two miscounted closers in different
functions cancel to a clean total.  Check each edited definition closes at
depth zero, not the file sum.  And bound a text replacement by the text being
replaced, never by "up to the next definition" — that once deleted 200 lines
of a parser.

## 7. Interactive is a different loop, not a different prompt

The platform REPL's customization surface is the prompt string and the
printer.  The *read* is the ambient sexp reader, and no banner changes what a
reader is — a "Python" prompt over a sexp reader evaluates `1 + 2` as three
forms across three prompts.  A lang REPL replaces the **loop**: read a line
(a block, when it opens one), parse with the lang's parser, evaluate, echo by
the lang's rules.  Wire it by `set!`-ing the launcher's globals (`%banner`,
`repl`) from `run.x`.

What the loop must know:

- **User stdin lives on fd 3 during boot** (the boot stream occupies fd 0).
  Reclaim it on first call — `(Sys dup2 3 0)` — or you will read the
  exhausted boot pipe and every line arrives as EOF.
- **Each line is its own parse**, so any per-parse emissions (hoisted
  declarations, undefined-name shims) must be **conditional** — a guard that
  evaluates the name and only defines on the unbound raise — or line two
  clobbers line one's bindings.
- **Echo by emitted shape.**  The parser's output says which forms are
  statements (silent) and which are expressions (echo their repr) — but
  inspect carefully: the same head (`let`) can serve both, distinguished by
  what it binds.
- **The loop owns the collect.**  The platform loop sweeps at the top of every
  iteration, and that is what keeps a long session's heap at its live set
  rather than at its history.  Replacing the loop means replacing the sweep —
  unless your lang owns a tokenizer base, in which case you cannot have it
  (see §6), and a long session will grow.  Know which case you are in.
- **The banner should identify the whole stack.**  `%param-release` (engine)
  and `%platform-release` (x-lang) arrive as boot data; printing them plus
  the resolved root makes every which-install-am-I-running mystery
  self-answering.  A `-dirty` in the banner is a feature.

## 8. Making it fast

Boot cost decomposes before it optimizes.  Measure with `(quit)` piped
through each dialect: x-python's 28s turned out to be ~15s of xenon tower
amalgam boot (every tower dialect pays it; plain `x` boots in 1.3s) plus the
bundle loading under xenon's heavier reader — the bundle's own code was 3s
under a light dialect.  Know whose cost you are looking at before "fixing"
your share of it.

Interpreted analysers are the hot path — one call per character per
contesting type — and the platform can compile them:

- **There are two JIT lanes.**  `compile-asm` (the assembler lane) emits
  machine code directly and needs no toolchain; `compile` (the cc lane)
  shells out to a PATH cc at runtime.  Analysers use the assembler lane.
- **Fvars-present means analyser.**  The compiler discriminates its two
  calling worlds by the fvar table: integer functions (called from x, prim
  ABI, args evaluated and unboxed, result boxed) versus analysers (called
  from C with live stack values — nothing evaluated, objects stay pointers,
  result returned unboxed).  A compiled-with-fvars function is **for the
  tokenizer, not for you**: direct-calling it crashes by contract.
- `%score-set`'s sign folds `(- 0 1)` and raises loudly on other
  non-literals; any other non-trivial constant belongs in an fvar.
- **Adopt with sha256.x's pattern**: lazy, threshold-triggered, the whole
  attempt in a guard that pins `failed` and carries on pure-x.  Compiling
  costs seconds once; never per-call, and never unconditionally at load.

## 9. Testing is the construction method

- **Probes are specs.**  Never run the engine binary directly, and never
  probe by piping forms at it — the runner's process timeout and alloc
  ceiling are the machine's protection, and a probe written as a `.spec.md`
  becomes a regression test the moment it teaches you something.  Prototype
  risky mechanisms (a new reader trick, a compiled callback) on a **scratch
  base in a throwaway spec** before touching working code.
- **The wrapper is the contract.**  Every runner expects its lang wrapper
  (which sets `LANG_LIB`, `X_BIN`, policy knobs).  Invoking a core directly
  produces failures that misattribute themselves — both halves of a
  two-session debugging saga were exactly this mistake, and the resulting
  guards now fail loudly.  Corollaries: after editing anything that is
  amalgamated (`tool/compile.x`), `make boot`, or your edit silently does not
  load; suites resolve modules against the root the harness baked in, so
  point `X=` at the tree you mean.
- **One process per spec file** once a suite grows: a batch accumulates
  parse garbage against the alloc ceiling, and the failure ("interpreter
  died mid-batch") names innocent cases.  Respect the unit timeout's margin —
  a file that reaches it under CI load fails from the tail backward; split
  files before they graze it.  And never force `PARALLEL` over many
  tower-booting files, or run two heavy suites concurrently: the per-process
  guards cannot bound total memory.
- **Size the alloc ceiling to the smallest machine that runs the suite, not
  the biggest.**  With `SPEC_SEAM_COLLECT=0` (which a lang owning a tokenizer
  base must set — §6) a spec job accumulates a whole file's garbage, so the
  `alloc-limit!` guard is bounding a *sum*.  The platform default is 300M
  objects, ~14 GB, calibrated for a dev box: on a 16 GB CI runner a process
  approaching it exhausts the machine *before* the guard trips, and the job
  dies with `spec-gate: killed by SIGTERM` and no output at all to say why.
  Lower it until the guard fires first — a failed spec is legible, a killed
  job is not.  Measure on the small machine; a workstation that passes proves
  nothing about the runner, and "it is green here" is how this gets shipped
  twice.
- **Controls before conclusions.**  In two days, seven confident diagnoses
  died under control runs — a wrong bisect, two wrong suspects, a
  misattributed environment difference, a self-defective probe among them.
  The discipline that survived: reproduce on a pristine tree, run the
  interpreted twin of every compiled failure, exchange exact command lines
  before comparing results across sessions, and when an error names an
  operation your code never performs, check the arguments you handed the
  machinery first.  An error that changes shape across versions of the
  callee while your code stands still is near-proof the defect is in what
  you handed it.
- **State divergences as pending specs**, not code comments.  A divergence
  with a spec (`return` inside `try` skipping `finally`) stays visible and
  testable; a comment rots.  And when a case's example graduates — the
  feature it relied on being absent gets built — keep the old expectation as
  a new case asserting the new answer: the change of answer IS the feature.

## 10. The failure mode to fear is the silent wrong number

Across the whole build, the expensive bugs shared one shape: no error,
plausible output, wrong value.  `[1] + [2]` printing a pointer as an integer;
`1e10` reading as `1`; `float('abc')` answering `0.0`; a float literal
silently truncated to its integer prefix; a discard score arriving as
+65535×len.  Every one was found by a spec comparing against an external
oracle (CPython, or arithmetic done by hand), and several had survived under
green suites because nothing asked.

The defenses, in the order they pay: compare against an oracle, not your own
expectations; refuse to trust a conversion or shortcut with input the program
supplied (parse it yourself and raise the lang's own error); and when you
must diverge, make the divergence loud or make it a pending spec.  A loud
error is a gift; the silent wrong number is the one that ships.
