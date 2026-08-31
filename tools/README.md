# tools/ -- taxonomy and charter

| Directory | What lives here |
|---|---|
| `contract/` | Machine-readable single sources of truth: the C binding surface (`isa.x`), object header layout (`obj-layout.x`), base-object slot tree (`base-layout.x`) and field paths (`base-paths.x`), the sanctioned bare top level (`bare-globals.x`), and the header generator (`gen-base-layout.awk`).  These are the SPEC of the system, not tooling; two of them are boot-closure includes. |
| `check/` | Everything `make gates` / `make test` drives.  One file per gate; the Makefile target names (`check-isa`, ...) are the stable external contract. |
| `release/` | Artifact production: amalgam generation, binary tarballs, the release manifest, macOS signing. |
| `dev/` | Conveniences: formatter, linter, coverage, benchmarks, doc generation.  See `dev/README.md`. |
| `lib/` | Shared shell helpers for the scripts above (`contract-diff.sh`). |
| `tests/` | The tools' own spec suite (`make test-tools`). |

## Shell policy: logic lives in x

Tool LOGIC is written in x-lang -- entry scripts here or modules under
`lib/x/tool/`.  Shell survives in exactly three sanctioned roles:

1. **Process orchestration around the engine** -- building or booting the
   binary under test, pty allocation, per-spec subprocess isolation and
   timeouts, tar/codesign, profiling binaries.  A gate that must observe
   the engine from OUTSIDE (`amalgam-smoke`, `pin-smoke`,
   `bootstrap-smoke`) cannot run inside it.
2. **The C-artifact contract scans** (`check/isa.sh`,
   `check/obj-layout.sh`, `check/base-paths.sh`, plus
   `contract/gen-base-layout.awk`).  These audit the C source and must
   keep working when the interpreter build is broken -- independence from
   `x-bin` is a feature, not a shell habit.  (The awk generator is also
   bootstrap-circular: it emits a header the C build needs.)
3. **Corpus-scanning ratchets** (`check/bare-globals.sh`,
   `check/path-literals.sh`, `check/dup-defs.sh`), for two measured
   reasons from the 2026-08 overhaul:
   - Per-byte textual scanning in interpreted x costs ~500 heap objects
     per byte (the evaluator allocates per form evaluated): one pass over
     the ~700KB scan set is 45-70s and pins the GC -- per gate, per push,
     per CI OS.  Blocked on C-side byte-scan doors (`str find-byte` /
     `io read-line`), proposed in the overhaul follow-ups.
   - The C-tokenizer route (`Tok read-str`) is blocked on a reader
     re-entrancy bug: a raw `#(` vector literal in the tokenized TEXT
     makes the handler read the vector's elements from the AMBIENT input
     port -- eating the calling script's own stdin (repro in the filed
     issue).  Until fixed, read-str over arbitrary source is unsafe.
   In-language directory enumeration is also off the table on cost
   (~355K heap objects per file for the interpreted dirent+stat decode);
   file lists ride shell `find | sort` onto argv -- the boot-order
   pattern: shell enumerates, x analyzes.
4. **Thin launch glue where an engine variant is required**
   (`dev/cov.sh` needs `x-bin-cov`).

Everything else runs as an x entry script:

```sh
sh x.sh --no-pin -q -f tools/<dir>/<tool>.x -- <args>
```

Flags after `--` land in the interpreter's `args`; there is no stdin data
channel (`-f` owns the pipe), so inputs are read by path.  Gates always
pass `--no-pin` (the pin probe walks up from the tool file) and arm the
allocation guard.

## Structural invariants

- Every script lives exactly one level below `tools/` (`tools/tests/*`
  is the depth-2 exception).  Repo root from a script is always
  `$(dirname "$0")/../..` -- if you need a deeper level, you are doing it
  wrong.
- Scripts locate siblings through `$ROOT/tools/...`, never through their
  own relative position.
- A gate's output contract (ok-line, failure strings, exit code) is part
  of the gate; changing it is a ratchet change and needs its own
  adjudication.
