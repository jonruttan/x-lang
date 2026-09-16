# Bootstrap tool closure

The self-hosting scorecard: every external tool the build system actually
invokes, measured rather than grepped. The long-term goal is that each row
below is either implemented in x, absorbed as an x-coreutils applet, or
explicitly ruled a permanent external.

## Progress (2026-09-15)

37 of the 46 rows have a registered, spec-checked implementation in x.
Those rows carry 99.1% of the logged invocations (11,120 of 11,222):

- **the language tools**: awk (x-awk, 167 cases), grep (x-grep, 29),
  sed (x-sed, 21), make (x-make, 23) — the original core four
- **sh**: x-ash, 363 cases
- **the applets**: x-coreutils, 92 applets over 323 cases, of which 32
  answer a row here — basename cat cmp comm cp cut date diff dirname
  fold head install join ln ls mkdir mktemp mv nproc readlink rm
  sha256sum sort stat timeout touch tr uname uniq wc which xargs.
  sha256sum is FIPS 180-4 in pure x, byte-identical with the system tool.

Pipelines of x tools compose today:
`... | x -l awk '{print $1}' | x -l coreutils -- sort | x -l coreutils -- uniq -c`.

Still external — 9 rows, 102 invocations: cc/strip (the compiler tier —
the next mountain), codesign/sysctl (platform, permanent), git/curl
(fetch, out of scope), tar (archive), find, and shasum.

**Implementation is not adoption.** The figure above says the tool exists
in x and its suite passes; it does not say the build calls it. The build
still invokes the system binaries throughout, so a fresh measurement would
move these counts very little. sha256sum is the plainest case: an applet
byte-identical with the system tool, while the Makefile's install rules,
x.sh and tools/release/package.sh each still prefer `shasum` and fall back
to `sha256sum`. Switching a row over needs no new code, only the call site.

The percentage re-scores the 2026-08-31 counts below against the
implementations that exist today. The counts are that measurement's own and
predate four bundles; re-run them (see Reproducing) before reading anything
into a single row.

Measured 2026-08-31 on macOS (Darwin 25.5.0) by shimming every executable on
PATH (4,455 logging wrappers) and running three phases in the x-lang checkout:

1. **build** — `make` after touching `engine/src/x-alist.c` (forces one
   compile + full link + sign): 16 tools, 38 invocations
2. **test-fast** — `make test-fast` (fast contract gates + engine C unit
   tests + x-lang specs; 2689 tests, 0 failed): 42 tools, 10,817 invocations
3. **install** — `make install DESTDIR=<sandbox>`: 28 tools, 367 invocations

## Union: 46 tools, ranked by invocation count

| count | tool | phase(s) | tier |
|---:|---|---|---|
| 4186 | grep | test | regex trio |
| 1754 | awk | test, install | regex trio |
| 1451 | sed | test, install | regex trio |
| 1415 | sort | test, install | coreutils |
|  643 | tr | all | coreutils |
|  392 | join | test | coreutils |
|  201 | head | test, install | coreutils |
|  149 | sha256sum | test, install | crypto |
|  134 | cat | test, install | coreutils |
|  130 | cut | test, install | coreutils |
|   85 | comm | test | coreutils |
|   84 | date | test | coreutils |
|   84 | basename | test | coreutils |
|   64 | dirname | test, install | coreutils |
|   55 | cc | all | compiler |
|   54 | sh | all (undercounted — see caveats) | shell |
|   42 | timeout | test | coreutils (GNU ext) |
|   42 | rm | test, install | coreutils |
|   31 | diff | all | diff/cmp |
|   29 | which | all | shell builtin candidate |
|   25 | mkdir | all | coreutils |
|   23 | readlink | all | coreutils |
|   22 | find | test, install | coreutils |
|   18 | uname | test | coreutils |
|   16 | mv | build, test | coreutils |
|   13 | wc | test, install | coreutils |
|   11 | install | install | coreutils |
|   10 | ln | all | coreutils |
|    9 | cp | all | coreutils |
|    7 | git | all | out of scope (fetch/dev) |
|    6 | shasum | test, install | crypto (mac fallback pair) |
|    6 | cmp | all | diff/cmp |
|    4 | uniq | test | coreutils |
|    4 | curl | test (engine-fetch smoke, file://) | out of scope (fetch) |
|    3 | tar | test | archive |
|    3 | make | all (undercounted) | make |
|    3 | ls | test, install | coreutils |
|    2 | xargs | test | coreutils |
|    2 | strip | build, install | binutils |
|    2 | stat | test | coreutils |
|    2 | mktemp | test | coreutils |
|    2 | codesign | build, install | platform (macOS only) |
|    1 | touch | build | coreutils |
|    1 | sysctl | test | platform |
|    1 | nproc | test | coreutils (GNU ext) |
|    1 | fold | test | coreutils |

## Reading it by self-hosting tier

- **regex trio (grep/awk/sed)**: 7,391 invocations — 64% of everything.
  Three bundles over one regex layer: lib/x/type/regex.x, which x-grep
  extends with BRE and x-sed then reuses whole, plus each tool's own
  line loop.
- **coreutils subset**: x-coreutils, one busybox-shaped bundle, answers 32
  of these rows. `sort`+`join`+`comm` (1,892 calls) are the relational
  workhorses of the contract gates; `timeout` and `nproc`, the two GNU
  extensions, are applets now rather than Homebrew. `find` (22 calls) is
  the one row in this tier with no applet.
- **shell (sh)**: x-ash; every make recipe line, and the count is a floor
  (see caveats).
- **make**: x-make. Recursion via $(MAKE); the GNU subset actually used is
  $(shell), $(wildcard), $(findstring), $(if), ifeq/ifdef, 2 pattern rules.
- **crypto**: 155 calls for manifest and ISA pinning, still the system pair
  at every call site. x has a byte-identical sha256sum; what is left here is
  adoption, not implementation.
- **compiler + binutils**: cc, strip — the open tier, and the largest
  external count left. ld/as never hit PATH, clang drives them internally,
  so the true compile closure is cc+as+ld+SDK.
- **archive**: tar, 3 calls.
- **platform, likely permanent externals on macOS**: codesign, sysctl.
- **out of scope (network/dev)**: git, curl.

## Caveats (undercounts)

- `sh` is invoked by make via absolute /bin/sh for every recipe line —
  PATH shims never see those. Its true count is the largest of all.
- clang's internal `ld`/`as` don't go through PATH.
- Absolute-path invocations (`/usr/bin/env`, hardcoded paths) bypass shims.
- Not measured: full `make test` extras (conformance, doctest, doc-x,
  lint-x, examples, check-package) and release targets — static grep says
  those add `gzip` and one `jq` use at least.

## Reproducing

For every executable in every PATH directory, write a wrapper into a shim
directory (first PATH hit wins) that logs its own name and execs the real
binary:

```sh
printf '#!/bin/sh\necho %s >> %s\nexec %s "$@"\n' "$name" "$log" "$real"
```

Then run each phase with the shim directory prepended to PATH, snapshotting
the log between phases:

1. `touch engine/src/<any>.c && make` — forces compile + link + sign
2. `make test-fast`
3. `make install DESTDIR=<sandbox>`

`sort | uniq -c | sort -rn` over the combined logs yields the table above.
Re-measure after adding or retiring a tool, and when widening coverage to
the full `make test` and release targets.
