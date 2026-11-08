# Bundle checklist

Recurring defects in lang bundles and their tools. Each entry names the
defect, how to check a bundle for it, and the remedy. An entry tied to a
release says which; it can go once every bundle declares a later one. The
build itself is described in [Crafting a Lang](crafting-a-lang.md), and what a
bundle may rely on in [The Lang Contract](lang-contract.md).

## Garbage collection and memory

### G1. Collection is the application's
x collects only when asked. A bundle that drives its own loop (a game, a
REPL, a line filter) places its own `(Heap collect)`.
- **Check:** grep the driver loops (per key, per line, per level, per file)
  for `Heap collect`. Run a long session and watch the footprint. Two
  `(Heap count)` readings with no collect between them give the objects one
  step makes.
- **Remedy:** collect where the large garbage is, not on every step: after a
  level or a file, or every N lines or bytes (x-coreutils' `%cu-sweep-at`
  sweeps every 2048 bytes or 64 lines). A collect costs about 0.1 s in a spec
  process and about 1.6 s at 39M live objects, so a collect per key or per
  short line costs more than the work.

### G2. A spec file split to fit memory
Splitting a spec file lowers its peak without lowering what the code leaks.
- **Check:** the peak footprint of each spec file (`/usr/bin/time -l` on
  macOS, `/usr/bin/time -v` on Linux). A peak in gigabytes for a short file
  points at the code under test.
- **Remedy:** collect in the code (G1). Split files only for time (S1).

### G3. An object kept only in a second base
An object made on this heap and stored only inside another base (`Base make`,
`make-tok`, a base cell) is freed by the collect after next. The image
writer's child collects after every include, so it shows there first.
- **Check:** grep for `Base make`, `make-tok`, `base-bind`, and `%set-first!`
  into a base's cell. A spec that runs two `(Heap collect)`s and then reads
  through the base.
- **Remedy:** `(Heap pin! obj)`, which answers nil, or a copy on this heap
  (x-ash's `%sh-tok-own`).

### G4. More slots than `set-units!`
A `%make-obj TYPE n` with more slots than the type's `set-units!` leaves the
extra slots unmarked: a use-after-free that waits for a collect.
- **Check:** each type's `%make-obj` slot counts against its `set-units!`.
  The symptom is a nil inside a list the code has just built.
- **Remedy:** change `set-units!` in the same edit that adds the slot.

### G5. Allocation in a mark hook
A `Heap mark-hook!` body that allocates crashes the collector.
- **Check:** grep for `mark-hook!` and read each hook body.
- **Remedy:** no allocation in a mark hook.

### G6. Continuations outside the object ceiling
A `call/cc` stack copy is malloc'd, so `X_ALLOC_LIMIT_OBJS` does not count
it; a generator loop can reach gigabytes under the ceiling.
- **Check:** grep for `call/cc`.
- **Remedy:** `(Cont capture f)`; two or three generator-heavy cases a spec
  file.

### G7. A large source file's load garbage
A file's load garbage lives until the file ends: a large evaluator file can
take a load from 0.3M to over 20M objects, and an image write to several
gigabytes.
- **Check:** the peak footprint of `x --image -l NAME`.
- **Remedy:** a collect before the section headers of large files (x-ash#223,
  x-python#203); `x/boot/tower-compiled` for compiled reader analysers.

### G8. A runner knob that outlives its cause
`SPEC_SEAM_COLLECT=0`, `SPEC_BATCH` and `X_ALLOC_LIMIT_OBJS` in a bundle's
`tests/spec-runner.sh` each answer one defect. Once the declared release
fixes it, the knob only costs memory: x-python's peak fell from 5.9 to 3.2 GB
with seam collects back on.
- **Check:** grep `tests/spec-runner.sh` for each knob and its comment's
  issue number; read whether the issue is closed in the declared release.
- **Remedy:** delete the knob.

### G9. An object ceiling above the runner's memory
The default ceiling, 300M objects (about 14 GB), is close to a 16 GB hosted
runner. A job past the runner's memory dies with no tally:
`spec-gate: killed by SIGTERM`, or exit 143.
- **Check:** grep for raised `X_ALLOC_LIMIT_OBJS`; each raise is scoped to
  the one path that needs it.
- **Remedy:** reduce the memory (G1, G7) rather than raise the ceiling.

### G10. Measurement that allocates
`(Heap count)` walks the heap (about 1.2 s at 72M objects); each `prim-ref`
call makes about 20 KB.
- **Check:** grep for `prim-ref` inside fn bodies and loops.
- **Remedy:** bind each `prim-ref` once at load; for a cheap object count,
  `(%reflect-base-cell (lit alloc-count))`.

## State images and CI

### I1. A bundle without CI
A bundle with no CI workflow is checked only by whoever runs its suite last,
on one machine and one release; its pull requests show no checks.
- **Check:** `gh api repos/OWNER/REPO/contents/.github/workflows` answers
  404, or no workflow calls x-lang's `bundle.yml`.
- **Remedy:** `.github/workflows/ci.yml` calling
  `jonruttan/x-lang/.github/workflows/bundle.yml@main` on push to main, pull
  requests and a weekly schedule. It runs `tests/spec-gate.sh` against the
  declared release, and against main except on a pull request, on Linux
  x86-64, Linux arm64 and macOS unless the `os` input names other runners.

### I2. The suite boots from source on CI
Bundle CI runs an x-lang checkout (`.x-lang/x.sh`). A checkout's `x.sh` reads
`lib/` from the current directory, so a bundle script that runs `"$X"` from
the bundle directory works with an installed x and fails on CI. When that
script is an image probe, the suite falls back to booting from source.
- **Check:** a CI spec job's log: `image-build: writing` and no "boots from
  source" line. In the bundle, every `"$X"` run outside the platform runner.
- **Remedy:** run x from the platform's root,
  `(cd "$("$X" --share-dir)" && "$X" -f FILE)`, and print a probe's stderr
  when it fails.

### I3. A probe every declared release passes
A capability probe for a fix the declared release already carries can only
fail for another reason, and its message then names the wrong one.
- **Check:** for each probe in `tests/`, the release that brought the fix,
  against `(requires-release ...)` in `lang.xon`.
- **Remedy:** delete the probe.

### I4. Runner logic copied across bundles
A block copied into many bundles' `tests/spec-runner.sh` carries one defect
into all of them.
- **Check:** `md5` the same block across the bundles' runners.
- **Remedy:** move it into the platform runner or the lang kit, behind a knob
  a bundle sets.

### I5. A stale image after an edit
`x -l NAME` boots from an image keyed by the bundle's path, not its contents.
The spec runner's image is keyed on contents.
- **Check:** an edit, then a run from the same `X_LANG_DIR`.
- **Remedy:** a fresh langs directory after an edit, or an empty
  `~/.cache/x/images/`.

### I6. Modules the image key does not hash
The image key hashes `.x` files; modules with another extension (x-r5rs's
`.scm`) do not rewrite the image.
- **Check:** the bundle's module extensions against `IMG_KEY_EXT` in
  `tests/spec-runner.sh`.
- **Remedy:** name each extension in `IMG_KEY_EXT`.

### I7. NUL bytes in a module-level buffer
The image writer copies strings to their first NUL, so a module-level buffer
holding a NUL comes back short.
- **Check:** top-level `%make-str`, `Bytes of-hex` with `00`,
  `Bytes of-list (0`. A test that fails from the image and passes with
  `IMG=0`.
- **Remedy:** build the buffer per call.

### I8. Per-process state fixed at load
A second base, a session, `$$`, colour or a signal handler fixed at load is
wrong in every process that loads the image.
- **Check:** the writer's log says `unnameable: 0`; `X_IMG_WHO=1` names the
  holders.
- **Remedy:** build it on first use, or rebuild it from a replayable table
  (x-python#42).

### I9. A missing import the specs cannot see
The spec harness loads the whole platform and the kit lint preloads sibling
modules, so a module with a missing import passes every spec and fails from
its image or in x-os.
- **Check:** per module, the sibling names it uses minus its imports and
  defs; then the command from the image (`x -l NAME ...`) or in
  `docker.io/jonruttan/x-os:latest`.
- **Remedy:** add the import.

### I10. A pin moved past an untested release
- **Check:** the suite on the tag before `(requires-release ...)` moves; for
  a failure on the main leg only, `git log v<declared>..origin/main --
  tools/lang-kit`.
- **Remedy:** move the pin once the tag's suite passes. Until a bundle has CI
  (I1), its PR body carries the local tally.

## Specs and the runner

### S1. A spec file past the CI time limit
A job's time limit is `TIMEOUT_UNIT_SECS` times the files in its bucket (one
file with `SPEC_BATCH=1`, scaled by `@timeout-scale`), and a hosted Linux
runner is about twice as slow as an M-series Mac.
- **Check:** per-file times from a local run, each under about 40% of the
  limit.
- **Remedy:** split for time, never for memory (G2), or make the code faster.

### S2. "interpreter died mid-batch"
- A fast (about 1 s) silent death is C-stack depth: exit 139 that passes
  under `ulimit -s 65520`. Remedy: a tail shape.
- A slow death with `allocation limit exceeded` is a runaway loop.
- A wall of identical deaths is the ceiling; the first failure is the cause.
- `Unterminated input` is a source file rewritten during the run.

### S3. Globals shared between spec files
A batch runs several files in one process, and a top-level `def` in a spec
rebinds a root global (`lit`, `%base`, an applet name). The symptom is
`Error: ()` or a 139 far from the cause.
- **Check:** `grep -E '\(def NAME( |$)'` over the bundle and `lib/`;
  `IMG=0 SPEC_BATCH=8` reproduces a CI bucket.
- **Remedy:** spec helpers named `%SUBJECT-name`; each case sets what it
  reads.

### S4. A spec run that runs nothing
A spec file passed through `SPEC_PATH` (a directory) runs 0 tests and
passes. "0 tests, 0 failed" is a non-run.
- **Remedy:** pass the spec file as an argument.

### S5. A heavy file in a bucket
An undeclared heavy file pushes its neighbours past the bucket's timeout.
- **Remedy:** `# @weight N` and `# @timeout-scale N` on the heavy file.

## Code

- **C1.** `(first ())` and `(rest ())`: the globals are guarded from
  x-lang#1135, but a load-time alias taken into an image is not. Test
  `null?` on argv and split results first.
- **C2.** The int doors fault on nil and wrap at 2^63: indices and lengths
  only.
- **C3.** `eq?` on vectors is neither identity nor structure: `same?`.
- **C4.** `Str8 sub` takes a start and a length. helium has no `int?`,
  `abs`, `min` or `max`.
- **C5.** A `match` clause holds one form; further forms are dropped.
- **C6.** Input read whole: a read that is lazy returns on `/dev/zero`.
- **C7.** GNU-only make: no `$(shell`, `ifeq` or `$(CURDIR)`; values
  computed at recipe time with `$$(...)`.

## Performance

- **P1.** Objects a call: `match` 0, `if` 10, `let` 120, `cond` 140; `match`
  for four or more arms.
- **P2.** A byte walk in x costs about 25 KB a byte: split text with the
  platform Lexer; `(Sys environ)` once a process.
- **P3.** A `List fold` or `reverse` entry is the dear part of a short walk; a
  local accumulating walk is about 10x faster (x-python#79).
- **P4.** `Vector make` is about 390 objects a slot; `Str8 split` makes about
  0.5 MB a 160-byte line (prefilter with `index-of`).
- **P5.** A class send walks about 200 objects and an `Assoc find` about
  25,000: hot slots through `obj-ref`, lookups as plain walks.
