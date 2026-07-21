#!/bin/sh
# doctest.sh -- generate the doctest spec from the library's (example ...)
# forms (#16). Emits the generated .spec.md on stdout; run it through the
# spec harness with:
#
#   sh tools/doctest.sh > build/doctests.spec.md
#   sh tests/x/spec-runner.sh build/doctests.spec.md
#
# Module list is auto-discovered from lib/x/**. Denylist, with cause:
#   x/tool/asm/*       -- asm backend opcode tables: raw-included by
#                         tool/asm.x, reference its (reg n), not importable
#   x/constructs       -- XEON DATA, not code: importing it EVALUATES the
#                         construct table, and the (read ...) entry calls
#                         read -- which eats the tool's own stdin (the rest
#                         of doctest.x vanishes and the run "succeeds")
#   x/repl/launch      -- not a module, a launcher that exists to be cat'd
#                         (its body is (%banner) (repl)): importing it starts
#                         a REPL mid-walk, which eats the tool's own stdin
#                         exactly like x/constructs -- every module sorting
#                         after x/repl/launch silently vanished (40 doctests,
#                         251 -> 211, caught 2026-07-20)
#   x/boot/helium|xenon|radon
#                      -- not modules, dialect BODIES that exist to be
#                         included by the lib entries (#95): each
#                         starts with a raw (include "lib/x-core.x"),
#                         unconditional by design, so importing one
#                         re-boots core inside this already-booted walk
#                         (post-boot reader re-registration SIGSEGVs)
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
  | grep -v -E '^x/tool/asm/|^x/constructs$|^x/repl/launch$|^x/boot/(helium|xenon|radon)$')

# Generate to a temp file so the output can be VERIFIED before it is emitted.
# The failure mode this guards is silent truncation: an import that reads
# stdin (a REPL, a (read ...) data table) eats the rest of doctest.x, the
# process exits 0, and the shrunken spec runs green with fewer tests. The
# census trailer is doctest.x's LAST output, so its absence is proof the walk
# did not finish -- and a non-empty failed-imports list is the same disease
# with a guard in the way (those modules' examples are silently absent).
_TMP=$(mktemp) || exit 1
trap 'rm -f "$_TMP"' EXIT

{
  printf '(alloc-limit! %s)\n' "$X_ALLOC_LIMIT_OBJS"
  cat lib/x-core.x tools/doctest.x
} | "$X_BIN" $_MODS > "$_TMP"

if ! grep -q '^failed imports: ' "$_TMP"; then
  echo "doctest.sh: FAIL -- census trailer missing: the module walk was truncated" >&2
  echo "doctest.sh: (an import is eating stdin; see the denylist in this file)" >&2
  exit 1
fi
if ! grep -q '^failed imports: ()$' "$_TMP"; then
  echo "doctest.sh: FAIL -- some imports failed; their examples are silently absent:" >&2
  grep '^failed imports: ' "$_TMP" >&2
  exit 1
fi

cat "$_TMP"
