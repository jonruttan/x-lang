#!/bin/sh
# tools/dev/images.sh -- write every state image the suite boots from, in parallel.
#
#   sh tools/dev/images.sh OUT-DIR [JOBS]
#
# The list is the six library entries plus every harness a spec names with
# `# @lib ../tests/x/lib/NAME.x`.  Each image is written by image-build.sh,
# which skips a current one (its key matches) and refuses a marked one
# (exit 3); the refusal is not a failure here, any other status is.
#
# IN PARALLEL, because the writes are independent -- each images a fresh
# child that loaded one library -- and the serial loop this replaces was the
# longest phase of a CI specs job: 29 images took 6m43s on the 4-core Linux
# runner and 9m30s on the 3-core macOS one, ahead of the 8-minute suite they
# exist to speed up.  The same 29 took 271s serially on a 12-core box and
# 84s at the four jobs its memory allows (below).
#
# BOUNDED BY MEMORY, NOT CORES.  A writer boots a library from source and
# images the child: measured one at a time on arm64, x-base peaks at
# 2.0GB, x-core at 3.2GB and the tower harness at 3.9GB.  A first cut of
# this script took one job per core, and twelve writers beside two
# sanitizer runs took a 16GB box down.  So on arm64 a job is budgeted
# 3.5GB: a 16GB box gets four, the 7GB macOS runner two (29 images in five
# minutes there, against nine and a half serially).
#  ON x86-64 THE SAME WRITER IS BIGGER -- the heap costs ~64 bytes an
# object there against ~29 on arm64 -- and four jobs killed the 16GB
# Linux runner 49 seconds in (exit 143, no failing image).  Measured one
# at a time in the qemu guest (2026-09-10, before the boot collects in
# lib/x-core.x): x-core 2.9GB, x-base 6.2GB, the tower harness 7.7GB.  Two
# of those do not share a 16GB runner, so x86-64 budgets 9GB a job, which
# is one job there -- the serial build it always had -- until the tower's
# load burst is reclaimed during the boot as well.  A box whose size
# cannot be read gets one -- the spec runner's rule (tests/spec-runner.sh),
# unknown reads as small.  JOBS on the command line, or IMG_JOBS through
# make, overrides.
set -e
cd "$(dirname "$0")/../.."
out="${1:-.images}"
jobs="${2:-}"
if [ -z "$jobs" ]; then
  cpus=$( (command -v nproc >/dev/null 2>&1 && nproc) || sysctl -n hw.ncpu 2>/dev/null || echo 1)
  memb=$( (sysctl -n hw.memsize 2>/dev/null) \
          || (awk '/^MemTotal:/ {print $2 * 1024; exit}' /proc/meminfo 2>/dev/null) )
  case "$memb" in ''|*[!0-9]*) memb=0 ;; esac
  case "$(uname -m 2>/dev/null)" in
    x86_64|amd64) budget=9663676416 ;;   # 9GB a writer on x86-64 (unmeasured; see above)
    *)            budget=3758096384 ;;   # 3.5GB a writer on arm64 (measured)
  esac
  bymem=$(( memb / budget ))
  [ "$bymem" -ge 1 ] || bymem=1
  jobs=$cpus; [ "$bymem" -lt "$jobs" ] && jobs=$bymem
fi
mkdir -p "$out"
{ printf '%s\n' lib/x-core.x lib/x.x lib/he.x lib/x-base.x lib/xe.x lib/rn.x
  grep -rho '^# @lib \.\./tests/x/lib/[a-z-]*\.x' tests/x/specs | sed 's|^# @lib \.\./||' | sort -u
} | IMG_OUT="$out" xargs -P "$jobs" -n 1 sh -c '
  sh tools/dev/image-build.sh "$1" "$IMG_OUT"; s=$?
  [ "$s" -eq 0 ] || [ "$s" -eq 3 ] || { echo "images: $1 failed ($s)" >&2; exit 1; }' images-one
