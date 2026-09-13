#!/bin/sh
# spec-weights.sh -- every spec file declares a `# @weight N`.
#
# The declaration is mandatory.  The runner's heavy-set admission cap
# classifies on @weight: files at or above SPEC_HEAVY_MIN are limited to
# SPEC_HEAVY_JOBS in flight, whatever PARALLEL_JOBS says, because two big heaps
# co-resident is the shape that exhausts a 16GB box.
#
# The runner reads an absent weight as heavy, so forgetting is safe but not
# free: an unweighted file is capped, and under PARALLEL it drags the whole
# suite toward serial.  That cost is invisible in any output, which is what
# this gate is for.
#
# The number is rough serial-seconds, the unit the existing declarations use.
# It doubles as a footprint class, on the observation that the files heavy in
# time are the files heavy in memory.  Measure with
# `SPEC_BATCH=1 sh tests/x/spec-runner.sh` on a quiet machine: batching
# amortises one interpreter boot across a whole bucket, so batched timings
# cannot be attributed to a file.  A stale number mis-ranks a schedule; a
# missing one costs concurrency.
set -e

cd "$(dirname "$0")/../.."

SPEC_DIRS="${SPEC_WEIGHT_DIRS:-tests/x/specs}"

_missing=""
for _dir in $SPEC_DIRS; do
	[ -d "$_dir" ] || continue
	for _f in $(find "$_dir" -name '*.spec.md' | sort); do
		grep -q '^# @weight [0-9]' "$_f" || _missing="$_missing $_f"
	done
done

if [ -n "$_missing" ]; then
	echo "spec-weights: these spec files declare no '# @weight N':" >&2
	for _f in $_missing; do echo "    $_f" >&2; done
	echo "  Add one -- rough serial-seconds, 1 for anything under a second." >&2
	echo "  Measure with: SPEC_BATCH=1 sh tests/x/spec-runner.sh" >&2
	exit 1
fi

_n=$(for _dir in $SPEC_DIRS; do [ -d "$_dir" ] && find "$_dir" -name '*.spec.md'; done | wc -l | tr -d ' ')
echo "spec-weights: ok ($_n spec files, all weighted)"
