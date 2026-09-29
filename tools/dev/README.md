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

## Profiling

Which functions a program's evaluation goes to.  The profiling engine,
`x-bin-profile`, counts in each object's flags word how many times evaluation
reached it, and an x-engine-c release ships it from v0.2.15 on.
`x/tool/profile` reads the counts back by function.

```sh
make profile-x FILE=program.x               # the 30 functions evaluation reached most
sh tools/dev/profile.sh -n 50 program.x arg...
sh tools/dev/profile.sh -x --no-image program.x   # boot without writing a state image
sh tools/dev/profile.sh --tsv program.x     # every row, tab-separated, for a script
```

The driver boots the library on `x-bin-profile`, sets every count to zero
with `(profile-clear!)`, includes the program, and prints
`(profile-report N)`: one row per function body, most evaluation first.

    evals   calls   pairs   where
    2555    465     21      /path/to/program.x:1

- **calls**: a procedure steps onto its body's first cell once a call, and
  that cell's count is its calls.  The engine does not count an operative's
  body cells, so an operative's calls are the count of its first form, which
  every call evaluates once; one whose body starts with a name or a constant
  reads 0.
- **evals**: the counts summed through the body's pairs.  The body of a
  function made inside it is left out when that function has a row of its
  own, so the rows divide the evaluation between them.  Forms are counted,
  not names: a symbol is interned, so its count is every evaluation of it.
- **pairs**: the pairs walked in the body.
- **where**: the file and line the body's first form was read from.

Everything from the clear to the report is counted: the program's own
functions, the library functions it calls, and the reader, which is x code
and reads the program after the clear.  The profiler adds nothing of its own:
between the clear and the reading it runs only the engine's forms and
primitives.  A count stops at 1,048,575; a row whose evals end in `+` holds
one, so its sum is a lower bound, and a shorter run gives the whole count.

From x: `(profile-evals obj)`, `(profile-fn f)`, `(profile-rows)` and
`(profile-clear!)`.  Their specs, `tools/tests/specs/profile/`, run on
`x-bin-profile` under `make test-tools`.

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
ceiling. The unrolled version lives here so the negative result stays
reproducible rather than being re-derived.

`--fold` moves the H shuffles into the compiled function (one native
call per block); `--fill` compiles the W fill itself via the byte-width
`%mem-byte` functions, padding included. Together they take the 25KB digest
from ~964ms interpreted-parts to ~71ms — at the price of ~9s of compile,
so the compiled digest pays off on reuse, not one-shot hashing. All
knobs compose, and the FIPS vectors plus a differential check against
`lib/x/codec/sha256.x` run on every invocation regardless.

Input is synthetic (`--size`, default 25000) because SHA-256 does
identical work per block whatever the bytes are -- no build artifact
needed. The three FIPS vectors are checked on every run before any
timing is reported; a fast wrong digest is worth nothing.

## State image writer

Writes a library's state as a binary image. The format is
[../../docs/state-image-format.md](../../docs/state-image-format.md), and
[../../docs/state-images.md](../../docs/state-images.md) is the design.

```sh
sh tools/dev/image-build.sh lib/x-core.x .images   # .images/x-core.x.ximg
sh tools/dev/image-build.sh lib/x.x .images        # helium
```

`image-build.sh` runs `image-write.x` on helium with `%IMG-LIB` and
`%IMG-OUT` bound, and skips the write when the image's key is current. The
writer makes a child base, loads `%IMG-LIB` in it and images the child, so
the writer's own names are not in the file. Its last lines give the counts:
objects, externals, roots, and the words it could not name, which an image
that is kept has none of. `X_IMG_WHO=1` names the holders of each such word.

`image-read.x` is the loader, run on the `img` dialect (`lib/img.x`). With
`%IMG-VERBOSE` bound it prints the counts and every external that did not
resolve.

The heap walk and unit reader the image tools share is a library module,
`x/tool/image/walk` (`lib/x/tool/image/walk.x`), and the names for foreign
addresses are `x/tool/image/name`; the scripts here take what they use by
selective import. Run the scripts from the repository root: their contract
includes are cwd-relative.

## Foreign-unit census

```sh
sh x.sh -q --no-image -f tools/dev/image-foreign.x
```

Counts the foreign units of the heap it runs in by the source that names
each. A foreign unit holds a raw address, which means nothing in another
process, so an image records the name the loader reacquires it by. The
sources, in the order the writer tries them:

| source | named by |
|---|---|
| the type's own call pointer | the type's name |
| the prims catalogue | `NAMESPACE/NAME` |
| the bare globals the ISA contract declares (`%isa-bare`) | the symbol |
| the process's `dlopen` handle | nothing; the loader opens its own |
| `dladdr`, checked back through `dlsym` | the linker's symbol |

None of them searches the heap for a name: a name is declared, looked up,
or asked of the dynamic linker. A unit that no source names is counted as
unnamed; in an image the writer refuses it.

The census counts the base it runs in, so the script's own allocations are
among the units. The writer images a child and does not see its own.

## An x86-64 Linux box

```sh
sh tools/dev/x86-vm.sh up            # boot (first run provisions; minutes)
sh tools/dev/x86-vm.sh run 'make -s' # sync this checkout in and run something
sh tools/dev/x86-vm.sh ssh           # interactive shell
sh tools/dev/x86-vm.sh down          # graceful shutdown
```

CI covers `ubuntu-24.04`, so x86-64 Linux is tested -- but on Apple
Silicon there was no way to *reach* it, and a platform whose only test
is a twelve-minute round trip through CI is a platform that gets fixed
by guessing. This is the local one.

It has to be a full-system VM. The cheap routes were tried first and
each of them answers the wrong question: Rosetta 2 gives x86-64 with
macOS underneath (right ISA, wrong OS -- it does not reproduce the JIT
crash the remote Linux box does); Rosetta for Linux dies on an
unimplemented syscall; qemu-user and `docker --platform linux/amd64`
crash the *known-good* configuration, so a crash under them proves
nothing; VirtualBox cannot run an x86-64 guest on an arm64 host.
`qemu-system-x86_64` emulates the MMU, so freshly-mmap'd JIT pages are
invalidated and re-translated the way real hardware would do it.

The price is speed -- TCG is roughly an order of magnitude off native,
so a tower boot is minutes rather than the six seconds it takes on
arm64. Use it to reproduce and bisect; use CI or a real x86-64 host for
full suite runs.

The guest gets 8G and 4G of swap, which is not generosity. A cold tower
boot peaks at 2.4G on arm64 and more here, and a 4G guest was
OOM-killed evaluating `(display 1)`. qemu allocates guest memory
lazily, so the ceiling costs the host nothing until it is touched.

It also contains the blast radius. The allocation ceiling is not an
OOM guard -- the runners default to a limit well past physical memory,
and a runaway engine has taken a workstation down more than once. In
the guest it hits a 4G wall and the guest's own OOM killer reaps it.

The guest starts empty: `sync` sends the tree, and the checkout still
has to acquire an engine for *its* platform before anything runs.

```sh
sh tools/dev/x86-vm.sh run 'make engine && make'
sh tools/dev/x86-vm.sh ssh  'cd x-lang && sh x.sh -q -l xe -f prog.x'
```

`X86_VM_SRC=/path/to/worktree` sends a different checkout, which is what
a worktree-per-branch layout needs -- the branch under test is rarely
the one this script happens to sit in.

Needs `qemu` (`brew install qemu`). State lives in
`~/.cache/x-lang/x86-vm`, never in the checkout, so `destroy` cannot
take a source tree with it. The sync sends files without `.git`, which
is enough to build the engine and run the specs; the gates that shell
out to git want a clone.

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
