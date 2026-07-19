#!/bin/sh
# doctest.sh -- generate the doctest spec from the library's (example ...)
# forms (#16). Emits the generated .spec.md on stdout; run it through the
# spec harness with:
#
#   sh tools/doctest.sh > build/doctests.spec.md
#   sh tests/x/spec-runner.sh build/doctests.spec.md
#
# Module list is auto-discovered from lib/x/**. Denylist, with cause:
#   x/platform/arm64   -- asm backends; not importable standalone (#37)
#   x/platform/x86_64
#   x/constructs       -- XEON DATA, not code: importing it EVALUATES the
#                         construct table, and the (read ...) entry calls
#                         read -- which eats the tool's own stdin (the rest
#                         of doctest.x vanishes and the run "succeeds")
# Everything else under lib/x is fair game; boot-loaded modules re-import
# as no-ops (include-once pre-seed).

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
PROJECT_DIR="$(cd "$SCRIPT_DIR/.." && pwd)"
X_BIN="${X_BIN:-$PROJECT_DIR/x}"

cd "$PROJECT_DIR" || exit 1

X_ALLOC_LIMIT_OBJS="${X_ALLOC_LIMIT_OBJS:-300000000}"
case "$X_ALLOC_LIMIT_OBJS" in
  ''|*[!0-9]*) X_ALLOC_LIMIT_OBJS=300000000 ;;
esac

# lib/x/type/dict.x -> x/type/dict; sorted for stable output.
_MODS=$(find lib/x -name '*.x' | sed 's|^lib/||; s|\.x$||' | sort \
  | grep -v -E '^x/platform/(arm64|x86_64)$|^x/constructs$')

{
  printf '(alloc-limit! %s)\n' "$X_ALLOC_LIMIT_OBJS"
  cat lib/x-core.x tools/doctest.x
} | "$X_BIN" $_MODS
