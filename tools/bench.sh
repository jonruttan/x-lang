#!/bin/sh
# bench.sh -- Benchmark x-lang library loading with profiling data
#
# Usage: sh tools/bench.sh [--no-build]
#
# Outputs TSV to benchmarks/<date>.tsv and prints comparison with
# the previous benchmark if one exists.

set -e

BASEDIR="$(cd "$(dirname "$0")/.." && pwd)"
cd "$BASEDIR"

DATE=$(date +%Y-%m-%d_%H%M%S)
OUTFILE="benchmarks/${DATE}.tsv"
TMPDIR="${TMPDIR:-/tmp}"

# Build unless --no-build
if [ "$1" != "--no-build" ]; then
    printf "Building... "
    make clean >/dev/null 2>&1
    make >/dev/null 2>&1
    echo "done."
fi

# Profile dump snippet (appended to each personality load)
PROF_SNIPPET='(include "lib/x/profile.x")(profile-dump)'

# Header
printf "name\twall_us\tevals\ttco\tassoc_calls\tassoc_steps\tsym_find_calls\tsym_find_steps\tgc_runs\tbst_hits\tbst_misses\theap\n" > "$OUTFILE"

run_bench() {
    name="$1"
    lib="$2"

    stderr_file="${TMPDIR}/x-bench-$$.stderr"
    time_file="${TMPDIR}/x-bench-$$.time"

    # Run with wall-clock timing; profile-dump goes to stderr
    printf '%s' "$PROF_SNIPPET" | cat $lib - | \
        /usr/bin/time -p sh -c "./x-profile 2>\"$stderr_file\"" 2>"$time_file" >/dev/null || true

    # Parse wall time (seconds -> microseconds)
    wall_s=$(grep '^real' "$time_file" | awk '{print $2}')
    # Use awk to convert to microseconds (integer)
    wall_us=$(echo "$wall_s" | awk '{printf "%d", $1 * 1000000}')

    # Parse profile-dump line from stderr
    prof_line=$(grep '^allocs=' "$stderr_file" || echo "")

    if [ -n "$prof_line" ]; then
        evals=$(echo "$prof_line" | sed 's/.*evals=\([0-9]*\).*/\1/')
        tco=$(echo "$prof_line" | sed 's/.*tco=\([0-9]*\).*/\1/')
        assoc_calls=$(echo "$prof_line" | sed 's/.*assoc-calls=\([0-9]*\).*/\1/')
        assoc_steps=$(echo "$prof_line" | sed 's/.*assoc-steps=\([0-9]*\).*/\1/')
        sym_find_calls=$(echo "$prof_line" | sed 's/.*sym-find-calls=\([0-9]*\).*/\1/')
        sym_find_steps=$(echo "$prof_line" | sed 's/.*sym-find-steps=\([0-9]*\).*/\1/')
        gc_runs=$(echo "$prof_line" | sed 's/.*gc-runs=\([0-9]*\).*/\1/')
        bst_hits=$(echo "$prof_line" | sed 's/.*bst-hits=\([0-9]*\).*/\1/')
        bst_misses=$(echo "$prof_line" | sed 's/.*bst-misses=\([0-9]*\).*/\1/')
        heap=$(echo "$prof_line" | sed 's/.*heap=\([0-9]*\).*/\1/')
    else
        evals=0; tco=0; assoc_calls=0; assoc_steps=0
        sym_find_calls=0; sym_find_steps=0; gc_runs=0
        bst_hits=0; bst_misses=0; heap=0
    fi

    printf "%s\t%s\t%s\t%s\t%s\t%s\t%s\t%s\t%s\t%s\t%s\t%s\n" \
        "$name" "$wall_us" "$evals" "$tco" \
        "$assoc_calls" "$assoc_steps" \
        "$sym_find_calls" "$sym_find_steps" \
        "$gc_runs" "$bst_hits" "$bst_misses" "$heap" >> "$OUTFILE"

    # Print human-readable line
    avg_scan=0
    if [ "$assoc_calls" -gt 0 ] 2>/dev/null; then
        avg_scan=$(echo "$assoc_steps $assoc_calls" | awk '{printf "%.1f", $1/$2}')
    fi
    bst_rate="n/a"
    if [ "$bst_hits" -gt 0 ] 2>/dev/null || [ "$bst_misses" -gt 0 ] 2>/dev/null; then
        bst_rate=$(echo "$bst_hits $bst_misses" | awk '{printf "%.0f%%", $1/($1+$2)*100}')
    fi
    printf "  %-12s %6.2fs  evals=%-10s assoc=%s/%s (avg %s)  bst=%s/%s (%s)  sym=%s/%s  gc=%s  heap=%s\n" \
        "$name" "$(echo "$wall_us" | awk '{printf "%.2f", $1/1000000}')" \
        "$evals" "$assoc_calls" "$assoc_steps" "$avg_scan" \
        "$bst_hits" "$bst_misses" "$bst_rate" \
        "$sym_find_calls" "$sym_find_steps" "$gc_runs" "$heap"

    rm -f "$stderr_file" "$time_file"
}

echo ""
echo "Running benchmarks..."
echo ""

run_bench "x-core" "lib/x-core.x"
run_bench "r5rs" "lang/r5rs/lib/r5rs-base.x"
run_bench "r7rs" "lang/r7rs/lib/r7rs-base.x"

echo ""

# Find previous benchmark for comparison
prev=$(ls -t benchmarks/*.tsv 2>/dev/null | grep -v "$DATE" | head -1)

if [ -n "$prev" ]; then
    echo "vs. previous: $prev"
    echo ""
    # Compare wall times
    while IFS='	' read -r name wall rest; do
        [ "$name" = "name" ] && continue
        prev_wall=$(awk -F'\t' -v n="$name" '$1==n {print $2}' "$prev")
        if [ -n "$prev_wall" ] && [ "$prev_wall" -gt 0 ] 2>/dev/null; then
            pct=$(echo "$wall $prev_wall" | awk '{printf "%+.1f%%", ($1-$2)/$2*100}')
            printf "  %-12s %6.2fs -> %6.2fs  (%s)\n" \
                "$name" \
                "$(echo "$prev_wall" | awk '{printf "%.2f", $1/1000000}')" \
                "$(echo "$wall" | awk '{printf "%.2f", $1/1000000}')" \
                "$pct"
        fi
    done < "$OUTFILE"
    echo ""
fi

echo "Saved to $OUTFILE"
