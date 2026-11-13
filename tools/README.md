# tools/ -- taxonomy and charter

| Directory | What lives here |
|---|---|
| `contract/` | Machine-readable single sources of truth: what x-lang needs from an engine (`requires.x`) and the engine contract's vocabulary (`features.x`, the compliance specs, `gen-engine-xon.sh`), what a lang may rely on (`seam.x`, `langs.x`), and the ratchet budgets (`bare-globals.x`, `percent-globals.x`, `private-reads.x`, `shared-privates.x`, `constraints.x`, the doc vocabularies).  These are the SPEC of the system, not tooling.  The C binding surface and object layout moved to the engine with the C source. |
| `check/` | Everything `make gates` / `make test` drives.  One file per gate; the Makefile target names are the stable external contract, and `make help` is their catalogue -- the scripts are not listed again here. |
| `engine/` | The engine pin (`engine.pin.xon`) and the scripts that fetch the engine it names, bump it, and refuse a directory it does not name. |
| `lang-kit/` | What a lang bundle's own build runs against this tree: the spec harness generator, the lint, the provide and duplicate-definition checks, the release references.  [docs/lang-contract.md](../docs/lang-contract.md) is the reference. |
| `release/` | Artifact production: amalgam generation, binary tarballs, the release manifest, macOS signing. |
| `dev/` | Conveniences: formatter, linter, coverage, benchmarks, images, doc generation.  See `dev/README.md`. |
| `fuzz/` | Cross-engine differential input: a deterministic batch of forms both engines evaluate. |
| `roots/` | Regenerates `lib/x/net/mozilla-roots.pem` from Mozilla's list. |
| `lib/` | Shared shell helpers for the scripts above (`guard.sh`, a wall-time ceiling an interrupt can stop). |
| `tests/` | The tools' own spec suite (`make test-tools`). |

## Shell policy: logic lives in x

Tool LOGIC is written in x-lang -- entry scripts here or modules under
`lib/x/tool/`.  Shell survives in exactly four sanctioned roles:

1. **Process orchestration around the engine** -- building or booting the
   binary under test, pty allocation, per-spec subprocess isolation and
   timeouts, tar/codesign, profiling binaries.  A gate that must observe
   the engine from OUTSIDE (`amalgam-smoke`, `pin-smoke`,
   `bootstrap-smoke`) cannot run inside it.
2. **The C-artifact contract scans** -- these live in the engine's repository,
   beside the C source they audit (`check/isa.sh`, `check/obj-layout.sh`,
   `check/base-paths.sh`, the base-layout header generator).  They must
   keep working when the interpreter build is broken -- independence from
   `x-bin` is a feature, not a shell habit.
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
   File lists ride shell `find | sort` onto argv -- the boot-order
   pattern: shell enumerates, x analyzes.
4. **Thin launch glue where an engine variant is required**
   (`dev/cov.sh` needs `x-bin-profile`).

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
- A script that cleans up on the way out sets the cleanup as its `EXIT`
  trap, with `trap 'exit 130' INT` and `trap 'exit 143' TERM` beside it.
  The exit runs the `EXIT` trap, so the cleanup runs once and the script
  stops.  A trap action for `INT` or `TERM` that does not exit returns to
  the script when it finishes, so the script carries on past the signal
  and `timeout` cannot stop it.
