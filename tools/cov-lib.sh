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
                if (buf !~ /\(read[ )]/ && buf !~ /\(read-char/ && buf !~ /\(include / && buf !~ /regex/ && buf !~ /#\// && buf !~ /string->float/)
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

# Run: library + marker + test code + coverage report.
# The marker separates library defs from test defs so the report
# only walks library functions (skipping test-local defs).
# Test output is mixed in but filtered by sed to show only the report.
{
    cat lib/x-core.x
    echo '(def %cov-library-end #t)'
    cat "$TMPTEST"
    cat tools/cov-report.x
} | timeout 120 ./x-profile 2>/dev/null | sed -n '/=== x-lang/,$ p'
