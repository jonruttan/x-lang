#!/bin/sh
# bare-globals-scan.sh -- bare top-level name ratchet (#108)
#
# The shared boot/core layers may bind only the bare names the manifest
# (tools/contract/bare-globals.x) lists: the approved keep-list survivors plus
# the not-yet-swept remainder, which may only shrink.  Scans every top-level
# (def NAME ...) / (doc (def NAME ...)) / (def-class NAME ...) in
# lib/x-core.x + lib/x/boot/*.x + lib/x/core/*.x whose NAME is not
# %-private, and diffs BOTH directions against the manifest:
#   - a bare def absent from the manifest fails (the surface cannot grow);
#   - a manifest row with no def fails (stale rows die with their defs).
# C-bound bare names are engine/tools/contract/isa.x's %isa-bare section, not this file.
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
cd "$(dirname "$0")/../.."

SCAN_FILES="lib/x-core.x $(find lib/x -name '*.x' | grep -v -e 'lib/x/xe\.x' -e 'lib/x/rn\.x' -e 'lib/x/tool/' | sort | tr '\n' ' ')"
MANIFEST=tools/contract/bare-globals.x

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

# The (global NAME) marks (x-lang#719).  A scoped module's provide binds in
# the root only its classes and the exports it marks (global NAME)
# (lib/x/boot/module.x), so the marks are how a scoped module keeps a name of
# this manifest global.  Every mark must name a manifest row, and every
# manifest name a scoped module exports must carry the mark -- unmarked, it
# would quietly stop being bound in the root.  Each line below is FILE and an
# export, a marked one written @NAME; a provide list runs to its first `)`
# once the marks are folded, and comments are stripped a line at a time.
exports=$(for f in $(find lib -name '*.x' | sort); do
  sed 's/;.*$//' "$f" | tr '\n' ' ' | sed 's/(global \([^()]*\))/@\1/g' \
    | grep -o '(provide [^)]*' \
    | awk -v f="$f" '{ for (i = 3; i <= NF; i++) print f " " $i }'
done)
echo "$exports" | while read -r f n; do
  [ -n "$n" ] || continue
  case "$n" in
    @*) echo "$listed" | grep -qx "${n#@}" \
          || { echo "bare-globals: $f marks (global ${n#@}), which is not a manifest row"; exit 1; } ;;
    *)  grep -q '^(module ' "$f" || continue
        echo "$listed" | grep -qx "$n" \
          && { echo "bare-globals: $f exports $n, a manifest name, without (global $n) -- it would not be bound in the root"; exit 1; } ;;
  esac
done || fail=1

[ "$fail" -eq 0 ] && echo "bare-globals: boot/core top level matches the manifest, and the scoped modules' (global ...) marks match it too."
exit $fail
