# Bootstrap tool closure

The self-hosting scorecard: every external tool the build system actually
invokes, measured rather than grepped. The long-term goal is that each row
below is either implemented in x, absorbed as an x-coreutils applet, or
explicitly ruled a permanent external.

> **A snapshot.** The figures below were measured on 2026-11-20. File and
> line references are as they stood that day. A fresh run follows
> [Reproducing](#reproducing).

## Progress (2026-11-20)

40 of the 47 rows have a registered, spec-checked implementation in x, and
they carry 98.6% of the logged invocations (18,467 of 18,734):

- **the language tools**: awk (x-awk), grep (x-grep), sed (x-sed),
  make (x-make)
- **sh**: x-ash
- **the applets**: x-coreutils, 237 applets, of which 35 answer a row
  here — basename cat chmod cmp comm cp cut date diff dirname find fold
  head install join ln ls mkdir mktemp mv nproc readlink rm sha1sum
  sha256sum sleep sort sysctl tail tar timeout tr uname wc xargs.

`tools/contract/langs.x` carries each bundle's current suite size.

Pipelines of x tools compose today:
`... | x -l awk '{print $1}' | x -l coreutils -- sort | x -l coreutils -- uniq -c`.

Still external — 7 rows, 267 invocations: cc (the JIT's cc lane), git,
openssl and curl (test peers and fetch), stty, and strip and codesign
(one install-time call each).

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

Closure therefore has a floor above zero, and 47 of 47 was never the target.

## What moved since 2026-09-16

- **shasum is gone.** Every digest goes through `tools/lib/digest.sh`
  (`x.sh` carries the same three functions), which takes sha256sum and
  sha1sum first and shasum only when neither is there. On this host both
  are present, so the rows read sha256sum (324) and sha1sum (183, the
  image-cache keys).
- **perl is gone**: the NUL escaper is `tools/dev/nul-escape.x`.
- **tar and sysctl** are x-coreutils applets; both rows move to "in x".
- **openssl** is new, 19 calls: the TLS 1.3 spec runs `openssl s_server`
  and `s_client` as the peer for x's own client and server.
- **git** went from 4 calls to 110. Its callers were not traced; the
  scripts under `tools/` that read the history include release-version,
  changelog-commits and bootstrap-smoke.
- **mv** dropped from 3,307 to 57: the ASan gate no longer moves the byte
  cache (x-lang#820).
- **sort, join and comm** dropped from 2,148 to 552 calls together.
- **stty, tail, sleep, chmod** are new rows. All but stty are applets.

## Union: 47 tools, ranked by invocation count

Measured 2026-11-20 on macOS (Darwin 27.2.0), 4,466 logging wrappers, three
phases. "in x" marks a row with a registered implementation — not one the
build calls.

| count | tool | phase(s) | in x |
|---:|---|---|---|
| 4674 | grep | test | x |
| 2992 | sed | build, test, install | x |
| 2194 | awk | test, install | x |
| 1465 | cat | test, install | x |
| 1044 | dirname | test, install | x |
| 765 | head | build, test, install | x |
| 595 | tr | test, install | x |
| 562 | date | test | x |
| 496 | rm | test, install | x |
| 461 | basename | build, test, install | x |
| 443 | sort | test, install | x |
| 403 | sh | build, test, install | x |
| 394 | find | test, install | x |
| 324 | sha256sum | test, install | x |
| 322 | mkdir | test, install | x |
| 284 | timeout | test | x |
| 284 | cut | test, install | x |
| 183 | sha1sum | test | x |
| 130 | cc | test | **external** |
| 126 | xargs | test | x |
| 110 | git | test, install | **external** |
| 109 | mktemp | test | x |
| 89 | comm | test | x |
| 57 | mv | test | x |
| 34 | install | install | x |
| 25 | wc | test, install | x |
| 21 | uname | test | x |
| 20 | join | test | x |
| 20 | diff | test, install | x |
| 19 | openssl | test | **external** |
| 13 | tail | test | x |
| 12 | ls | test, install | x |
| 11 | cp | build, test, install | x |
| 10 | readlink | build, test, install | x |
| 10 | ln | build, test, install | x |
| 6 | sleep | test | x |
| 6 | cmp | build, test, install | x |
| 4 | make | build, test, install | x |
| 4 | curl | test | **external** |
| 3 | tar | test | x |
| 2 | sysctl | test | x |
| 2 | stty | test | **external** |
| 2 | nproc | test | x |
| 1 | strip | install | **external** |
| 1 | fold | test | x |
| 1 | codesign | install | **external** |
| 1 | chmod | test | x |

Per phase: build 9 tools / 18 invocations; test 44 / 17,991 (5,010 tests, 0
failed, 9 pending); install 26 / 725.

## Reading it by how far each is self-hosted

- **regex trio (grep/awk/sed)**: 9,860 invocations — 53% of everything.
  Three bundles over one regex layer: lib/x/type/regex.x, which x-grep
  extends with BRE and x-sed then reuses whole, plus each tool's own
  line loop.
- **coreutils subset**: x-coreutils, one bundle made as busybox is, answers 35
  of these rows. `sort`+`join`+`comm` (552 calls) are the relational
  workhorses of the contract gates.
- **shell (sh)**: x-ash; every make recipe line, and the count is a floor
  (see caveats).
- **make**: x-make. Both Makefiles, this one and the engine's, need no
  reading only GNU make has: recursion is `cd DIR && $(MAKE)`, a shell value
  is computed at the recipe, and a conditional is a computed macro name.
- **digests**: 507 calls, all through `tools/lib/digest.sh` or its copy in
  `x.sh`. x-coreutils' sha256sum and sha1sum are byte-identical with the
  system tools. The pre-x sites (`x.sh`'s boot guard, its fetched-engine
  check, the image-cache directory name) cannot take x's; the
  post-x ones can, by putting the applets first on PATH.
- **compiler**: cc, 130 calls in the test phase only, from the JIT's cc lane.
  [x-cc](https://github.com/jonruttan/x-cc) is a C compiler in x and builds
  the engine end to end; whether it can take the cc lane's calls has not been
  measured, so the row stays external. `strip` is one install-time call.
- **platform, likely permanent externals on macOS**: codesign. stty is a
  busybox applet that x-coreutils does not have yet.
- **test peers and fetch**: openssl (the TLS spec's peer), git, curl.

## Caveats

- `sh` is invoked by make via absolute /bin/sh for every recipe line —
  PATH shims never see those. Its true count is the largest of all.
- Absolute-path invocations (`/usr/bin/env`, hardcoded paths) bypass shims.
- The build phase depends on whether the engine arrives prebuilt or as
  source. This measurement is the prebuilt path, which is what CI runs and
  what `make engine` gives on both platforms with an artifact row. A tree
  built against engine sources would put cc, ld, as, strip and codesign back
  into the build phase.
- The digest rows name whichever tool the host has first: on a host without
  sha256sum they read shasum.
- Not measured: full `make test` extras (conformance, doctest, doc-x,
  lint-x, examples, check-package) and release targets.

## Reproducing

For every executable in every PATH directory, write a wrapper into a shim
directory (first PATH hit wins) that logs its own name and execs the real
binary by its absolute path, so no wrapper resolves anything through PATH:

```sh
printf '#!/bin/sh\necho %s >> "%s"\nexec "%s" "$@"\n' "$name" "$log" "$real"
```

Skip names with characters outside `A-Za-z0-9._+-`, and quote the real path:
a PATH directory may hold a space.

Then run each phase with the shim directory prepended to PATH, snapshotting
the log between phases:

1. `rm -f x-bin && make` — the build. (With an engine checkout rather than an
   artifact, touch one of its `src/*.c` first to force compile + link + sign.)
2. `make test-fast`
3. `make install DESTDIR=<sandbox>`

`sort | uniq -c | sort -rn` over the combined logs yields the table above.
Re-measure after adding or retiring a tool, and when widening coverage to the
full `make test` and release targets.
