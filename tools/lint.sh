#!/bin/sh
# lint.sh -- x-lang linter wrapper
#
# Runs the x-lang linter on each target file. The linter uses
# the interpreter's own env-alist for known symbols -- no manual
# enumeration needed.
#
# Usage: sh tools/lint.sh [--lib] [--lang LANG] [file.x ...]
#   --lib: suppress unused warnings (for library/export files)
#   --lang LANG: use language-specific constructs
#   No args: lint all lib/x-core.x and lib/x/*.x in --lib mode

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
PROJECT_DIR="$(cd "$SCRIPT_DIR/.." && pwd)"
X_BIN="$PROJECT_DIR/x"
LINTER="$SCRIPT_DIR/lint.x"
LANG_LIB="$PROJECT_DIR/lib/x-core.x"
CONSTRUCTS="$PROJECT_DIR/lib/x/constructs.x"

LIB_MODE=0
LANG=""

# Parse flags (before file args)
while [ $# -gt 0 ]; do
  case "$1" in
    --lib) LIB_MODE=1; shift ;;
    --lang) LANG="$2"; shift 2 ;;
    -*) echo "Usage: $0 [--lib] [--lang LANG] [file.x ...]" >&2; exit 1 ;;
    *) break ;;
  esac
done

# Default targets: library files in --lib mode (skip data-only files)
if [ $# -eq 0 ]; then
  LIB_MODE=1
  _FILES="$LANG_LIB"
  for _f in "$PROJECT_DIR"/lib/x/*.x; do
    case "$_f" in */constructs.x) ;; *) _FILES="$_FILES $_f" ;; esac
  done
  set -- $_FILES
fi

FAIL=0
for f in "$@"; do
  _NAME=$(echo "$f" | sed "s|$PROJECT_DIR/||")

  # Auto-detect language from file path if not specified
  _LANG="$LANG"
  if [ -z "$_LANG" ]; then
    case "$f" in
      */lang/r5rs/*) _LANG="r5rs" ;;
      */lang/r7rs/*) _LANG="r7rs" ;;
      */lang/krn/*)  _LANG="krn"  ;;
      */lang/ash/*)  _LANG="ash"  ;;
      */lang/sweet/*) _LANG="sweet" ;;
      */lang/sl/*)   _LANG="sl"   ;;
    esac
  fi

  # Build constructs input: base + lang (or ())
  _LANG_CONSTRUCTS=""
  if [ -n "$_LANG" ] && [ -f "$PROJECT_DIR/lang/$_LANG/lib/constructs.x" ]; then
    _LANG_CONSTRUCTS="$PROJECT_DIR/lang/$_LANG/lib/constructs.x"
  fi
  if [ -n "$_LANG_CONSTRUCTS" ]; then
    _CONSTRUCTS_INPUT="$(cat "$CONSTRUCTS") $(cat "$_LANG_CONSTRUCTS")"
  else
    _CONSTRUCTS_INPUT="$(cat "$CONSTRUCTS") ()"
  fi

  # Run linter: library + linter code, then constructs + [mode flag] + target
  if [ "$LIB_MODE" -eq 1 ]; then
    _OUT=$({ printf '%s\n%%lint-lib\n' "$_CONSTRUCTS_INPUT"; cat "$f"; } | cat "$LANG_LIB" "$LINTER" - | "$X_BIN" 2>&1)
  else
    _OUT=$({ printf '%s\n' "$_CONSTRUCTS_INPUT"; cat "$f"; } | cat "$LANG_LIB" "$LINTER" - | "$X_BIN" 2>&1)
  fi
  _RC=$?
  if [ "$_RC" -eq 0 ]; then
    printf '  \033[1;32m.\033[0m %s\n' "$_NAME"
  else
    FAIL=1
    printf '  \033[1;31mF\033[0m %s\n' "$_NAME"
    echo "$_OUT" | while IFS= read -r line; do
      case "$line" in
        "*** ERROR"*) ;;
        *) printf '    %s\n' "$line" ;;
      esac
    done
  fi
done

[ "$FAIL" -eq 0 ]
