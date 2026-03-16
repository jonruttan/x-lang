#!/bin/sh
# # Computational Expressions in C
#
# ## tests/spec-runner.sh -- Shared Test Runner
#
# @description AWK-based test runner for .spec.md format (PARALLEL=1 for concurrent)
# @author [Jon Ruttan](jonruttan@gmail.com)
# @copyright 2024 Jon Ruttan
# @license MIT No Attribution (MIT-0)
#
#     ., .,
#     {O,O}
#     (   )
#      " "
#
# Usage: Each personality runner sets SPEC_PATH, X_BIN, and LANG_LIB,
#        then sources this file.
#
#   SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
#   SPEC_PATH="$SCRIPT_DIR/specs"
#   X_BIN="$SCRIPT_DIR/../../x"
#   LANG_LIB="$SCRIPT_DIR/../../lib/x.x"
#   . "$SCRIPT_DIR/../spec-runner.sh"

ANSI_RESET="\033[0m"
ANSI_RED="\033[1;31m"
ANSI_GREEN="\033[1;32m"

# Detect timeout command (prevents runaway tests from OOM-killing the machine).
# Linux: timeout, macOS: gtimeout (from coreutils), fallback: none.
# Short timeout for unit tests, long for applicative (stress) tests.
# Personality runners can override TIMEOUT_UNIT_SECS / TIMEOUT_APPL_SECS.
_TIMEOUT_BIN=""
if command -v timeout >/dev/null 2>&1; then
  _TIMEOUT_BIN="timeout"
elif command -v gtimeout >/dev/null 2>&1; then
  _TIMEOUT_BIN="gtimeout"
fi
TIMEOUT_UNIT=""
TIMEOUT_APPL=""
if [ -n "$_TIMEOUT_BIN" ]; then
  TIMEOUT_UNIT="$_TIMEOUT_BIN ${TIMEOUT_UNIT_SECS:-30}"
  TIMEOUT_APPL="$_TIMEOUT_BIN ${TIMEOUT_APPL_SECS:-120}"
fi

# Derive project root from X_BIN (always at project root).
RUNNER="$(cd "$(dirname "$X_BIN")" && pwd)/tests/spec-runner.awk"

TEST_COUNT=0
FAIL_COUNT=0
PENDING_COUNT=0

# Run each .spec.md file through AWK runner.
# Set PARALLEL=1 to run specs concurrently.
# Counters are collected from temp files after all jobs finish.
_TMPDIR=$(mktemp -d)
_N=0
for _spec in "$SPEC_PATH"/*.spec.md; do
  [ -f "$_spec" ] || continue
  _I=$_N
  _N=$((_N+1))
  if [ -n "$PARALLEL" ]; then
    (
      awk -v X_BIN="$X_BIN" \
          -v LANG_LIB="$LANG_LIB" \
          -v REPL_CMD="${REPL_CMD:-(repl)}" \
          -v READ_FN="${READ_FN:-read}" \
          -v TIMEOUT_CMD="$TIMEOUT_UNIT" \
          -v TMPDIR="$_TMPDIR" \
          -v SPEC_ID="$_I" \
          -f "$RUNNER" "$_spec"
    ) &
  else
    awk -v X_BIN="$X_BIN" \
        -v LANG_LIB="$LANG_LIB" \
        -v REPL_CMD="${REPL_CMD:-(repl)}" \
        -v READ_FN="${READ_FN:-read}" \
        -v TIMEOUT_CMD="$TIMEOUT_UNIT" \
        -v TMPDIR="$_TMPDIR" \
        -v SPEC_ID="$_I" \
        -f "$RUNNER" "$_spec"
  fi
done

# Also run applicative specs unless UNIT_ONLY is set.
if [ -z "$UNIT_ONLY" ] && [ -d "$SPEC_PATH/applicative" ]; then
  for _spec in "$SPEC_PATH"/applicative/*.spec.md; do
    [ -f "$_spec" ] || continue
    _I=$_N
    _N=$((_N+1))
    if [ -n "$PARALLEL" ]; then
      (
        awk -v X_BIN="$X_BIN" \
            -v LANG_LIB="$LANG_LIB" \
            -v REPL_CMD="${REPL_CMD:-(repl)}" \
            -v READ_FN="${READ_FN:-read}" \
            -v TIMEOUT_CMD="$TIMEOUT_APPL" \
            -v TMPDIR="$_TMPDIR" \
            -v SPEC_ID="$_I" \
            -f "$RUNNER" "$_spec"
      ) &
    else
      awk -v X_BIN="$X_BIN" \
          -v LANG_LIB="$LANG_LIB" \
          -v REPL_CMD="${REPL_CMD:-(repl)}" \
          -v READ_FN="${READ_FN:-read}" \
          -v TIMEOUT_CMD="$TIMEOUT_APPL" \
          -v TMPDIR="$_TMPDIR" \
          -v SPEC_ID="$_I" \
          -f "$RUNNER" "$_spec"
    fi
  done
fi

wait

# Collect counts.
_I=0
while [ "$_I" -lt "$_N" ]; do
  read _T _F _P < "$_TMPDIR/spec-$_I.cnt"
  TEST_COUNT=$((TEST_COUNT + _T))
  FAIL_COUNT=$((FAIL_COUNT + _F))
  PENDING_COUNT=$((PENDING_COUNT + _P))
  _I=$((_I+1))
done
rm -rf "$_TMPDIR"

# Summary.
if [ "$FAIL_COUNT" -gt 0 ]; then
  SUMMARY_COLOR="$ANSI_RED"
else
  SUMMARY_COLOR="$ANSI_GREEN"
fi
printf '\n\n%b%d tests, %d failed, %d pending%b\n' \
  "$SUMMARY_COLOR" "$TEST_COUNT" "$FAIL_COUNT" "$PENDING_COUNT" "$ANSI_RESET"

# Exit non-zero on failure.
[ "$FAIL_COUNT" -eq 0 ]
