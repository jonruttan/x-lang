#!/bin/sh
# tools/cov-lib.sh -- x-lang library coverage report (aggregated)
#
# Runs each spec file in its own x-profile invocation, collects
# per-function coverage data (TSV), then merges by taking the max
# covered count per function across all runs.
#
# Usage: sh tools/cov-lib.sh [spec-dir...]
#        (defaults to tests/x/specs/{core,lib,ext})
#
# Requires: x-profile binary (make x-profile)

set +e  # don't exit on crash/empty grep from individual specs

BASEDIR="$(cd "$(dirname "$0")/.." && pwd)"
cd "$BASEDIR"

if [ ! -f ./x-profile ]; then
    echo "Building x-profile..."
    make x-profile >/dev/null 2>&1
fi

# Default spec directories
if [ $# -eq 0 ]; then
    set -- tests/x/specs/core tests/x/specs/lib tests/x/specs/ext
fi

TMPDIR="${TMPDIR:-/tmp}"
TMPTEST="${TMPDIR}/x-cov-test.$$.x"
TMPTSV="${TMPDIR}/x-cov-raw.$$.tsv"
trap 'rm -f "$TMPTEST" "$TMPTSV"' EXIT

# Detect library: x-base.x if ext/ specs included, else x-core.x
LIB="lib/x-core.x"
for dir in "$@"; do
    case "$dir" in *ext*) LIB="lib/x-base.x" ;; esac
done

SPEC_COUNT=0
> "$TMPTSV"

for dir in "$@"; do
    for spec in "$dir"/*.spec.md; do
        [ -f "$spec" ] || continue
        SPEC_COUNT=$((SPEC_COUNT + 1))

        # Extract test blocks from this spec file
        > "$TMPTEST"
        awk '
        /^```/ { fenced = !fenced; next }
        /^---$/ {
            if (state == 1 && buf != "") {
                if (buf !~ /\(read[ )]/ && buf !~ /\(read-char/ && buf !~ /\(include / && buf !~ /make-token-base/ && buf !~ /make-base/ && buf !~ /base-make-type/ && buf !~ /base-eval/ && buf !~ /base-bind/)
                    printf "(guard (err ()) (do %s))\n", buf
                buf = ""
            }
            state = 2; next
        }
        /^### / { state = 1; buf = ""; next }
        /^## / { state = 0; next }
        fenced && state == 1 {
            if (buf == "") buf = $0
            else buf = buf " " $0
        }
        ' "$spec" >> "$TMPTEST"

        BLOCKS=$(wc -l < "$TMPTEST" | tr -d ' ')
        [ "$BLOCKS" -eq 0 ] && continue

        # Run: library + marker + tsv-mode + tests + report
        {
            cat "$LIB"
            echo '(def %cov-library-end #t)'
            echo '(def %cov-tsv-mode #t)'
            cat "$TMPTEST"
            cat tools/cov-report.x
        } | timeout 60 ./x-profile 2>/dev/null | grep '^COV	' >> "$TMPTSV"
        true  # don't fail on crash or empty grep

        printf "." >&2
    done
done

echo "" >&2
echo "x-lang coverage: $SPEC_COUNT spec files" >&2
echo "" >&2

# Merge TSV: for each function, take max covered count
# Input: name\tcovered\ttotal (may have duplicates across runs)
# Output: sorted report with summary
sort "$TMPTSV" | awk -F'\t' '
{
    name = $2; cov = $3 + 0; total = $4 + 0
    if (!(name in totals) || cov > maxcov[name]) {
        maxcov[name] = cov
    }
    totals[name] = total
}
END {
    full = 0; partial = 0; untested = 0; count = 0
    for (name in totals) {
        count++
        cov = maxcov[name]; total = totals[name]
        if (cov == total) full++
        else if (cov == 0) { untested++; printf "    %s UNTESTED\n", name }
        else { partial++; printf "    %s %d/%d (%d%%)\n", name, cov, total, int(cov*100/total) }
    }
    printf "\n  Full:     %d/%d\n", full, count
    printf "  Partial:  %d/%d\n", partial, count
    printf "  Untested: %d/%d\n", untested, count
}
'
