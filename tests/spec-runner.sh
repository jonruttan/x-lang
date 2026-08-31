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
# Usage: Each lang runner sets SPEC_PATH, X_BIN, and LANG_LIB,
#        then sources this file.
#
#   SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
#   SPEC_PATH="$SCRIPT_DIR/specs"
#   X_BIN="$SCRIPT_DIR/../../x-bin"
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
# timeout for applicative (stress) tests. Lang runners can override
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
# bounds CPU/wall-time; this bounds MEMORY: the interpreter stops a runaway ./x-bin
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
# machine.
#
# THE BINDING CASE HAS LEFT: the logo spec is x-logo's now, so the heaviest
# batch in THIS suite is ext/complex at ~130M.  The ceiling is deliberately
# NOT lowered to match -- what it has to clear is whatever the heaviest batch
# grows into next, and headroom is the point of a runaway guard.  The logo
# figures above stay because they are the measurement 300M was chosen from.
#
# RE-MEASURE when heavy batches change: a too-low ceiling fails good
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

# THE AWK HARNESS SITS BESIDE THIS FILE.  The default finds it the way it
# always has -- from the directory holding the engine, which in a checkout is
# the repo root, beside tests/.  That coupling is one of the three reasons the
# built engine lands at the repo root (see the Makefile's engine-split note).
#
# SPEC_RUNNER_DIR OVERRIDES IT, for a caller sourcing this runner out of an
# INSTALLED tree.  There the engine is under libexec/x/ and this harness under
# share/x/tests/, so the derivation below points at a path that was never going
# to exist -- the same addressing bug that dangled the old lang runners
# when they left the tree.  A lang bundle sets it from `x --share-dir`
# (docs/lang-contract.md).  The caller says because a SOURCED script
# cannot portably find its own path.
RUNNER="${SPEC_RUNNER_DIR:-$(cd "$(dirname "$X_BIN")" && pwd)/tests}/spec-runner.awk"
if [ ! -f "$RUNNER" ]; then
	echo "spec-runner: no awk harness at $RUNNER" >&2
	echo "  set SPEC_RUNNER_DIR to the directory holding spec-runner.awk --" >&2
	echo "  from an installed tree that is \"\$(x --share-dir)/tests\"" >&2
	exit 1
fi

# Host arch for arch-tagged specs (e.g. asm.arm64.spec.md runs only on A64
# hosts). Darwin says arm64 where GNU says aarch64; normalize to the tags the
# platform backends use (lib/x/platform/<arch>.x).
_HOST_ARCH=$(uname -m)
case "$_HOST_ARCH" in
  arm64|aarch64) _HOST_ARCH=arm64 ;;
  x86_64|amd64)  _HOST_ARCH=x86_64 ;;
esac

TEST_COUNT=0
FAIL_COUNT=0
PENDING_COUNT=0

# Run each .spec.md file through AWK runner.
# Set PARALLEL=1 to run specs concurrently.
# Counters are collected from temp files after all jobs finish.
_TMPDIR=$(mktemp -d)
_N=0

# Cap concurrent jobs in PARALLEL mode. Without a cap the loop forks every job
# at once, producing spurious "empty output" failures that shift run-to-run.
# The bottleneck is MEMORY, twice over: the boot burst (mostly gone since the
# #319 lib bucketing) and the RESIDENT HEAPS of the heavy specs (complex
# ~6GB, the tower boots; logo was ~5-7GB before it left for x-logo, and its
# bundle suite is heavy for the same reason) -- the alloc-limit! guard cannot
# protect the MACHINE from several of those at once.  The cores*2/3 rule
# stays (verified stable at 8 on a 12-core box); the heavy-set admission cap
# below is what makes heaviest-first scheduling safe at all.  2026-08-19,
# the hard way: heaviest-first + wait-any + a raised cap launched EVERY
# heavy spec at t=0 and locked up a 17GB dev box (load avg 185) -- a
# schedule reorder is a memory-profile change even when total work is
# identical.  Override with PARALLEL_JOBS (=1 serial; lower it on a
# memory-constrained box like a Pi).
_cpus=$( (command -v nproc >/dev/null 2>&1 && nproc) || sysctl -n hw.ncpu 2>/dev/null )
case "$_cpus" in ''|*[!0-9]*) _cpus=4 ;; esac
_cpus=$(( _cpus * 2 / 3 ))
[ "$_cpus" -lt 2 ] && _cpus=2
: "${PARALLEL_JOBS:=$_cpus}"

# Heavy-set admission cap: at most SPEC_HEAVY_JOBS jobs whose @weight is
# >= SPEC_HEAVY_MIN may be in flight together, whatever PARALLEL_JOBS
# says.  @weight doubles as a footprint class: the files heavy in TIME
# are the same ones heavy in RESIDENT MEMORY (tower/test-lib loads, the
# jit builds), and running them heaviest-FIRST would otherwise mean
# running them ALL AT ONCE -- the 2026-08-19 lockup above.  Two heavies
# + light fill bounds the peak at roughly two big heaps regardless of
# core count.  Both knobs are env-overridable; lower them on a shared or
# small box.
#
# THE DEFAULT IS SIZED TO THE BOX, because "lower them on a small box" is
# advice this file gives and its callers do not take.  Two heavies is roughly
# two big heaps -- ~13GB worst case, measured when logo (~5-7GB) and complex
# (~6GB) were both in this suite -- which fits a 32GB desktop and does not fit
# a 16GB laptop.  It is the same arithmetic that OOM-killed CI's 16GB ubuntu
# runner (ci.yml pins that leg to 1 for exactly this reason), and on
# 2026-08-28 it took down a 16GB dev machine running two suites at once.  A
# default that is safe only when the caller remembers a comment is not a
# guard.
#
# LOGO LEAVING DID NOT MAKE THIS SAFER, and the number is left at what two
# heavies cost for that reason: x-logo's suite is the same heap on the same
# machine, one process further away, and nothing coordinates the two runners.
#
# CI IS UNAFFECTED: both legs set SPEC_HEAVY_JOBS explicitly, and an explicit
# value still wins below.  This moves only the uninstructed local run.
#
# UNKNOWN MEMORY READS AS SMALL.  A box whose size cannot be established gets
# the conservative width, not the fast one: the cost of being wrong downward
# is a slower suite, and the cost of being wrong upward is the machine.
_memb=$( (sysctl -n hw.memsize 2>/dev/null) \
         || (awk '/^MemTotal:/ {print $2 * 1024; exit}' /proc/meminfo 2>/dev/null) )
case "$_memb" in ''|*[!0-9]*) _memb=0 ;; esac
# 24GB: two big heaps (~13GB) plus room for the OS, an editor, a browser and
# whatever else a dev box is doing while the suite runs.
if [ "$_memb" -ge 25769803776 ]; then _heavy_default=2; else _heavy_default=1; fi
: "${SPEC_HEAVY_JOBS:=$_heavy_default}"
: "${SPEC_HEAVY_MIN:=4}"
[ "$SPEC_HEAVY_JOBS" -lt 1 ] 2>/dev/null && SPEC_HEAVY_JOBS=1

# Wait-any job tracking (#320).  The old FIFO wait blocked on the OLDEST
# job, so one 19s job launched first held the runner below capacity while
# short jobs finished behind it -- measured 74% worker utilization at 2
# jobs.  POSIX sh has no `wait -n`, so completion is detected by the
# job's own output: every awk job writes spec-<id>.cnt as its last act,
# and a vanished process (`kill -0` fails once the shell has reaped it)
# covers a job killed before it could write.  The FIFO escape hatch in
# _admit guarantees progress in the one undetectable shape -- an awk job
# killed while the shell still holds its zombie unreaped -- by falling
# back to the old blocking wait after ~60s without progress; the
# collector's missing-.cnt warning still names the lost job.
_jobs_running=0
_heavy_running=0
_jobs_pids=""
_jobs_ids=""
_jobs_wts=""
_reap() {
  # Free every tracked slot whose job has finished.  The three lists are
  # space-terminated and popped in lockstep.
  _keep_pids=""; _keep_ids=""; _keep_wts=""
  _rest_ids="$_jobs_ids"; _rest_wts="$_jobs_wts"
  for _jpid in $_jobs_pids; do
    _jid="${_rest_ids%% *}"; _rest_ids="${_rest_ids#* }"
    _jw="${_rest_wts%% *}";  _rest_wts="${_rest_wts#* }"
    if [ -f "$_TMPDIR/spec-$_jid.cnt" ] || ! kill -0 "$_jpid" 2>/dev/null; then
      wait "$_jpid" 2>/dev/null
      _jobs_running=$((_jobs_running - 1))
      [ "$_jw" -ge "$SPEC_HEAVY_MIN" ] && _heavy_running=$((_heavy_running - 1))
    else
      _keep_pids="$_keep_pids$_jpid "
      _keep_ids="$_keep_ids$_jid "
      _keep_wts="$_keep_wts$_jw "
    fi
  done
  _jobs_pids="$_keep_pids"
  _jobs_ids="$_keep_ids"
  _jobs_wts="$_keep_wts"
}
# _admit WEIGHT: block until launching a job of this weight fits BOTH
# caps.  Called BEFORE the fork, so an over-budget job is never started.
_admit() {
  _stall=0
  while :; do
    _reap
    if [ "$_jobs_running" -lt "$PARALLEL_JOBS" ]; then
      if [ "$1" -lt "$SPEC_HEAVY_MIN" ] || [ "$_heavy_running" -lt "$SPEC_HEAVY_JOBS" ]; then
        return 0
      fi
    fi
    _stall=$((_stall + 1))
    if [ "$_stall" -gt 600 ]; then
      wait "${_jobs_pids%% *}" 2>/dev/null
      _w_old="${_jobs_wts%% *}"
      _jobs_pids="${_jobs_pids#* }"
      _jobs_ids="${_jobs_ids#* }"
      _jobs_wts="${_jobs_wts#* }"
      _jobs_running=$((_jobs_running - 1))
      [ "$_w_old" -ge "$SPEC_HEAVY_MIN" ] 2>/dev/null && _heavy_running=$((_heavy_running - 1))
      _stall=0
    fi
    sleep 0.1
  done
}
# _register PID SPEC_ID WEIGHT: record a job _admit already cleared.
_register() {
  _jobs_pids="${_jobs_pids}$1 "
  _jobs_ids="${_jobs_ids}$2 "
  _jobs_wts="${_jobs_wts}$3 "
  _jobs_running=$((_jobs_running + 1))
  [ "$3" -ge "$SPEC_HEAVY_MIN" ] && _heavy_running=$((_heavy_running + 1))
  return 0
}

# _spawn WEIGHT TIMEOUT_CMD FILE... -- one awk runner job over the given
# spec files (a same-@lib bucket, or a singleton).  In PARALLEL mode the
# job is admitted against both caps BEFORE forking, then registered;
# inline otherwise.  Serial mode prints a per-job timing tail; a merged
# bucket is labelled by its first file plus a +N count.
_spawn() {
  _w_adm="$1"; _tcmd="$2"; shift 2
  # AN UNDECLARED WEIGHT IS HEAVY, NOT LIGHT.  This used to read 0, which put
  # every unweighted file OUTSIDE the admission cap -- so the guard covered
  # only the files someone had remembered to annotate, and the one file its
  # own rationale is written around (ext/complex, ~6GB) was not among them.
  # The applicative stress lane was worse: six files documented as peaking
  # ~4.7GB each, none weighted, admitted PARALLEL_JOBS-wide.
  #
  # Same rule as the memory probe below: the cost of being wrong downward is a
  # slower suite, and the cost of being wrong upward is the machine.  So a
  # file earns parallelism by DECLARING its weight; forgetting costs speed.
  case "$_w_adm" in ''|*[!0-9]*) _w_adm=$SPEC_HEAVY_MIN ;; esac
  _I=$_N
  _N=$((_N+1))
  # TEMPORARY diagnostic (object-model v2 CI hunt): name each job as it
  # launches, so the runaway that OOM-kills the ubuntu runner is
  # identified by the last SPAWN line before the memory ramp.
  [ -n "$SPEC_TRACE" ] && echo "SPAWN[$_I] w=$_w_adm: $*" >&2
  _t0=$(date +%s)
  if [ -n "$PARALLEL" ]; then
    _admit "$_w_adm"
    (
      awk -v X_BIN="$X_BIN" \
          -v LANG_LIB="$LANG_LIB" \
          -v REPL_CMD="${REPL_CMD:-(repl)}" \
          -v READ_FN="${READ_FN:-Io read}" \
          -v TIMEOUT_CMD="$_tcmd" \
          -v TMPDIR="$_TMPDIR" \
          -v SPEC_ID="$_I" \
          -f "$RUNNER" "$@"
    ) &
    _register "$!" "$_I" "$_w_adm"
  else
    awk -v X_BIN="$X_BIN" \
        -v LANG_LIB="$LANG_LIB" \
        -v REPL_CMD="${REPL_CMD:-(repl)}" \
        -v READ_FN="${READ_FN:-Io read}" \
        -v TIMEOUT_CMD="$_tcmd" \
        -v TMPDIR="$_TMPDIR" \
        -v SPEC_ID="$_I" \
        -f "$RUNNER" "$@"
    _t1=$(date +%s); _dt=$((_t1 - _t0))
    if [ "$_dt" -gt 0 ]; then
      if [ $# -gt 1 ]; then
        printf " [%s+%d: %ds]" "$(basename "$1" .spec.md)" $(($# - 1)) "$_dt"
      else
        printf " [%s: %ds]" "$(basename "$1" .spec.md)" "$_dt"
      fi
    fi
  fi
}

# Per-file timeout scaling: a file whose one-off cost is legitimately
# heavy (the sha256-jit spec BUILDS the compiled digest engine, and
# sanitizer instrumentation multiplies that build several-fold)
# declares `# @timeout-scale N` near its head, and its process budget
# becomes N x the base.  A MULTIPLIER, not an absolute: it composes
# with the asan gate's raised TIMEOUT_UNIT_SECS, and the runaway guard
# stays tight for every file that declares nothing.
_file_tcmd() {
  _ftc="$TIMEOUT_UNIT"
  if [ -n "$_TIMEOUT_BIN" ]; then
    _scale=$(sed -n 's/^# @timeout-scale \([0-9][0-9]*\)$/\1/p' "$1" | head -1)
    if [ -n "$_scale" ]; then
      _ftc="$_TIMEOUT_BIN $(( ${TIMEOUT_UNIT_SECS:-60} * _scale ))"
    fi
  fi
  printf '%s' "$_ftc"
}

# Bucket classification (#319).  One awk job can take several spec files,
# amortizing the library boot (~0.7s for x-core -- ~61% of the suite when
# every file paid it alone), but ONLY same-@lib files may share a job:
# the runner's `lib` state persists across file boundaries, so a mixed
# bucket would leak one file's @lib into the next.  A file is bucketable
# under its declared lib only when the declaration is unambiguous -- ONE
# `@lib`, sitting above the first test and the first fence (a fenced
# `# @lib` is spec PROSE, e.g. in the meta specs, and must not classify).
# Anything ambiguous, plus every `@timeout-scale` file (its budget is per
# FILE), prints "!" and runs alone.  Over-detection only costs a lost
# merge, never a wrong lib.
#
# The second field is the file's `# @weight N` declaration (0 when
# absent): a scheduling hint in rough serial-seconds, declared in the
# heavy files themselves the way @timeout-scale is (#320).  Jobs run
# heaviest-first, because the glob is alphabetical and put six of the
# eight heaviest files in the last 40% of the queue -- the 13s tools/pin
# spec started DEAD LAST, defining the whole run's tail.
#
# A STALE WEIGHT ONLY MIS-RANKS A SCHEDULE.  An ABSENT one used to do more
# than that, and this comment said otherwise for as long as the admission cap
# has existed: weight is what the cap classifies on, so a missing declaration
# read as light and took the file out of the cap entirely.  Absent is now
# heavy (see _spawn), which restores "correctness never depends on the
# number" -- it depends only on the declaration being there.
_classify() {
  awk '
    /^# @lib /                { nlib++; if (nlib == 1) { libval = substr($0, 8); libline = FNR } }
    /^### /                   { if (!testline) testline = FNR }
    /^```/                    { if (!fenceline) fenceline = FNR }
    /^# @timeout-scale [0-9]/ { scaled = 1 }
    /^# @weight [0-9]/        { weight = substr($0, 11) + 0 }
    END {
      if (scaled || nlib > 1) { print "!|" weight; exit }
      if (nlib == 0) { print "|" weight; exit }
      if ((testline && libline > testline) || (fenceline && libline > fenceline)) { print "!|" weight; exit }
      print libval "|" weight
    }' "$1"
}

# Positional arguments name EXACTLY the specs to run (GH #221: they used
# to be silently ignored -- accepted-and-discarded is the silent-fallback
# shape).  A named path that does not exist is a loud error, never a
# fallthrough to the glob.  Explicit args keep one job per file (exact
# runs stay exact, with their own timing tails); the glob walk buckets.
# No arguments = every spec under SPEC_PATH, as ever; the SPECS='<glob>'
# narrowing composes with both modes, and the STRESS tail stays glob-mode
# only (explicit args mean exactly those).
_args_mode=0
if [ $# -gt 0 ]; then
  _args_mode=1
  for _s in "$@"; do
    [ -f "$_s" ] || { echo "spec-runner: no such spec file: $_s" >&2; exit 1; }
  done
else
  set -- "$SPEC_PATH"/*.spec.md "$SPEC_PATH"/*/*.spec.md
fi

# Walk the target list, applying the filters; glob mode collects the
# survivors for bucketing, args mode spawns each file directly.
_LIST="$_TMPDIR/files.lst"
: > "$_LIST"
for _spec in "$@"; do
  [ -f "$_spec" ] || continue
  # Applicative (stress) specs are skipped by the glob walk; naming one
  # explicitly runs it.
  case "$_spec" in */applicative/*) [ "$_args_mode" = 1 ] || continue ;; esac
  # Arch-tagged specs (<name>.<arch>.spec.md) run only on matching hosts.
  _tag="${_spec%.spec.md}"; _tag="${_tag##*.}"
  case "$_tag" in
    arm64|x86_64) [ "$_tag" = "$_HOST_ARCH" ] || continue ;;
  esac
  # Capability-gated specs: `# @requires <capability>` in the header runs the
  # file only against an engine whose x-engine.xon declares
  # `(provides <capability>)`.  The vocabulary is tools/contract/features.x.
  # A skipped file is NAMED, because silently thinner coverage is the
  # vacuous-pass shape; naming the file explicitly overrides the gate, the
  # same deliberate-override rule the applicative/ specs use.  An engine
  # with no xon beside it skips gated files too -- an undeclared capability
  # is an absent one, which is the whole point of declaring.
  #
  # X_ENGINE_DIR NAMES THE ENGINE DIRECTORY and wins outright, which is how
  # every other reader of this manifest already finds it: engine-contract.sh and
  # base-routes.sh both open with ${X_ENGINE_DIR:-engine}, second-engine.sh and
  # compliance.sh set it to drive a different engine, and tools/engine/fetch.sh
  # tells you to unpack a release and pass `make X_ENGINE_DIR=/path/to/unpacked`.
  # It is authoritative rather than a first guess -- a caller that names the
  # directory and finds no manifest there has an engine that declares nothing,
  # and probing elsewhere would answer a question it did not ask.
  #
  # Unset, the manifest SITS IN TWO PLACES and reading only one disables this
  # gate silently.  A repo build keeps it under engine/ while the Makefile copies
  # the binary to the root; a release bundle and an installed tree both put it
  # FLAT beside the engine (deps/engine/<release>/x-engine.xon, libexec/x/ --
  # the wrapper's "binary + its declaration").  Reading only the repo spelling
  # meant every gated file skipped against every RELEASED engine whatever that
  # engine declared: a check that cannot pass is not a check, and this one
  # failed shut in the configuration a consumer's CI actually runs.
  _req=$(sed -n 's/^# @requires //p' "$_spec" | head -1)
  if [ -n "$_req" ] && [ "$_args_mode" != 1 ]; then
    if [ -n "${X_ENGINE_DIR:-}" ]; then
      _xon="$X_ENGINE_DIR/x-engine.xon"
    else
      _xon="$(dirname "$X_BIN")/engine/x-engine.xon"
      [ -f "$_xon" ] || _xon="$(dirname "$X_BIN")/x-engine.xon"
    fi
    if ! grep -q "(provides $_req)" "$_xon" 2>/dev/null; then
      printf '[skip %s: requires %s]\n' "$(basename "$_spec" .spec.md)" "$_req"
      continue
    fi
  fi
  # SPECS (a glob pattern, e.g. '*list*') narrows the run for fast iteration; unset = all.
  [ -n "$SPECS" ] && { case "$_spec" in $SPECS) : ;; *) continue ;; esac; }
  if [ "$_args_mode" = 1 ]; then
    # NAMED FILES ARE CLASSIFIED TOO.  This passed a hard 0, so a file given on
    # the command line was admitted as light whatever it declared -- and the
    # obvious way to reproduce a heavy-file problem is to name the heavy files.
    # `PARALLEL=1 spec-runner.sh ext/complex.spec.md lib/logo.spec.md` put both
    # big heaps in flight at once, which is the pairing the cap exists to stop.
    _aw=$(_classify "$_spec"); _aw=${_aw#*|}
    _spawn "$_aw" "$(_file_tcmd "$_spec")" "$_spec"
  else
    printf '%s\n' "$_spec" >> "$_LIST"
  fi
done

# Glob mode: bucket same-lib files, at most SPEC_BATCH per job.  The cap
# keeps the two per-process guards meaningful -- the wall-clock timeout
# and the alloc-limit! ceiling both bound one PROCESS, and a bucket is
# one process accumulating all its files' garbage (there is no safe
# mid-batch collect: see the seam note in spec-runner.awk).  Eight LIGHT
# files stay far under the ceiling; the heavy libs (complex, x-base
# tower) are singletons or tiny buckets by construction.  A
# merged bucket's timeout is base x file-count: the same per-file budget
# as before, one process instead of N.  Lower SPEC_BATCH on a
# memory-constrained box (it composes with PARALLEL_JOBS); 1 restores
# the old one-file-per-job behaviour exactly.
: "${SPEC_BATCH:=8}"
if [ "$_args_mode" = 0 ]; then
  _CLS="$_TMPDIR/classes.lst"
  : > "$_CLS"
  while IFS= read -r _spec; do
    printf '%s|%s\n' "$(_classify "$_spec")" "$_spec" >> "$_CLS"
  done < "$_LIST"
  # Stable sort by class: same-lib files become adjacent, glob order is
  # preserved within a class ("|" delimiter -- it survives an empty
  # leading field where a tab would not, and no repo path contains one).
  sort -s -t '|' -k1,1 "$_CLS" > "$_CLS.sorted"

  # First pass collects the jobs (one line each: weight|timeout|files);
  # a bucket's weight is its heaviest member's.  The job list is then
  # sorted heaviest-first and spawned -- with wait-any throttling this
  # approaches the ideal makespan (the FIFO+glob-order scheduler ran at
  # 74% utilization; see _throttle).
  _JOBS="$_TMPDIR/jobs.lst"
  : > "$_JOBS"
  _bucket=""; _bn=0; _bkey=""; _bw=0
  _flush() {
    [ "$_bn" -gt 0 ] || return 0
    if [ "$_bn" -eq 1 ]; then
      printf '%s|%s|%s\n' "$_bw" "$(_file_tcmd $_bucket)" "$_bucket" >> "$_JOBS"
    elif [ -n "$_TIMEOUT_BIN" ]; then
      printf '%s|%s|%s\n' "$_bw" "$_TIMEOUT_BIN $(( ${TIMEOUT_UNIT_SECS:-60} * _bn ))" "$_bucket" >> "$_JOBS"
    else
      printf '%s||%s\n' "$_bw" "$_bucket" >> "$_JOBS"
    fi
    _bucket=""; _bn=0; _bw=0
  }
  while IFS='|' read -r _cls _w _spec; do
    if [ "$_cls" = "!" ] || [ "$_cls" != "$_bkey" ] || [ "$_bn" -ge "$SPEC_BATCH" ]; then
      _flush
      _bkey="$_cls"
    fi
    _bucket="$_bucket $_spec"
    _bn=$((_bn + 1))
    case "$_w" in ''|*[!0-9]*) _w=0 ;; esac
    [ "$_w" -gt "$_bw" ] && _bw="$_w"
    [ "$_cls" = "!" ] && _flush
  done < "$_CLS.sorted"
  _flush

  sort -s -t '|' -k1,1rn "$_JOBS" > "$_JOBS.sorted"
  while IFS='|' read -r _w _tc _files; do
    _spawn "$_w" "$_tc" $_files
  done < "$_JOBS.sorted"
fi

# Applicative (stress) specs only run with STRESS=1, and only in glob
# mode -- explicit arguments already said exactly what to run.  One job
# per file through _spawn, on the stress timeout -- STRICTLY SERIAL,
# after the main fleet drains: these files accumulate eval garbage
# across deep TCO loops (regression.spec.md peaks ~3.9GB NATIVE,
# tco-stress ~1.7GB, measured 2026-08-20), and two co-resident on a
# 7GB CI runner is the #366 OOM shape.  Serial costs ~35s total.
# ASan jobs must keep STRESS unset: the sanitizer multiplies these
# peaks 2-4x past any runner.
if [ "$_args_mode" = 0 ] && [ -n "$STRESS" ] && [ -d "$SPEC_PATH/applicative" ]; then
  wait
  for _spec in "$SPEC_PATH"/applicative/*.spec.md; do
    [ -f "$_spec" ] || continue
    _spawn "$SPEC_HEAVY_MIN" "$TIMEOUT_APPL" "$_spec"
    wait
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
