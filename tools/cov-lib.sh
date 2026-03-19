#!/bin/sh
# tools/cov-lib.sh -- x-lang library coverage report
#
# Extracts test code from spec files, runs all tests in a single
# x-profile invocation, then reports which library functions have
# untested code paths.
#
# Usage: sh tools/cov-lib.sh [spec-dir...]
#        (defaults to tests/x/specs/{core,lib,ext})
#
# Requires: x-profile binary (make x-profile)

set -e

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

TMPTEST=$(mktemp)
trap 'rm -f "$TMPTEST"' EXIT

# Extract test code blocks from spec files.
# Each test block (between ### heading and ---) is wrapped in
# (guard (err ()) (do ...)) so errors don't halt execution.
# Blocks containing read, read-char, or include are skipped
# (they consume stdin or load files, breaking piped execution).
for dir in "$@"; do
    for spec in "$dir"/*.spec.md; do
        [ -f "$spec" ] || continue
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
    done
done

BLOCKS=$(wc -l < "$TMPTEST" | tr -d ' ')
echo "x-lang coverage: $BLOCKS test blocks from $# spec directories"
echo ""

# Detect which library to load: x-base.x if ext/ specs are included
# (they need float, vector, regex types), otherwise x-core.x.
LIB="lib/x-core.x"
for dir in "$@"; do
    case "$dir" in *ext*) LIB="lib/x-base.x" ;; esac
done

# Run: library + marker + test code + coverage report.
# The marker separates library defs from test defs so the report
# only walks library functions (skipping test-local defs).
# Test output is mixed in but filtered by sed to show only the report.
# Run: library + test code + coverage report.
# Limit to 350 blocks per invocation (more causes heap exhaustion).
# If over the limit, trim from the end (lib tests are first, most important).
LIMIT=350
TOTAL=$(wc -l < "$TMPTEST" | tr -d ' ')
if [ "$TOTAL" -gt "$LIMIT" ]; then
    echo "  (capped at $LIMIT/$TOTAL blocks to avoid heap exhaustion)"
    echo ""
    head -"$LIMIT" "$TMPTEST" > "${TMPTEST}.cap"
    mv "${TMPTEST}.cap" "$TMPTEST"
fi

{
    cat "$LIB"
    echo '(def %cov-library-end #t)'
    cat "$TMPTEST"
    cat tools/cov-report.x
} | timeout 180 ./x-profile 2>/dev/null | sed -n '/=== x-lang/,$ p'
