#!/bin/sh
# platform-seam.sh -- the build triple is parsed in one place.
#
# `x-machine` is a string the engine binds, e.g. "arm64-apple-darwin25.5.0".
# Parsed in more than one module, the spellings diverge: Darwin spells A64
# "arm64" while GNU triplets spell it "aarch64", so a module that learns one
# is wrong about the other.
#
# Parsing is forbidden, using is not.  Handing the whole triple to a hash as a
# cache key, or putting it in a diagnostic, treats it as an opaque identity and
# is fine -- lib/x/tool/compile.x does both.  What belongs to the platform
# layer is taking it apart: substring tests that decide what OS or
# architecture this is.
#
# The triple is an interim.  What an engine should hand over is a declared
# (param os ...) / (param arch ...) row, a fact it knows at build time rather
# than a substring of a string it happens to print.  Keeping the parse in one
# place makes that a one-file change when the stamped params arrive.
set -e

ROOT="$(cd "$(dirname "$0")/../.." && pwd)"
cd "$ROOT"

SEAM="lib/x/platform/syscall.x"
[ -f "$SEAM" ] || { echo "platform-seam: no platform layer at $SEAM" >&2; exit 2; }

W="${TMPDIR:-/tmp}/platform-seam.$$"
trap 'rm -f "$W"' EXIT INT TERM
fail=0

# A parse is a substring test whose subject is the triple.  Both spellings the
# tree has used: the Str8 protocol's `includes?`, and the boot-level byte search
# the platform layer itself must use (it loads before that protocol exists).
: > "$W"
for f in $(grep -rl "x-machine" lib apps --include='*.x' 2>/dev/null | sort); do
	[ "$f" = "$SEAM" ] && continue
	sed 's/;.*//' "$f" \
		| grep -nE '(includes\?|%os-contains\?|byte-sub|str-index)[^)]*x-machine' \
		| sed "s|^|$f:|" >> "$W" || true
done

if [ -s "$W" ]; then
	echo "platform-seam: the build triple is taken apart outside the platform layer:"
	sed 's/^/    /' "$W"
	echo "FAIL: parse it in $SEAM and export a predicate, or -- if the whole"
	echo "  triple is being used as an opaque value (a cache key, a message) --"
	echo "  that is allowed and this pattern is a false positive worth narrowing."
	fail=1
fi

if [ "$fail" -ne 0 ]; then exit 1; fi
users=$(grep -rl "x-machine" lib apps --include='*.x' 2>/dev/null | wc -l | tr -d ' ')
echo "platform-seam: the triple is parsed only in $SEAM ($users files mention it)."
exit 0
