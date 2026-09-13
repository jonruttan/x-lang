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
# The writes run in parallel: each images a fresh child that loaded one
# library, so they are independent.
#
# Concurrency is bounded by memory rather than by cores.  A writer boots a
# library from source and images the child, and the peaks differ by
# architecture -- measured one at a time:
#
#   arm64    x-base 2.0GB, x-core 3.2GB, tower harness 3.9GB
#   x86-64   x-core 2.9GB, x-base 6.2GB, tower harness 7.7GB
#            (the heap costs ~64 bytes an object there against ~29 on arm64)
#
# A job is therefore budgeted 3.5GB on arm64 -- four on a 16GB box, two on a
# 7GB macOS runner -- and 9GB on x86-64, which is one job until the tower's
# load burst is reclaimed during the boot as well.  A box whose size cannot be
# read gets one: the spec runner's rule (tests/spec-runner.sh), unknown reads
# as small.  JOBS on the command line, or IMG_JOBS through make, overrides.
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
# Every writer's host is helium, booted through the wrapper (image-build.sh).
# A host boots from the per-user cache image of x.x when one is current (0.4s)
# and from source when not (2.3s on arm64, more on x86-64), once per image.  A
# fresh checkout has no such image, so one plain boot is taken first to write
# it and the rest hit the cache; that boot is the wrapper's ordinary path,
# refusals included.
sh x.sh -q -c 1 > /dev/null 2>&1 || true
{ printf '%s\n' lib/x-core.x lib/x.x lib/he.x lib/x-base.x lib/xe.x lib/rn.x
  grep -rho '^# @lib \.\./tests/x/lib/[a-z-]*\.x' tests/x/specs | sed 's|^# @lib \.\./||' | sort -u
} | IMG_OUT="$out" xargs -P "$jobs" -n 1 sh -c '
  sh tools/dev/image-build.sh "$1" "$IMG_OUT"; s=$?
  [ "$s" -eq 0 ] || [ "$s" -eq 3 ] || { echo "images: $1 failed ($s)" >&2; exit 1; }' images-one
