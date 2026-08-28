#!/bin/sh
# path-literals.sh -- ratchet: root-relative load-path literals are
# BOOT-CLOSURE ONLY.
#
# A "lib/..." (or "tools/...", "apps/...", "ext/...") include in a runtime module
# resolves against the process cwd, so it works only when cwd is the repo
# root -- it breaks installed trees ONLY, the one environment CI never
# runs.  Runtime modules load siblings via import
# (root-resolved) or ./-relative include-once (file-relative), both of
# which work from any tree root.
#
# Allowed: the dialect entries + boot bodies (flattened away by the
# amalgam generator at install time) and app entries (self-booting,
# amalgamated the same way).  Comments are stripped before matching, so a
# commented-out include does not trip the gate.

cd "$(dirname "$0")/../.." || exit 1

FOUND=0
for f in $(find lib apps -name '*.x' \
    ! -path 'lib/x-core.x' ! -path 'lib/x-base.x' \
    ! -path 'lib/x.x' ! -path 'lib/he.x' ! -path 'lib/xe.x' ! -path 'lib/rn.x' \
    ! -path 'lib/x/boot/*' ! -path 'apps/*/run.x' | sort); do
	HITS=$(sed 's/;.*//' "$f" \
		| grep -nE '\((include|include-once|require-once)[[:space:]]+"(lib|tools|apps|ext)/')
	if [ -n "$HITS" ]; then
		FOUND=1
		printf '%s\n' "$HITS" | sed "s|^|$f:|"
	fi
done

if [ "$FOUND" != 0 ]; then
	echo "path-literals: FAIL -- root-relative load literals outside the boot closure (use import or ./-relative include-once)" >&2
	exit 1
fi
echo "path-literals: ok"

# ---------------------------------------------------------------------------
# COMPILER INCLUDE PATHS must name directories that exist.
#
# WHY THIS EXISTS.  lib/x/tool/compile.x hands cc a pair of -I paths so the
# generated C can find the engine's headers.  When those headers moved to the
# engine the paths went stale, and nothing said so: the JIT lane
# is STRESS-gated, so the only thing that runs it is CI's stress job, and the
# failure arrived there as 150 specs reporting "interpreter died mid-batch"
# -- three inference steps from "cc could not find x.h".  Every other spec
# suite passed, locally and on the PR's fast tier.
#
# It is a one-line scan, so it runs on every push instead of waiting for the
# heavy lane.  Same shape as the include ratchet above: a path literal in the
# runtime library that must resolve.
BAD=0
for f in $(grep -rl '"-I' lib apps --include='*.x' 2>/dev/null | sort); do
	for inc in $(sed 's/;.*//' "$f" | grep -o '"-I[^"]*"' | sed 's/^"-I//; s/"$//'); do
		case "$inc" in .|./) continue;; esac
		[ -d "$inc" ] && continue
		echo "$f: -I$inc does not exist" >&2
		BAD=1
	done
done

if [ "$BAD" != 0 ]; then
	echo "include-paths: FAIL -- a compiler -I path in the runtime library names a directory that is not there" >&2
	exit 1
fi
echo "include-paths: ok"

# ---------------------------------------------------------------------------
# APP DATA PATHS are root-relative literals too, and the include scan above
# cannot see them.
#
# WHY THIS EXISTS.  apps/logo/serve.x read its viewer template from a bare
# "apps/logo/viewer.html".  That is not an include, so the ratchet at the top
# of this file -- which matches (include "lib/...") forms -- passed it every
# time, for as long as it existed.  It resolves against the process cwd, and
# x.sh forces cwd to the repo root in a checkout, so every test and every
# developer run found the file.  An INSTALLED tree does not: the app is at
# share/x/apps/logo/ and the user's cwd is wherever they happen to be, so the
# viewer failed with `io: Could not read turtle.html` for every installed
# user, in the one environment nothing ran in.
#
# THE RULE, from docs/lang-contract.md: an app tree has exactly ONE
# file that may know the layout -- its entry, which is already exempt above
# and is where the amalgam generator flattens the literals away.  Every other
# file reaches data through a root the entry armed and named.
#
# SCOPE IS apps/, NOT lib/.  A library module is loaded from the platform's
# own root and its doc (sample ...) / (example ...) strings legitimately name
# repo paths -- "(File stat \"lib/x.x\")" is documentation, not a load.
# Widening this to lib/ would be a false-positive generator; the relocatable
# trees the contract governs are the app trees.
BAD=0
for f in $(find apps -name '*.x' ! -path 'apps/*/run.x' | sort); do
	HITS=$(sed 's/;.*//' "$f" | grep -nE '"(lib|apps|tools|ext)/[^"]*"')
	if [ -n "$HITS" ]; then
		printf '%s\n' "$HITS" | sed "s|^|$f:|"
		BAD=1
	fi
done

if [ "$BAD" != 0 ]; then
	echo "app-data-paths: FAIL -- a root-relative literal outside an app entry (resolve it through the root the entry arms; see docs/lang-contract.md)" >&2
	exit 1
fi
echo "app-data-paths: ok"
