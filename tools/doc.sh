#!/bin/sh
# doc.sh -- Generate Markdown documentation from x-lang source files
#
# Usage: sh tools/doc.sh FILE [FILE ...]    -- generate docs to stdout
#
# Feeds two string literals to the doc tool:
#   1. doc-prims.x content (retroactive docs for boot modules)
#   2. Source file content

set -e

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
X="${ROOT}/x"
LIB="${ROOT}/lib/x-core.x"
DOC="${ROOT}/tools/doc.x"
PRIMS="${ROOT}/lib/x/doc/doc-prims.x"

escape_file() {
    awk 'BEGIN{ORS=""} {gsub(/\\/,"\\\\"); gsub(/"/,"\\\""); if(NR>1) printf "\\n"; print} END{printf "\\n"}' "$1"
}

usage() {
    echo "Usage: $0 FILE [FILE ...]" >&2
    exit 1
}

[ $# -eq 0 ] && usage

for FILE in "$@"; do
    [ -f "$FILE" ] || { echo "Error: $FILE not found" >&2; exit 1; }

    TMPINPUT=$(mktemp)

    # First string: doc-prims.x (skip if target IS doc-prims.x)
    if [ "$(cd "$(dirname "$FILE")" && pwd)/$(basename "$FILE")" = "$PRIMS" ]; then
        printf '""' > "$TMPINPUT"
    else
        printf '"%s"' "$(escape_file "$PRIMS")" > "$TMPINPUT"
    fi

    # Second string: source file
    printf '\n"%s"' "$(escape_file "$FILE")" >> "$TMPINPUT"

    cat "$LIB" "$DOC" "$TMPINPUT" | "$X"
    rm -f "$TMPINPUT"
done
