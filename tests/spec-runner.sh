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

# Detect timeout command. This whole-process timeout IS the runaway guard: it
# kills a hung/runaway interpreter before it can OOM-lock the machine, and the
# AWK runner now reports every test the kill interrupted as a failure (a missing
# result is a failure), so a runaway turns the suite red instead of hanging or
# silently passing. Linux: timeout, macOS: gtimeout (from coreutils), else none.
# The timeout is generous on purpose: it must absorb a heavy spec's lib load
# (e.g. compile.x is ~6s warm / ~20s cold) plus parallel contention without a
# false kill (a too-tight 30s killed the compile spec under load). Longer
# timeout for applicative (stress) tests. Personality runners can override
# TIMEOUT_UNIT_SECS / TIMEOUT_APPL_SECS.
_TIMEOUT_BIN=""
if command -v timeout >/dev/null 2>&1; then
  _TIMEOUT_BIN="timeout"
elif command -v gtimeout >/dev/null 2>&1; then
  _TIMEOUT_BIN="gtimeout"
fi
TIMEOUT_UNIT=""
TIMEOUT_APPL=""
if [ -n "$_TIMEOUT_BIN" ]; then
  TIMEOUT_UNIT="$_TIMEOUT_BIN ${TIMEOUT_UNIT_SECS:-60}"
  TIMEOUT_APPL="$_TIMEOUT_BIN ${TIMEOUT_APPL_SECS:-120}"
fi

# Memory runaway guard (complements the wall-time timeout above). The timeout
# bounds CPU/wall-time; this bounds MEMORY: the interpreter stops a runaway ./x
# once its allocated-object count reaches the ceiling, instead of allocating
# until the machine locks up or reboots. Portable: the interpreter limits
# itself, so it works identically on macOS (where `ulimit -v` is a no-op for
# address space) and the Pi. The interpreter reads no environment (no stdlib
# dependency), so spec-runner.awk feeds `(alloc-limit! $X_ALLOC_LIMIT_OBJS)`
# ahead of each library load, arming the guard before the load burst. Override
# per box; 0 disables.
#
# This is a RUNAWAY ceiling, not a tight bound. There is no auto-GC, so a batch
# accumulates all its parse-time and per-snippet garbage until the process
# exits, and the ceiling must clear the heaviest LEGIT batch. Binding case
# (measured against a green suite): the logo spec -- its test lib alone loads
# ~98M objects and the 72-test batch crosses 150M (fails at 150M, passes at
# 250M); ext/complex peaks ~130M. The default is 300M (~14 GB at ~48 B/obj on
# a 64-bit box): ~2x the heaviest batch, so it trips only a genuinely unbounded
# loop -- which would otherwise grow without limit -- before it eats the
# machine. RE-MEASURE when heavy batches change: a too-low ceiling fails good
# specs (died mid-batch), which is exactly how 150M failed once logo went
# green. LOWER it on a small-RAM box (a 512 MB Pi wants a few M -- the guard
# then stops the tower/logo loads themselves, turning a lockup into a failed
# spec). NOTE: a per-process guard cannot fix memory exhaustion from many heavy
# specs loading in PARALLEL; for that lower PARALLEL_JOBS.
export X_ALLOC_LIMIT_OBJS="${X_ALLOC_LIMIT_OBJS:-300000000}"

# Fail OPEN on a malformed value: a non-numeric limit (e.g. "150M") would
# otherwise tokenize as two forms -- (alloc-limit! 150 M) -- arming a
# 150-object limit that kills every test process at startup.
case "$X_ALLOC_LIMIT_OBJS" in
  ''|*[!0-9]*)
    printf '%bWARNING: X_ALLOC_LIMIT_OBJS="%s" is not a whole number; memory guard disabled%b\n' \
      "$ANSI_RED" "$X_ALLOC_LIMIT_OBJS" "$ANSI_RESET" >&2
    X_ALLOC_LIMIT_OBJS=0
    export X_ALLOC_LIMIT_OBJS
    ;;
esac

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
# spec file (dozens) at once, producing spurious "empty output" failures that
# shift run-to-run. The bottleneck is MEMORY BANDWIDTH, not CPU: each ./x's lib
# load is allocation-heavy, so one job per core thrashes the memory subsystem and
# slows the heaviest spec ~10x (compile.x load: ~6s -> >60s) until it trips the
# timeout. One job per core flakes; ~2/3 of the cores leaves enough bandwidth
# headroom to stay stable while recovering ~10% over half (verified: 2/2 clean
# runs at 8 on a 12-core box, ~245s vs ~270s). Override with PARALLEL_JOBS
# (=1 serial; lower it on a memory-constrained box like a Pi).
_cpus=$( (command -v nproc >/dev/null 2>&1 && nproc) || sysctl -n hw.ncpu 2>/dev/null )
case "$_cpus" in ''|*[!0-9]*) _cpus=4 ;; esac
_cpus=$(( _cpus * 2 / 3 ))
[ "$_cpus" -lt 2 ] && _cpus=2
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
  # SPECS (a glob pattern, e.g. '*list*') narrows the run for fast iteration; unset = all.
  [ -n "$SPECS" ] && { case "$_spec" in $SPECS) : ;; *) continue ;; esac; }
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

# Collect counts. A missing .cnt means that spec's AWK job died before writing
# results (OOM-kill, crash): reset the temps so a dead job can't silently carry
# the previous spec's counts, surface it loudly, and force a non-zero exit -- a
# lost spec must never read as success.
_I=0
_MISSING=0
while [ "$_I" -lt "$_N" ]; do
  _T=0; _F=0; _P=0
  if [ -f "$_TMPDIR/spec-$_I.cnt" ]; then
    read -r _T _F _P < "$_TMPDIR/spec-$_I.cnt"
  else
    _MISSING=$((_MISSING + 1))
    printf '\n%bWARNING: spec job %d produced no results (killed? OOM?)%b\n' \
      "$ANSI_RED" "$_I" "$ANSI_RESET" >&2
  fi
  TEST_COUNT=$((TEST_COUNT + _T))
  FAIL_COUNT=$((FAIL_COUNT + _F))
  PENDING_COUNT=$((PENDING_COUNT + _P))
  _I=$((_I+1))
done
rm -rf "$_TMPDIR"

# Summary.
if [ "$FAIL_COUNT" -gt 0 ] || [ "$_MISSING" -gt 0 ]; then
  SUMMARY_COLOR="$ANSI_RED"
else
  SUMMARY_COLOR="$ANSI_GREEN"
fi
printf '\n\n%b%d tests, %d failed, %d pending%b' \
  "$SUMMARY_COLOR" "$TEST_COUNT" "$FAIL_COUNT" "$PENDING_COUNT" "$ANSI_RESET"
if [ "$_MISSING" -gt 0 ]; then
  printf '%b (%d spec job(s) produced no results)%b' "$ANSI_RED" "$_MISSING" "$ANSI_RESET"
fi
printf '\n'

# Exit non-zero on failure (or if any spec job vanished).
[ "$FAIL_COUNT" -eq 0 ] && [ "$_MISSING" -eq 0 ]
