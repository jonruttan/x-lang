#!/bin/sh
# base-routes.sh -- the engine's base carries the routes the library walks.
#
# A GAP THE PROFILE DOES NOT COVER.  x-engine-rust reached the `core` profile --
# every capability satisfied, every conformance case that exists passing -- with
# a base-paths.x declaring TWO routes.  The library walks eleven, by name, and
# would have died on the first one.  Nothing said so: the declaration digests
# base-paths.x without reading it, and `reflect/layout-data` claims only that an
# engine SHIPS the file.
#
# Route names are a contract even though the paths are not.  Decision L1 makes
# the STEPS an engine's own business -- `(prims base f)` here, `(prims base f r
# r r r r r r r r f)` in the C -- precisely so a different object model can
# arrange its base differently.  What both must agree on is what the routes are
# CALLED, because the library resolves them by name at runtime:
#
#   lib/x/boot/registry.x:  (%reflect-step (%base) (%reflect-path name %base-paths))
#
# So this derives the names from the call sites, the way requires.x is derived
# from prim-ref sites, and checks the engine declares each one.
set -e

ROOT="$(cd "$(dirname "$0")/../.." && pwd)"
cd "$ROOT"
ENGINE_DIR="${X_ENGINE_DIR:-ext/x-engine-c}"
PATHS="$ENGINE_DIR/tools/contract/base-paths.x"
[ -f "$PATHS" ] || { echo "base-routes: no base-paths.x at $PATHS" >&2; exit 2; }

W="${TMPDIR:-/tmp}/base-routes.$$"
mkdir -p "$W"
trap 'rm -rf "$W"' EXIT INT TERM

# What the library asks for, by name.
grep -rhoE "%reflect-path \(lit [a-z-]+\)|%reflect-base-cell \(lit [a-z-]+\)" lib/ \
	| grep -oE "lit [a-z-]+" | sed 's/lit //' | sort -u > "$W/needed"

# What the engine declares. A row is (name root step ...).
sed -n 's/^  (\([a-z-][a-z-]*\) .*/\1/p' "$PATHS" | sort -u > "$W/declared"

missing=$(comm -23 "$W/needed" "$W/declared" | tr '\n' ' ' | sed 's/ $//')
if [ -n "$missing" ]; then
	echo "base-routes: $ENGINE_DIR declares no route named:"
	echo "  $missing"
	echo "  The library resolves these by name at runtime and would die on the"
	echo "  first one. The STEPS are the engine's to choose; the NAMES are not."
	echo "FAIL: the engine's base cannot carry this library."
	exit 1
fi
n=$(wc -l < "$W/needed" | tr -d ' ')
echo "base-routes: all $n routes the library walks are declared by $(basename "$ENGINE_DIR")."
exit 0
