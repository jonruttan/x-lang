#!/bin/sh
# boot-order.sh -- run the boot-order lint (class-calls before def-class)
#
# Feeds the interpreter the allocation guard, the language, and the lint on
# stdin; the full lib file list (for the def-class inventory) rides the
# command line (the tool reads it from `args` -- stdin is for code, argv is
# for data: a mid-stream (read) would eat the tool's own next form).
# tools/check/boot-order.x simulates the boot load order from lib/x-core.x and
# prints one line per violation, then "ok" iff there were none.
#
# Pass/fail comes from the linter's own output, not $?: an uncaught x-lang
# error now exits non-zero, but a FINDING is a normal print, and "ok" is the
# only clean signal.

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
PROJECT_DIR="$(cd "$SCRIPT_DIR/../.." && pwd)"
X_BIN="${X_BIN:-$PROJECT_DIR/x-bin}"

# Paths inside x-core.x ("lib/...") are repo-relative.
cd "$PROJECT_DIR" || exit 1

# The interpreter self-limits (a raw run is otherwise unbounded RAM); same
# guard and same fail-open numeric check as the spec harness.
X_ALLOC_LIMIT_OBJS="${X_ALLOC_LIMIT_OBJS:-300000000}"
case "$X_ALLOC_LIMIT_OBJS" in
  ''|*[!0-9]*) X_ALLOC_LIMIT_OBJS=300000000 ;;
esac

# Word-splitting the list into argv is intended; lib paths contain no spaces.
_FILES=$(find lib -name '*.x' | sort)

# Verdict cache (#325).  This gate is a pure function of its inputs: the
# lib sources (list AND contents), this script, the lint itself, and the
# engine that tokenizes everything -- hashing x-bin covers the last (a
# relink changes it exactly when engine behaviour may have; an untouched
# tree hashes stable).  A GREEN verdict is cached under that key in
# build/, so the pre-push hook pays the ~25s walk only when something
# that could change the answer changed; a fresh checkout (CI) or a red
# tree always runs live -- only "ok" is ever cached.
_DG="sha256sum"
command -v sha256sum >/dev/null 2>&1 || _DG="shasum -a 256"
_KEY=$({ $_DG tools/check/boot-order.sh tools/check/boot-order.x x-bin $_FILES; } | $_DG | awk '{print $1}')
_CACHE="build/boot-order.verdict"
if [ -f "$_CACHE" ] && [ "$(cat "$_CACHE" 2>/dev/null)" = "$_KEY" ]; then
  echo "boot-order: ok (cached)"
  exit 0
fi

_OUT=$({
  printf '(alloc-limit! %s)\n' "$X_ALLOC_LIMIT_OBJS"
  cat lib/x-core.x tools/check/boot-order.x
} | "$X_BIN" $_FILES 2>&1)

# "ok" must be present AND no interpreter error anywhere in the output --
# an error AFTER the report (e.g. the allocation guard tripping) must not
# slip through on the strength of an earlier "ok" line.
if printf '%s\n' "$_OUT" | grep -qx "ok" \
  && ! printf '%s\n' "$_OUT" | grep -q "ERROR"; then
  mkdir -p build && printf '%s\n' "$_KEY" > "$_CACHE"
  echo "boot-order: ok"
else
  echo "boot-order: FAIL" >&2
  printf '%s\n' "$_OUT" >&2
  exit 1
fi
