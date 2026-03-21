#!/bin/sh
# doc.sh -- Generate Markdown documentation from x-lang source files
#
# Usage: sh tools/doc.sh FILE [FILE ...]    -- generate docs to stdout

set -e

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
X="${ROOT}/x"
LIB="${ROOT}/lib/x-core.x"
DOC="${ROOT}/tools/doc.x"

usage() {
    echo "Usage: $0 FILE [FILE ...]" >&2
    exit 1
}

[ $# -eq 0 ] && usage

for FILE in "$@"; do
    [ -f "$FILE" ] || { echo "Error: $FILE not found" >&2; exit 1; }

    # Escape file content as an x-lang string literal
    ESCAPED=$(awk 'BEGIN{ORS=""} {gsub(/\\/,"\\\\"); gsub(/"/,"\\\""); if(NR>1) printf "\\n"; print} END{printf "\\n"}' "$FILE")
    INPUT="\"${ESCAPED}\""

    # Run doc generator: library + tool + input string (input must come last)
    TMPINPUT=$(mktemp)
    printf '%s' "$INPUT" > "$TMPINPUT"
    cat "$LIB" "$DOC" "$TMPINPUT" | "$X"
    rm -f "$TMPINPUT"
done
