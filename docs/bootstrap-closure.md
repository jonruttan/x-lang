# Bootstrap tool closure

The self-hosting scorecard: every external tool the build system actually
invokes, measured rather than grepped. The long-term goal is that each row
below is either implemented in x, absorbed as an x-coreutils applet, or
explicitly ruled a permanent external.

## Progress (2026-09-16)

Measured fresh on this date. 36 of the 45 rows have a registered,
spec-checked implementation in x, and they carry 97.7% of the logged
invocations (19,934 of 20,398):

- **the language tools**: awk (x-awk, 167 cases), grep (x-grep, 29),
  sed (x-sed, 21), make (x-make, 23) — the original core four
- **sh**: x-ash, 363 cases
- **the applets**: x-coreutils, 93 applets over 341 cases, of which 31
  answer a row here — basename cat cmp comm cp cut date dirname diff find
  fold head install join ln ls mkdir mktemp mv nproc readlink rm sha256sum
  sort timeout tr uname uniq wc which xargs. sha256sum is FIPS 180-4 in
  pure x, byte-identical with the system tool.

Pipelines of x tools compose today:
`... | x -l awk '{print $1}' | x -l coreutils -- sort | x -l coreutils -- uniq -c`.

Still external — 9 rows, 464 invocations: cc (the JIT's compiler tier),
perl, shasum, codesign/sysctl (platform, permanent), git/curl (fetch, out
of scope), tar, strip.

**Implementation is not adoption.** The figure above says the tool exists in
x and its suite passes; it does not say the build calls it. The build still
invokes the system binaries throughout — this measurement counts the system
tool at every one of those rows.

Adoption is not uniformly available, either. A call site is **post-x** when x
is built and runnable by the time it fires; those can take an applet, and the
work is the call site alone. A call site is **pre-x** when it runs before
there is an x to call — the wrapper's own boot guard, engine acquisition, the
image-directory name computed ahead of `require_engine`. Those cannot switch
at all. Among the integrity checks the barrier is not ordering but meaning: a
digest that decides whether to trust x is worth nothing if x computes it.
`tools/engine/engine.pin.xon` states the same rule for itself — it is "read by
a shell script that runs BEFORE any engine exists and so cannot use x to parse
it."

Closure therefore has a floor above zero, and 45 of 45 was never the target.

## What moved since 2026-08-31

The first measurement ran against a tree that **carried** the engine as a
submodule and compiled it. The engine is now a separate project, acquired
rather than carried, and `tools/engine/engine.pin.xon` names a prebuilt
artifact for both platforms CI runs (darwin arm64, linux x86-64). The build
rule takes the source branch only when the engine directory has a Makefile:

    if [ -f $(ENGINE_DIR)/Makefile ]; then $(MAKE) -C $(ENGINE_DIR); ...

With a prebuilt artifact linked, it does not, and **`make` compiles nothing**.
Measured: zero invocations of cc, clang, ld, as, strip or codesign across the
whole build phase. The compiler tier did not get cheaper; it moved to the
engine's own repo and CI.

`cc` has not left the closure, though. It reappears in the **test** phase, 127
invocations, where the JIT's cc-hosted tier compiles at runtime — the middle
rung of the asm → cc-hosted → twins ladder. That is a different thing from a
build dependency, and the two should not be read as one row.

Other movement: `perl` is new, `stat` and `touch` have dropped out, `find`
went from 22 invocations to 315, and the crypto pair doubled to 330.

## Union: 45 tools, ranked by invocation count

Measured 2026-09-16 on macOS (Darwin 25.6.0), 4,455 logging wrappers, three
phases. "in x" marks a row with a registered implementation — not one the
build calls.

| count | tool | phase(s) | in x |
|---:|---|---|---|
| 4976 | grep | test | x |
| 3307 | mv | test | x (but see caveats — this row is noise) |
| 2380 | sed | build, test, install | x |
| 2024 | awk | test, install | x |
| 1631 | sort | test, install | x |
| 837 | cat | test, install | x |
| 696 | tr | test, install | x |
| 675 | dirname | test, install | x |
| 432 | join | test | x |
| 324 | date | test | x |
| 315 | find | test, install | x |
| 299 | rm | test, install | x |
| 292 | head | build, test, install | x |
| 283 | cut | test, install | x |
| 278 | basename | build, test, install | x |
| 255 | sh | build, test, install | x |
| 181 | mkdir | test, install | x |
| 170 | sha256sum | test, install | x |
| 165 | timeout | test | x |
| 162 | perl | test | **external** |
| 160 | shasum | test, install | **external** |
| 127 | cc | test | **external** |
| 104 | xargs | test | x |
| 85 | comm | test | x |
| 60 | mktemp | test | x |
| 33 | readlink | build, test, install | x |
| 26 | install | install | x |
| 25 | diff | test, install | x |
| 21 | uname | test | x |
| 14 | wc | test, install | x |
| 10 | ln | build, test, install | x |
| 10 | cp | build, test, install | x |
| 8 | which | test | x |
| 4 | uniq | test | x |
| 4 | make | build, test, install | x |
| 4 | git | test, install | **external** |
| 4 | curl | test | **external** |
| 4 | cmp | build, test, install | x |
| 3 | tar | test | **external** |
| 3 | ls | test, install | x |
| 2 | sysctl | test | **external** |
| 2 | nproc | test | x |
| 1 | strip | install | **external** |
| 1 | fold | test | x |
| 1 | codesign | install | **external** |

Per phase: build 9 tools / 23 invocations; test 42 / 19,934 (3143 tests, 0
failed); install 27 / 441.

## Reading it by self-hosting tier

- **regex trio (grep/awk/sed)**: 9,380 invocations — 46% of everything.
  Three bundles over one regex layer: lib/x/type/regex.x, which x-grep
  extends with BRE and x-sed then reuses whole, plus each tool's own
  line loop.
- **coreutils subset**: x-coreutils, one busybox-shaped bundle, answers 31
  of these rows. `sort`+`join`+`comm` (2,148 calls) are the relational
  workhorses of the contract gates. `find` is an applet as of x-coreutils#31,
  which matters more than the old count suggested: 315 invocations, not 22.
- **shell (sh)**: x-ash; every make recipe line, and the count is a floor
  (see caveats).
- **make**: x-make. Recursion via $(MAKE); the GNU subset actually used is
  $(shell), $(wildcard), $(findstring), $(if), ifeq/ifdef, 2 pattern rules.
- **crypto**: 330 calls for manifest and ISA pinning, still the system pair
  at every call site. x has a byte-identical sha256sum, but only three sites
  can take it: `Makefile:1076` and `Makefile:1087`, under an `install` target
  that has the built executable as a prerequisite, and
  `tools/release/package.sh:37`. The other four are pre-x — `x.sh:1039`
  guards the amalgam before boot, `x.sh:1111` verifies a fetched engine
  tarball before unpacking it, and `x.sh:1471` and `x.sh:1524` name the image
  cache directory ahead of `require_engine`. Switching only the reachable
  three would remove no external invocation: the same digest has three
  producers that must agree by construction (the Makefile,
  `tools/release/release-manifest.sh`, the x-engine.xon generator), and five
  further shell tools under `tools/` reach for the pair independently.
- **perl**: the spec runner's NUL filter (`tests/spec-runner.sh:76`), which
  turns a zero byte into `<<NUL>>` so a spec can assert one. It entered the
  closure with that feature and the runner warns when it is absent. A post-x
  site: x reads and writes NUL-carrying bytes (x-coreutils#30), so this one is
  reachable.
- **compiler tier**: cc, in the test phase only, from the JIT. `strip` is one
  install-time call. Neither is a build dependency any more.
- **archive**: tar, 3 calls. `x.sh:1116` unpacks a fetched engine, so part
  of this row is pre-x, with curl beside it in the same acquisition.
- **platform, likely permanent externals on macOS**: codesign, sysctl.
- **out of scope (network/dev)**: git, curl.

## Caveats

- **`mv`'s 3,307 is not a property of the build.**
  `tools/check/asan-boot.sh` sets every `/tmp/x-asm-*` file aside and puts it
  back, two `mv` calls per file, and that directory holds however much asm
  byte cache has accumulated on the machine. This run saw ~1,653 of them; a
  clean runner sees almost none, and the 2026-08-31 measurement recorded 16.
  Read the row as environmental, not structural.
- `sh` is invoked by make via absolute /bin/sh for every recipe line —
  PATH shims never see those. Its true count is the largest of all.
- Absolute-path invocations (`/usr/bin/env`, hardcoded paths) bypass shims.
- The build phase depends on whether the engine arrives prebuilt or as
  source. This measurement is the prebuilt path, which is what CI runs and
  what `make engine` gives on both platforms with an artifact row. A tree
  built against engine sources would put cc, ld, as, strip and codesign back
  into the build phase.
- Not measured: full `make test` extras (conformance, doctest, doc-x,
  lint-x, examples, check-package) and release targets.

## Reproducing

For every executable in every PATH directory, write a wrapper into a shim
directory (first PATH hit wins) that logs its own name and execs the real
binary:

```sh
printf '#!/bin/sh\necho %s >> %s\nexec %s "$@"\n' "$name" "$log" "$real"
```

Then run each phase with the shim directory prepended to PATH, snapshotting
the log between phases:

1. `rm -f x-bin && make` — the build. (With an engine checkout rather than an
   artifact, touch one of its `src/*.c` first to force compile + link + sign.)
2. `make test-fast`
3. `make install DESTDIR=<sandbox>`

`sort | uniq -c | sort -rn` over the combined logs yields the table above.
Empty `/tmp/x-asm-*` first, or the mv row measures the cache rather than the
build. Re-measure after adding or retiring a tool, and when widening coverage
to the full `make test` and release targets.
