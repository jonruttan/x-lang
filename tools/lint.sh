#!/bin/sh
# lint.sh -- x-lang linter wrapper
#
# Runs the x-lang linter on each target file. The linter uses
# the interpreter's own env-alist for known symbols — no manual
# enumeration needed.
#
# Usage: sh tools/lint.sh [--lib] [file.x ...]
#   --lib: suppress unused warnings (for library/export files)
#   No args: lint all lib/x-core.x and lib/x/*.x in --lib mode

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
PROJECT_DIR="$(cd "$SCRIPT_DIR/.." && pwd)"
X_BIN="$PROJECT_DIR/x"
LINTER="$SCRIPT_DIR/lint.x"
LANG_LIB="$PROJECT_DIR/lib/x-core.x"

LIB_MODE=0
if [ "${1:-}" = "--lib" ]; then
  LIB_MODE=1
  shift
fi

# Default targets: library files in --lib mode
if [ $# -eq 0 ]; then
  LIB_MODE=1
  set -- "$LANG_LIB" "$PROJECT_DIR"/lib/x/*.x
fi

FAIL=0
for f in "$@"; do
  _NAME=$(echo "$f" | sed "s|$PROJECT_DIR/||")
  if [ "$LIB_MODE" -eq 1 ]; then
    _OUT=$(printf '%%lint-lib\n'; cat "$f") | cat "$LANG_LIB" "$LINTER" - | "$X_BIN" 2>&1
  else
    _OUT=$(cat "$LANG_LIB" "$LINTER" "$f" | "$X_BIN" 2>&1)
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
