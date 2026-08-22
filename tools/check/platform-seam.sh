#!/bin/sh
# platform-seam.sh -- the build triple is PARSED in one place.
#
# `x-machine` is a string the engine binds, e.g. "arm64-apple-darwin25.5.0".
# Three modules used to pick it apart independently -- lib/x/platform/syscall.x
# for the OS, lib/x/tool/asm.x for the OS and the arch, lib/x/tool/compile.x for
# the OS again -- and only one of the three knew that Darwin spells A64 "arm64"
# while GNU triplets spell it "aarch64".  Knowledge that lives in whichever file
# needed it most recently is knowledge that is wrong somewhere else.
#
# WHAT IS FORBIDDEN IS PARSING, NOT USING.  Handing the whole triple to a hash as
# a cache key, or putting it in a diagnostic, treats it as an opaque identity and
# is fine -- lib/x/tool/compile.x does both.  What belongs to the platform layer
# is taking it APART: substring tests that decide what OS or architecture this is.
#
# THE TRIPLE IS THE INTERIM ANYWAY.  What an engine should hand over is a declared
# (param os ...) / (param arch ...) row -- a fact it knows at build time rather
# than a substring of a string it happens to print.  Keeping the parse in one
# place is what makes that a one-file change when the stamped params arrive.
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
