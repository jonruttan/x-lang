#!/bin/sh
# path-literals.sh -- ratchet: root-relative load-path literals are
# BOOT-CLOSURE ONLY.
#
# A "lib/..." (or "tools/...", "apps/...") include in a runtime module
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

cd "$(dirname "$0")/.." || exit 1

FOUND=0
for f in $(find lib apps -name '*.x' \
    ! -path 'lib/x-core.x' ! -path 'lib/x-base.x' \
    ! -path 'lib/x.x' ! -path 'lib/he.x' ! -path 'lib/xe.x' ! -path 'lib/rn.x' \
    ! -path 'lib/x/boot/*' ! -path 'apps/*/run.x' | sort); do
	HITS=$(sed 's/;.*//' "$f" \
		| grep -nE '\((include|include-once|require-once)[[:space:]]+"(lib|tools|apps)/')
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
