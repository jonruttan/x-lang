#!/bin/sh
# fmt.sh -- comment-preserving x-lang formatter
#
# Usage: sh tools/fmt.sh FILE                -- print formatted output
#        sh tools/fmt.sh -i FILE             -- format in place
#        sh tools/fmt.sh --check FILE        -- exit 1 if file would change
#        sh tools/fmt.sh --lang r5rs FILE    -- use language-specific constructs

set -e

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
X="${ROOT}/x"
LIB="${ROOT}/lib/x-core.x"
FMT="${ROOT}/tools/fmt.x"
CONSTRUCTS="${ROOT}/lib/x/constructs.x"

usage() {
    echo "Usage: $0 [-i|--check] [--lang LANG] FILE" >&2
    exit 1
}

# Parse args
MODE="print"
LANG=""
FILE=""
while [ $# -gt 0 ]; do
    case "$1" in
        -i) MODE="inplace"; shift ;;
        --check) MODE="check"; shift ;;
        --lang) LANG="$2"; shift 2 ;;
        -*) usage ;;
        *) FILE="$1"; shift ;;
    esac
done

[ -z "$FILE" ] && usage
[ -f "$FILE" ] || { echo "Error: $FILE not found" >&2; exit 1; }

# Auto-detect language from file path if not specified
if [ -z "$LANG" ]; then
    case "$FILE" in
        */lang/r5rs/*) LANG="r5rs" ;;
        */lang/r7rs/*) LANG="r7rs" ;;
        */lang/krn/*)  LANG="krn"  ;;
        */lang/ash/*)  LANG="ash"  ;;
        */lang/sweet/*) LANG="sweet" ;;
        */lang/sl/*)   LANG="sl"   ;;
    esac
fi

# Build constructs: base x-lang + language-specific (if any)
LANG_CONSTRUCTS=""
if [ -n "$LANG" ] && [ -f "${ROOT}/lang/${LANG}/lib/constructs.x" ]; then
    LANG_CONSTRUCTS="${ROOT}/lang/${LANG}/lib/constructs.x"
fi

# Build constructs input for the formatter.
# fmt.x always reads two forms: base constructs + lang constructs.
# If no lang constructs, send () as the second form.
if [ -n "$LANG_CONSTRUCTS" ]; then
    CONSTRUCTS_INPUT="$(cat "$CONSTRUCTS") $(cat "$LANG_CONSTRUCTS")"
else
    CONSTRUCTS_INPUT="$(cat "$CONSTRUCTS") ()"
fi

# Escape file content as an x-lang string literal
escape_string() {
    awk 'BEGIN{ORS=""} {gsub(/\\/,"\\\\"); gsub(/"/,"\\\""); if(NR>1) printf "\\n"; print} END{printf "\\n"}' "$1"
}

ESCAPED=$(escape_string "$FILE")
INPUT="\"${ESCAPED}\""

# Run formatter: constructs + quoted source string piped after library + fmt
OUTPUT=$(printf '%s\n%s' "$CONSTRUCTS_INPUT" "$INPUT" | cat "$LIB" "$FMT" - | "$X")

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
