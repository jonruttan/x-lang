# Dev tools

Developer conveniences: formatter, linter, coverage, benchmarks, doc
generation.  None of these are gates -- the contract gates live in
`tools/check/` (see `tools/README.md` for the taxonomy).

## Formatter

Auto-formatter for x-lang source files with configurable width threshold.

```sh
# Print formatted output to stdout (a pure filter)
sh x.sh --no-pin -q -f tools/dev/fmt.x -- FILE

# Format all library files in place / check formatting
make fmt-x
make fmt-check-x
```

In-place and check modes are launch glue in the make recipes; the tool
itself is a filter.  NOTE: `make fmt-check-x` is currently red on four
hand-formatted files (x-core.x, constructs.x, rn.x, xe.x) whose layout
disagrees with the formatter's width rules -- a pre-existing style
adjudication tracked in the overhaul follow-ups.

### Formatting rules

Forms shorter than 60 characters stay on one line.  Longer forms break
across multiple lines with 2-space indentation.

| Form | Rule |
|------|------|
| `def` | Name on same line, body at +2 |
| `if` | Condition on same line, branches at +2 |
| `fn` / `op` | Params on same line, body at +2 |
| `do` / `begin` | Body forms at +2 |
| `let` | Bindings on same line, body at +2 |
| `match` / `cond` | Clauses at +2 |

`;` line comments are preserved; quoted strings are preserved exactly;
`()` is output for nil; atoms output raw.

### Architecture

- `tools/dev/fmt.x` -- the whole tool (reads constructs + target by
  path, tokenizes with a fresh comment-keeping base, walks, emits)

## Linter

Static analysis: undefined symbol references and unused definitions.

```sh
# Lint a single file
sh tools/dev/lint.sh FILE

# Lint all library files
sh tools/dev/lint.sh
# or: make lint-x

# Lint in library mode (suppresses unused warnings)
sh tools/dev/lint.sh --lib FILE
```

Undefined symbols are auto-discovered against the current environment, so
built-ins are never flagged.  `%`-prefixed names are exempt from unused
warnings; `--lib` mode suppresses unused warnings entirely (library
exports are used downstream).  Scope tracking covers `def`/`set!`, `fn`,
`op`, `let`, `guard`; `lit` is opaque; `quasi` walks only unquoted parts.

### Architecture

- `tools/dev/lint.x` -- the linter (scope walk + reporting; the `%lint-lib`
  first-form token is its library-mode flag)
- `tools/dev/lint.sh` -- launch wrapper (file discovery, constructs input)

## Coverage

Flag-bit branch coverage for x-lang programs.  The `x-bin-cov` binary is
a modified build that sets `X_OBJ_FLAG_2` (0x2) on every AST node at eval
time; the reporter walks the original AST afterwards and reports which
`if`/`match`/`cond` branches never ran.

```sh
sh tools/dev/cov.sh FILE      # single-file branch coverage
sh tools/dev/cov-lib.sh      # aggregated library coverage (x-bin-profile)
```

NOTE: the `make x-bin-cov` build target this tool needs is currently
absent from the Makefile (pre-existing rot; only `make clean` remembers
the binary).  Restoring it is tracked in the tools-overhaul follow-ups.

1. **Marking**: `x-bin-cov` adds one line to `x_eval()` under `#ifdef
   X_COV`, setting bit 0x2 on every evaluated expression's flags field.
2. **Tokenization**: the reporter (`cov.x`) reads the source as a string
   and tokenizes with `(Tok read-str)` on the current base.
3. **Evaluation**: an operative loop evaluates each top-level form
   (operatives, not closures, so `def` effects persist).
4. **Walking**: branch nodes without the flag are reported.

The GC sweep clears only `X_OBJ_FLAG_HEAP`, so coverage flags survive
collection.  Limitations: interned atoms are shared (marking one `x`
marks them all -- compound branch expressions are the reliable signal);
no line numbers; the target must run under `x-bin-cov` itself.

## SHA-256 / JIT benchmark

Where a digest's time actually goes, and the harness that proved the JIT
was not where it went.

```sh
sh x.sh --no-pin -q -f tools/dev/bench-sha256.x -- [--parts] [--fold] [--unroll N] [--size BYTES]
```

`--parts` times the digest's pieces separately over the same block count:
the compiled round loop, the interpreted W fill, and the interpreted H
shuffles. **Run it before optimising anything in this area.** It exists
because intuition here was wrong by two orders of magnitude -- the
compiled round loop, which #189-#195 spent a week sharpening, was 0.9% of
a 25KB digest against 92.5% for the W fill. The three parts should
roughly sum to the end-to-end digest; a sum well under it means
something outside the three is paying, and that is the next thing to
look at.

`--fold` moves the H shuffles into the compiled function (a sentinel
entry at `t = -1`; the store rides the exit branch), so each block is one
native call instead of a call bracketed by two interpreted 8-iteration
loops. Measured at `--size 25000`: digest 963.8 → 666.7ms (−31%). Under
`--fold` the parts report says `folded into rounds` for the shuffle line
rather than timing loops the digest no longer runs.

`--unroll N` emits N round bodies per recursive call. It is a knob for
RE-MEASURING, not a recommendation: 1/2/4 measure as noise (the boxing it
amortises is a fraction of that 0.9%), and 8 trips the allocation
ceiling. The unrolled shape lives here so the negative result stays
reproducible rather than being re-derived.

`--fold` moves the H shuffles into the compiled function (one native
call per block); `--fill` compiles the W fill itself via the byte-width
`%mem-byte` family, padding included. Together they take the 25KB digest
from ~964ms interpreted-parts to ~71ms — at the price of ~9s of compile,
so the compiled digest pays off on reuse, not one-shot hashing. All
knobs compose, and the FIPS vectors plus a differential check against
`lib/x/codec/sha256.x` run on every invocation regardless.

Input is synthetic (`--size`, default 25000) because SHA-256 does
identical work per block whatever the bytes are -- no build artifact
needed. The three FIPS vectors are checked on every run before any
timing is reported; a fast wrong digest is worth nothing.

## State image writer

Writes the live heap out as a binary state image -- the writer half of
[../../docs/state-images.md](../../docs/state-images.md).

```sh
sh x.sh -q -f tools/dev/image-write.x        # helium, to /tmp/x-core.ximg
sh x.sh -q -l xe -f tools/dev/image-write.x  # xenon
```

It images the base it runs in, so the dialect flag chooses what gets imaged.
Output path is the `%IMG` def near the bottom of the file.

`image-walk.x` holds the heap walk and unit reader both image tools share; it
is a file rather than a copy in each because its three rules were each learned
by breaking them. Run it from the repository root -- the include is
cwd-relative -- and note that `tools/dev/lint.sh` does not follow the include,
so the two including files report the shared names as undefined. `make lint-x`
covers `lib/` and `apps/`, not `tools/`, so nothing is gated on it.

## Foreign-unit census

```sh
sh x.sh -q -f tools/dev/image-foreign.x
```

Counts how many of the heap's foreign units the image can actually name. Every
foreign unit holds a raw address and no address survives into another process,
so each has to be reacquired by name. Three sources, and between them they
reach 142 of 146:

| source | names |
|---|--:|
| the prims catalog | 104 |
| the bare globals the ISA contract declares (`%isa-bare`) | 24 |
| `dladdr`, round-trip checked back through `dlsym` | 17 |
| still unnamed | 4 |

None of them goes looking. Nothing in x safely can: `first` is unchecked, so
`(first 5)` segfaults; `pair?` answers #f for the structural pairs the base
spine is built from; and `%reflect-type-word` is itself a dereference, so even
asking "may I walk this?" is the unsafe act. Names are declared, looked up, or
asked of the dynamic linker.

The image carries the object graph -- extent table, object table and byte blob,
with every reference resolved to an object index -- and a **foreign table**:
one entry per named address, as a kind word, a name-length word and the name
bytes padded to a word boundary. Foreign units in the object table are indices
into it. The section references nothing else, so it can be built before the
object walk.

It also carries a **type table** -- one entry per distinct type word the heap
actually uses, as kind, unit count, unit mask and name -- and object records
name their type by index into it. A count may be negative: that is the
slot-0-counted form, and the loader needs the sign as much as the magnitude.

**The root is the environment, not the base.** The base object is traced but
is not on the allocation chain, so no walk reaches it and it is not in the
image at all -- which is right rather than missing: the base is the static
spine, readable only through `base-layout.x` and `base-paths.x`, and a loader
rebuilds it. What a loader reattaches is what hangs off it, so the header
records the imaged indices of the env-alist and the global tree, both of which
are flagged, traced and on the chain.

**Still not loadable**, because nothing can read the file until the engine
grows the allocate-and-patch loop the document specs. The remaining gap in the
file itself is the 266 references to statics, which resolve to 0 and need the
base-paths encoding.

Two things to know when reading one. The writer images the base it runs in, so
its own libc doors (`malloc`, `calloc`, `write`, `creat`) appear among the
foreign entries -- that is the writer-in-its-own-base problem the document
records, showing through. And **the heap may be marked only once per process**:
`(heap chain-clear!)` permanently disables any later `(heap tree-mark!)`, and a
mark after a clear flags nothing at all, silently, so every later walk reports
a clean zero. Passes that need no reachability use `%walk-all` and run before
the mark.

What it does guarantee is self-consistency, and that is worth checking after
any change: the extent table must sum to exactly the object table's unit
count, and the section sizes must add up to the file length.

## Others

- `tools/dev/bench.sh` -- library-load benchmarks over `x-bin-profile`
- `tools/dev/doc.x` -- Markdown doc generation from source (per-file filter)
- `tools/dev/doc-index.x` -- the `docs/ref` master index (filter)

## Tests

```sh
make test-tools
```

Runs `tools/tests/` (fmt specs on the plain engine, cov + meta specs on
`x-bin-cov`).  In `make test` and CI since the #180 repair.  The legacy
def/use library `lint-lib.x` and its specs were retired with that repair
(dead code: loaded by nothing, its `%walk-pair` dispatcher was never
assigned); the live linter is `lib/x/tool/lint.x`, gated by `lint-x`.
