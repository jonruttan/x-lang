#!/bin/sh
# fmt.sh -- comment-preserving x-lang formatter
#
# Usage: sh tools/fmt.sh FILE          -- print formatted output
#        sh tools/fmt.sh -i FILE       -- format in place
#        sh tools/fmt.sh --check FILE  -- exit 1 if file would change

set -e

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
X="${ROOT}/x"
LIB="${ROOT}/lib/x-core.x"
FMT="${ROOT}/tools/fmt.x"

usage() {
    echo "Usage: $0 [-i|--check] FILE" >&2
    exit 1
}

# Parse args
MODE="print"
FILE=""
while [ $# -gt 0 ]; do
    case "$1" in
        -i) MODE="inplace"; shift ;;
        --check) MODE="check"; shift ;;
        -*) usage ;;
        *) FILE="$1"; shift ;;
    esac
done

[ -z "$FILE" ] && usage
[ -f "$FILE" ] || { echo "Error: $FILE not found" >&2; exit 1; }

# Escape file content as an x-lang string literal:
# - backslashes -> \\
# - double quotes -> \"
# - newlines -> \n
# Then wrap in double quotes
escape_string() {
    awk 'BEGIN{ORS=""} {gsub(/\\/,"\\\\"); gsub(/"/,"\\\""); if(NR>1) printf "\\n"; print} END{printf "\\n"}' "$1"
}

ESCAPED=$(escape_string "$FILE")
INPUT="\"${ESCAPED}\""

# Run formatter
OUTPUT=$(printf '%s' "$INPUT" | cat "$LIB" "$FMT" - | "$X")

case "$MODE" in
    print)
        printf '%s\n' "$OUTPUT"
        ;;
    inplace)
        printf '%s\n' "$OUTPUT" > "$FILE"
        ;;
    check)
        ORIGINAL=$(cat "$FILE")
        if [ "$OUTPUT" = "$ORIGINAL" ]; then
            exit 0
        else
            echo "Would reformat: $FILE" >&2
            exit 1
        fi
        ;;
esac
