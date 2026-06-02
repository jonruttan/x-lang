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

# Speed regression detection (per-test).
# MAX_TEST_SECS: abort if any single test exceeds this (0=disable, default 10).
# SLOW_STREAK: abort after N consecutive tests taking >=1s each (0=disable, default 5).
: "${MAX_TEST_SECS:=10}"
: "${SLOW_STREAK:=5}"

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

# Cap concurrent jobs in PARALLEL mode. Without a cap the loop forks one job per
# spec file (dozens) at once; on a typical box that oversubscribes the CPUs and
# starves each ./x's lib load past the per-test timeout, producing spurious
# "empty output" failures that shift run-to-run. Default to the CPU count;
# override with PARALLEL_JOBS (e.g. =2 on a low-RAM Pi).
_cpus=$( (command -v nproc >/dev/null 2>&1 && nproc) || sysctl -n hw.ncpu 2>/dev/null )
case "$_cpus" in ''|*[!0-9]*) _cpus=4 ;; esac
: "${PARALLEL_JOBS:=$_cpus}"

# _throttle PID: record a just-launched background job and, once PARALLEL_JOBS
# are in flight, block on the oldest before returning. POSIX-portable (no
# `wait -n`): PIDs are tracked FIFO in _jobs_pids.
_jobs_running=0
_jobs_pids=""
_throttle() {
  _jobs_pids="${_jobs_pids}$1 "
  _jobs_running=$((_jobs_running + 1))
  if [ "$_jobs_running" -ge "$PARALLEL_JOBS" ]; then
    wait "${_jobs_pids%% *}" 2>/dev/null
    _jobs_pids="${_jobs_pids#* }"
    _jobs_running=$((_jobs_running - 1))
  fi
}

for _spec in "$SPEC_PATH"/*.spec.md "$SPEC_PATH"/*/*.spec.md; do
  [ -f "$_spec" ] || continue
  case "$_spec" in */applicative/*) continue ;; esac
  _I=$_N
  _N=$((_N+1))
  _t0=$(date +%s)
  if [ -n "$PARALLEL" ]; then
    (
      awk -v X_BIN="$X_BIN" \
          -v LANG_LIB="$LANG_LIB" \
          -v REPL_CMD="${REPL_CMD:-(repl)}" \
          -v READ_FN="${READ_FN:-read}" \
          -v TIMEOUT_CMD="$TIMEOUT_UNIT" \
          -v MAX_TEST_SECS="$MAX_TEST_SECS" \
          -v SLOW_STREAK="$SLOW_STREAK" \
          -v TMPDIR="$_TMPDIR" \
          -v SPEC_ID="$_I" \
          -f "$RUNNER" "$_spec"
    ) &
    _throttle "$!"
  else
    awk -v X_BIN="$X_BIN" \
        -v LANG_LIB="$LANG_LIB" \
        -v REPL_CMD="${REPL_CMD:-(repl)}" \
        -v READ_FN="${READ_FN:-read}" \
        -v TIMEOUT_CMD="$TIMEOUT_UNIT" \
        -v MAX_TEST_SECS="$MAX_TEST_SECS" \
        -v SLOW_STREAK="$SLOW_STREAK" \
        -v TMPDIR="$_TMPDIR" \
        -v SPEC_ID="$_I" \
        -f "$RUNNER" "$_spec"
  fi
  _t1=$(date +%s); _dt=$((_t1 - _t0))
  if [ -z "$PARALLEL" ] && [ "$_dt" -gt 0 ]; then
    printf " [%s: %ds]" "$(basename "$_spec" .spec.md)" "$_dt"
  fi
done

# Applicative (stress) specs only run with STRESS=1.
if [ -n "$STRESS" ] && [ -d "$SPEC_PATH/applicative" ]; then
  for _spec in "$SPEC_PATH"/applicative/*.spec.md; do
    [ -f "$_spec" ] || continue
    _I=$_N
    _N=$((_N+1))
    _t0=$(date +%s)
    if [ -n "$PARALLEL" ]; then
      (
        awk -v X_BIN="$X_BIN" \
            -v LANG_LIB="$LANG_LIB" \
            -v REPL_CMD="${REPL_CMD:-(repl)}" \
            -v READ_FN="${READ_FN:-read}" \
            -v TIMEOUT_CMD="$TIMEOUT_APPL" \
            -v MAX_TEST_SECS="$MAX_TEST_SECS" \
            -v SLOW_STREAK="$SLOW_STREAK" \
            -v TMPDIR="$_TMPDIR" \
            -v SPEC_ID="$_I" \
            -f "$RUNNER" "$_spec"
      ) &
      _throttle "$!"
    else
      awk -v X_BIN="$X_BIN" \
          -v LANG_LIB="$LANG_LIB" \
          -v REPL_CMD="${REPL_CMD:-(repl)}" \
          -v READ_FN="${READ_FN:-read}" \
          -v TIMEOUT_CMD="$TIMEOUT_APPL" \
          -v MAX_TEST_SECS="$MAX_TEST_SECS" \
          -v SLOW_STREAK="$SLOW_STREAK" \
          -v TMPDIR="$_TMPDIR" \
          -v SPEC_ID="$_I" \
          -f "$RUNNER" "$_spec"
    fi
    _t1=$(date +%s); _dt=$((_t1 - _t0))
    if [ -z "$PARALLEL" ] && [ "$_dt" -gt 0 ]; then
      printf " [%s: %ds]" "$(basename "$_spec" .spec.md)" "$_dt"
    fi
  done
fi

wait

# Collect counts and timing.
_I=0
_TOTAL_LOAD_MS=0
_TOTAL_TEST_MS=0
_SLOWEST_TEST=""
_SLOWEST_MS=0
while [ "$_I" -lt "$_N" ]; do
  read _T _F _P < "$_TMPDIR/spec-$_I.cnt"
  TEST_COUNT=$((TEST_COUNT + _T))
  FAIL_COUNT=$((FAIL_COUNT + _F))
  PENDING_COUNT=$((PENDING_COUNT + _P))
  # Aggregate timing if available
  if [ -f "$_TMPDIR/spec-$_I.time" ]; then
    while IFS='	' read -r _COL1 _COL2 _COL3; do
      if [ "$_COL1" = "load" ]; then
        _TOTAL_LOAD_MS=$((_TOTAL_LOAD_MS + _COL2))
      else
        _MS="${_COL3:-0}"
        _TOTAL_TEST_MS=$((_TOTAL_TEST_MS + _MS))
        if [ "$_MS" -gt "$_SLOWEST_MS" ] 2>/dev/null; then
          _SLOWEST_MS="$_MS"
          _SLOWEST_TEST="$_COL1: $_COL2"
        fi
      fi
    done < "$_TMPDIR/spec-$_I.time"
  fi
  _I=$((_I+1))
done
rm -rf "$_TMPDIR"

# Summary.
if [ "$FAIL_COUNT" -gt 0 ]; then
  SUMMARY_COLOR="$ANSI_RED"
else
  SUMMARY_COLOR="$ANSI_GREEN"
fi
_LOAD_S=$((_TOTAL_LOAD_MS / 1000))
_LOAD_FRAC=$(( (_TOTAL_LOAD_MS % 1000) / 100 ))
_TEST_S=$((_TOTAL_TEST_MS / 1000))
_TEST_FRAC=$(( (_TOTAL_TEST_MS % 1000) / 100 ))
_SLOW_S=$((_SLOWEST_MS / 1000))
_SLOW_FRAC=$(( (_SLOWEST_MS % 1000) / 100 ))
printf '\n\n%b%d tests, %d failed, %d pending%b' \
  "$SUMMARY_COLOR" "$TEST_COUNT" "$FAIL_COUNT" "$PENDING_COUNT" "$ANSI_RESET"
if [ "$_TOTAL_LOAD_MS" -gt 0 ] 2>/dev/null; then
  printf ' (load: %d.%ds, test: %d.%ds' "$_LOAD_S" "$_LOAD_FRAC" "$_TEST_S" "$_TEST_FRAC"
  if [ "$_SLOWEST_MS" -gt 0 ] 2>/dev/null; then
    printf ', slowest: %d.%ds %s' "$_SLOW_S" "$_SLOW_FRAC" "$_SLOWEST_TEST"
  fi
  printf ')'
fi
printf '\n'

# Exit non-zero on failure.
[ "$FAIL_COUNT" -eq 0 ]
