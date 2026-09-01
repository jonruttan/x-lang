#!/bin/sh
# diff-engines.sh -- cross-engine differential fuzzing.
#
# Two independent engines pass the same suite; this driver probes what the
# suite does not reach.  It generates a deterministic batch of forms
# (tools/fuzz/diff-gen.x), runs the SAME batch through both engines, and
# diffs the line-aligned output: any differing line is an engine
# divergence or a behaviour the suite never pinned -- each becomes a spec
# check or a bug, never a shrug.
#
# Usage:
#   X_BIN_A=engine-a X_SEAM_A=engine-a-root \
#   X_BIN_B=engine-b X_SEAM_B=engine-b-root \
#     sh tests/x/diff-engines.sh [SEED [COUNT [DEPTH]]]
#
# The SEAM roots are what each binary's `engine` symlink must point at --
# the library boots through engine/tools/contract, and the stage-0 seam
# guard refuses a mismatched one, so each engine runs in its own scratch
# directory carrying its own link.
#
# Defaults: SEED=20260901 COUNT=300 DEPTH=5, lib $DIFF_LIB (lib/x-base.x,
# tree-relative).  A mismatch prints the line number, both outputs, and
# the offending form; rerunning with the same arguments reproduces it
# exactly.  Exit 1 on any mismatch.
set -e
ROOT="$(cd "$(dirname "$0")/../.." && pwd)"
SEED="${1:-20260901}"
COUNT="${2:-300}"
DEPTH="${3:-5}"
LIB="${DIFF_LIB:-lib/x-base.x}"
: "${X_BIN_A:?set X_BIN_A to the first engine binary}"
: "${X_BIN_B:?set X_BIN_B to the second engine binary}"
: "${X_SEAM_A:?set X_SEAM_A to the first engine's contract root}"
: "${X_SEAM_B:?set X_SEAM_B to the second engine's contract root}"

TMP=$(mktemp -d)
trap 'rm -rf "$TMP"' EXIT

# A run directory per engine: the tree's lib, that engine's seam.
rundir() { # $1 = name, $2 = seam root
  mkdir -p "$TMP/$1"
  ln -s "$ROOT/lib" "$TMP/$1/lib"
  ln -s "$ROOT/tools" "$TMP/$1/tools"
  ln -s "$2" "$TMP/$1/engine"
}
rundir a "$X_SEAM_A"
rundir b "$X_SEAM_B"

# One generation, on engine A: the batch is text, so which engine wrote
# it cannot bias the comparison.
( cd "$TMP/a" && { printf '(alloc-limit! 1500000000)\n'; cat "$LIB"; cat tools/fuzz/diff-gen.x; } \
  | "$X_BIN_A" -- "$SEED" "$COUNT" "$DEPTH" ) > "$TMP/forms.x" 2>"$TMP/gen-err.txt" || {
    echo "diff-engines: generation failed:" >&2
    tail -3 "$TMP/gen-err.txt" >&2
    exit 2
  }

run() { # $1 = run dir, $2 = engine binary, $3 = output file
  ( cd "$TMP/$1" && { printf '(alloc-limit! 1500000000)\n'; cat "$LIB"; cat "$TMP/forms.x"; } \
    | "$2" ) > "$3" 2>/dev/null || true
}
run a "$X_BIN_A" "$TMP/out-a.txt"
run b "$X_BIN_B" "$TMP/out-b.txt"

LA=$(wc -l < "$TMP/out-a.txt" | tr -d ' ')
LB=$(wc -l < "$TMP/out-b.txt" | tr -d ' ')
# Output lines map to CASES: the interleaved (Heap collect) lines print
# nothing, so the batch file is filtered before any line-number lookup.
grep -v "(Heap collect)" "$TMP/forms.x" > "$TMP/cases.x"

if [ "$LA" != "$COUNT" ] || [ "$LB" != "$COUNT" ]; then
  echo "diff-engines: TRUNCATED RUN (a=$LA b=$LB of $COUNT) -- an engine died mid-batch."
  echo "  first form after the shorter output is the killer; seed=$SEED depth=$DEPTH"
  N=$(( (LA < LB ? LA : LB) + 1 ))
  sed -n "${N}p" "$TMP/cases.x"
  exit 1
fi

if cmp -s "$TMP/out-a.txt" "$TMP/out-b.txt"; then
  echo "diff-engines: $COUNT cases agree (seed=$SEED depth=$DEPTH)"
  exit 0
fi

echo "diff-engines: DIVERGENCE (seed=$SEED depth=$DEPTH)"
n=0
paste_delim=$(printf '\t')
awk 'NR==FNR{a[FNR]=$0;next} a[FNR]!=$0{print FNR"\t"a[FNR]"\t"$0}' \
  "$TMP/out-a.txt" "$TMP/out-b.txt" | while IFS="$paste_delim" read -r line av bv; do
    echo "  line $line: A=$av B=$bv"
    echo "    form: $(sed -n "${line}p" "$TMP/cases.x")"
  done
exit 1
