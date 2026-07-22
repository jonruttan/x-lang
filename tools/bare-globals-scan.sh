#!/bin/sh
# bare-globals-scan.sh -- THE TOP LEVEL IS SACRED ratchet (#108)
#
# The shared boot/core layers may bind only the bare names the manifest
# (tools/bare-globals.x) lists: the approved keep-list survivors plus the
# not-yet-swept remainder, which may only SHRINK.  Scans every top-level
# (def NAME ...) / (doc (def NAME ...)) / (def-class NAME ...) in
# lib/x-core.x + lib/x/boot/*.x + lib/x/core/*.x whose NAME is not
# %-private, and diffs BOTH directions against the manifest:
#   - a bare def absent from the manifest fails (the surface cannot grow);
#   - a manifest row with no def fails (stale rows die with their defs).
# C-bound bare names are tools/isa.x's %isa-bare section, not this file.
#
# Top-level detection is indentation (<= 2 spaces): library style keeps
# module-level defs at column 0 (x-core.x's do-block at 2); fn-internal
# defs sit deeper and are %-named besides.
#
# SCOPE (#108 scope-extension round, 2026-07-22): the whole runtime
# library -- everything a user program inherits.  Excluded on purpose:
#   lib/x/{xe,rn}.x   dialect toolboxes ADD bare vocabulary by charter
#   lib/x/tool/       dev-tool DSLs (asm register names, profiler
#                     counters, lint internals) -- additive by design,
#                     and its indent style defeats the heuristic
# def-class is NOT scanned: classes ARE the sanctioned surface; a new
# class needs no manifest row.

set -e
cd "$(dirname "$0")/.."

SCAN_FILES="lib/x-core.x $(find lib/x -name '*.x' | grep -v -e 'lib/x/xe\.x' -e 'lib/x/rn\.x' -e 'lib/x/tool/' | sort | tr '\n' ' ')"
MANIFEST=tools/bare-globals.x

live=$(awk '
  /^ {0,2}\((doc \()?\(?def [a-z#]/ {
    line = $0
    sub(/^ */, "", line)
    sub(/^\(doc /, "", line)
    sub(/^\(/, "", line)
    sub(/^def /, "", line)
    sub(/[ )].*$/, "", line)
    if (line !~ /^%/) print line
  }
' $SCAN_FILES | sort -u)

listed=$(awk '/^\(def %bare-globals/{next} /^ *\(/{gsub(/[()]/,""); print $1}' "$MANIFEST" | sort -u)

fail=0
for n in $live; do
  echo "$listed" | grep -qx "$n" || { echo "bare-globals: UNLISTED bare def: $n (the top level is sacred -- home it or add a manifest row with justification)"; fail=1; }
done
for n in $listed; do
  echo "$live" | grep -qx "$n" || { echo "bare-globals: STALE manifest row: $n (def is gone -- delete the row; shrinking is the point)"; fail=1; }
done

[ "$fail" -eq 0 ] && echo "bare-globals: boot/core top level matches the manifest."
exit $fail
