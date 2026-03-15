#!/bin/sh
# cov.sh -- x-lang branch coverage wrapper
#
# Usage: sh tools/cov.sh [--lang LANG] FILE
#
# Runs the target file through the x-cov binary (which marks
# evaluated AST nodes) then reports which branches were taken.

set -e

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
X_COV="${ROOT}/x-cov"
LIB="${ROOT}/lib/x-core.x"
COV="${ROOT}/tools/cov.x"
CONSTRUCTS="${ROOT}/lib/x/constructs.x"

usage() {
    echo "Usage: $0 [--lang LANG] FILE" >&2
    exit 1
}

# Parse args
LANG=""
FILE=""
while [ $# -gt 0 ]; do
    case "$1" in
        --lang) LANG="$2"; shift 2 ;;
        -*) usage ;;
        *) FILE="$1"; shift ;;
    esac
done

[ -z "$FILE" ] && usage
[ -f "$FILE" ] || { echo "Error: $FILE not found" >&2; exit 1; }

# Check x-cov binary exists
[ -f "$X_COV" ] || { echo "Error: x-cov not found (run: make x-cov)" >&2; exit 1; }

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

# Build constructs: base + lang (or ())
LANG_CONSTRUCTS=""
if [ -n "$LANG" ] && [ -f "${ROOT}/lang/${LANG}/lib/constructs.x" ]; then
    LANG_CONSTRUCTS="${ROOT}/lang/${LANG}/lib/constructs.x"
fi
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

# Run coverage: constructs + quoted source string piped after library + cov
printf '%s\n%s' "$CONSTRUCTS_INPUT" "$INPUT" | cat "$LIB" "$COV" - | "$X_COV"
