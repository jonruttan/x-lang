#!/bin/sh
# doc-examples.sh -- execute the worked examples in the prose docs.
#
# The prose docs write examples the same way docs/spec.md does -- a fenced
# `EXPR -> EXPECTED` line -- and until now only spec.md was ever run.  The
# other two files carrying that format held 235 assertions that nothing had
# executed, and running them found retired primitives still documented as
# live, list functions documented as bare globals years after they moved onto
# classes, and three swapped argument orders (#452, #453).
#
# Which docs run, at what heading level, under which dialect, and whether
# failures are fatal is tools/check/doc-examples.conf -- see that file for the
# gate/report promotion rule.  This script is the driver; the extraction is
# tools/check/spec-examples.sh.
#
#   sh tools/check/doc-examples.sh          # every doc in the conf
#   sh tools/check/doc-examples.sh docs/primitives.md   # just one
#
# Report-only docs are NOT quiet: their failure counts print on every run and
# the summary names them.  A doc whose examples are unchecked has to say so.
set -e

ROOT=$(cd "$(dirname "$0")/../.." && pwd)
cd "$ROOT"

CONF="${CONF:-tools/check/doc-examples.conf}"
OUTROOT="${OUTROOT:-build/doc-example-specs}"
ONLY="$1"

# The harness colours its output even when redirected, and the tallies below
# are read back out of the log.  A `\x1b` in a sed pattern is a GNU extension
# -- BSD sed reads it as a literal `x`, so the strip silently becomes a no-op
# on macOS.  Build the escape with printf instead; this runs on both CI OSes.
ESC=$(printf '\033')
strip_ansi() { sed "s/${ESC}\[[0-9;]*m//g" "$1"; }

[ -f "$CONF" ] || { echo "doc-examples: no such conf: $CONF" >&2; exit 1; }

mkdir -p "$OUTROOT"
failed=0
reported=0
ran=0

# Strip comments and blank lines; the conf is whitespace-delimited.
sed 's/#.*//' "$CONF" | while read -r doc level lib mode; do
  [ -n "$doc" ] || continue
  [ -z "$ONLY" ] || [ "$ONLY" = "$doc" ] || continue

  slug=$(basename "$doc" .md)
  out="$OUTROOT/$slug"
  section=$(awk -v n="$level" 'BEGIN { s=""; while (n-- > 0) s = s "#"; print s " " }')
  [ "$lib" = "-" ] && lib=""

  skips="$OUTROOT/$slug.skipped"
  DOC="$doc" SECTION="$section" DEFAULT_LIB="$lib" SKIPFILE="$skips" \
    sh tools/check/spec-examples.sh "$out" >/dev/null 2>/dev/null

  n_files=$(ls "$out" 2>/dev/null | wc -l | tr -d ' ')
  n_tests=$(cat "$out"/*.spec.md 2>/dev/null | grep -c '^### ' || true)
  n_skip=$(wc -l < "$skips" 2>/dev/null | tr -d ' ')
  [ -n "$n_skip" ] || n_skip=0

  log="$OUTROOT/$slug.log"
  # The runner returns non-zero on failures; this driver decides what that
  # MEANS per the conf, so do not let set -e make that call for us.
  if SPEC_PATH="$out" sh tests/x/spec-example-runner.sh > "$log" 2>&1; then
    rc=0
  else
    rc=$?
  fi

  n_fail=$(strip_ansi "$log" | sed -n 's/.*[0-9]* tests, \([0-9]*\) failed.*/\1/p' | tail -1)
  [ -n "$n_fail" ] || n_fail=0

  printf 'doc-examples: %-26s %3s checked / %3s files  %s failed  %s unchecked  [%s]\n' \
    "$doc" "$n_tests" "$n_files" "$n_fail" "$n_skip" "$mode"

  if [ "$n_fail" -gt 0 ]; then
    strip_ansi "$log" | grep '^FAIL' | sed 's/^/  /'
  fi

  # An example the extractor cannot run is not a passing example. Naming the
  # reasons keeps "0 failed" from reading as "everything here is verified".
  if [ "$n_skip" -gt 0 ]; then
    awk -F'\t' '{ n[$3]++ } END { for (r in n) printf "  unchecked: %3d  %s\n", n[r], r }' "$skips"
    [ -z "$SKIP_DETAIL" ] || awk -F'\t' '{ printf "    %s:%s  %s\n", $1, $2, $4 }' "$skips"
  fi

  case "$mode" in
    gate)   [ "$rc" -eq 0 ] || echo "$doc" >> "$OUTROOT/.failed" ;;
    report) [ "$n_fail" -eq 0 ] || echo "$doc" >> "$OUTROOT/.reported" ;;
    *)      echo "doc-examples: unknown mode '$mode' for $doc" >&2
            echo "$doc" >> "$OUTROOT/.failed" ;;
  esac
done

# The while loop runs in a subshell (it is the tail of a pipe), so tallies come
# back through files rather than variables.
if [ -s "$OUTROOT/.failed" ]; then
  echo "doc-examples: FAIL -- gated docs with failing examples:" >&2
  sed 's/^/  /' "$OUTROOT/.failed" >&2
  rm -f "$OUTROOT/.failed" "$OUTROOT/.reported"
  exit 1
fi

if [ -s "$OUTROOT/.reported" ]; then
  echo "doc-examples: ok (report-only docs still failing, not gated:" \
       "$(tr '\n' ' ' < "$OUTROOT/.reported"))"
else
  echo "doc-examples: ok"
fi
rm -f "$OUTROOT/.failed" "$OUTROOT/.reported"
