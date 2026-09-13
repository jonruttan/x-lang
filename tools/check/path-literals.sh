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
    ! -path 'lib/x.x' ! -path 'lib/he.x' ! -path 'lib/xe.x' ! -path 'lib/rn.x' ! -path 'lib/img.x' \
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
# Compiler include paths must name directories that exist.
#
# lib/x/tool/compile.x hands cc a pair of -I paths so the generated C can find
# the engine's headers.  A stale path there surfaces only in the JIT lane,
# which is stress-gated, and arrives as specs reporting "interpreter died
# mid-batch" rather than as "cc could not find x.h".  This scan is one line,
# so it runs on every push instead of waiting for the heavy lane.  Same shape
# as the include ratchet above: a path literal in the runtime library that
# must resolve.
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
# App data paths are root-relative literals too, and the include scan above
# cannot see them: a bare "apps/NAME/file.html" is not an include.  Such a
# path resolves against the process cwd, which x.sh forces to the repo root in
# a checkout, so it reads correctly there and fails in an installed tree, where
# the app sits under share/x/apps/ and the cwd is wherever the user is.
#
# The rule, from docs/lang-contract.md: an app tree has exactly one file that
# may know the layout -- its entry, which is exempt above and is where the
# amalgam generator flattens the literals away.  Every other file reaches data
# through a root the entry armed and named.  A lang bundle is covered from the
# other side: x-logo's CI asserts its data goes through %lang-root and never
# %install-root.
#
# apps/ is empty at present, so this scan has nothing to read.  It stays
# because apps/ remains a live resolution step (see apps/README.md).
#
# The scope is apps/, not lib/.  A library module is loaded from the
# platform's own root, and its doc (sample ...) / (example ...) strings
# legitimately name repo paths -- "(File stat \"lib/x.x\")" is documentation,
# not a load.
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
