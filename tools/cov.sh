#!/bin/sh
# cov.sh -- x-lang branch coverage wrapper
#
# Usage: sh tools/cov.sh FILE
#
# Runs the target file through the x-cov binary (which marks
# evaluated AST nodes) then reports which branches were taken.

set -e

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
X_COV="${ROOT}/x-cov"
LIB="${ROOT}/lib/x-core.x"
COV="${ROOT}/tools/cov.x"

usage() {
    echo "Usage: $0 FILE" >&2
    exit 1
}

[ $# -eq 0 ] && usage
FILE="$1"
[ -f "$FILE" ] || { echo "Error: $FILE not found" >&2; exit 1; }

# Check x-cov binary exists
[ -f "$X_COV" ] || { echo "Error: x-cov not found (run: make x-cov)" >&2; exit 1; }

# Escape file content as an x-lang string literal
escape_string() {
    awk 'BEGIN{ORS=""} {gsub(/\\/,"\\\\"); gsub(/"/,"\\\""); if(NR>1) printf "\\n"; print} END{printf "\\n"}' "$1"
}

ESCAPED=$(escape_string "$FILE")
INPUT="\"${ESCAPED}\""

printf '%s' "$INPUT" | cat "$LIB" "$COV" - | "$X_COV"
