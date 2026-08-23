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
ENGINE_DIR="${X_ENGINE_DIR:-engine}"
PATHS="$ENGINE_DIR/tools/contract/base-paths.x"
[ -f "$PATHS" ] || { echo "base-routes: no base-paths.x at $PATHS" >&2; exit 2; }

W="${TMPDIR:-/tmp}/base-routes.$$"
mkdir -p "$W"
trap 'rm -rf "$W"' EXIT INT TERM

# What the library asks for, by name.
#
# THROUGH THE WRAPPERS TOO.  This matched only the two resolvers directly, and
# lib/x/type/struct.x reaches thirty-odd routes through %type-parent-path -- so
# the check reported "all 16 routes are declared" while the library needed 25,
# and x-engine-rust died on type-analyse-stack with a green gate behind it.
# Any helper that forwards a name to %reflect-path belongs in this list.
grep -rhoE "(%reflect-path|%reflect-base-cell|%type-parent-path) \(lit [a-z-]+\)" lib/ \
	| grep -oE "lit [a-z-]+" | sed 's/lit //' | sort -u > "$W/needed"

# What the engine declares. A row is (name root step ...).
sed -n 's/^  (\([a-z-][a-z-]*\) .*/\1/p' "$PATHS" | sort -u > "$W/declared"

# --- and the thing a name-based check cannot see at all --------------------
# A route resolved by NAME is portable; the same steps spelled out are not.
# Five sites walked the base with literal first/rest chains -- module.x, both
# %files readers, profile.x, intrinsics.x's line counter -- every one of them
# reproducing x-engine-c's layout by hand. They passed this check by never
# naming a route, and they are exactly what decision L1 forbids: the steps are
# the engine's, so a literal walk lands wherever a DIFFERENT engine put
# something else. module.x then mutated what it found, which on x-engine-rust
# scribbled past the false singleton and made #f truthy.
#
# Matched loosely on purpose: any first/rest chain three deep reaching %base is
# suspicious whatever its shape, and a false positive here costs one comment
# while a false negative costs a boot.
walks=$(grep -rnE "\((first|rest) \((first|rest) \((first|rest) [^)]*\(%base\)" lib/ \
	| grep -v '^\s*[0-9]*:\s*;' | grep -vE ":[0-9]+:\s*;" || true)
if [ -n "$walks" ]; then
	echo "base-routes: the library walks the base by LITERAL STEPS, not by name:" >&2
	printf '%s\n' "$walks" | sed 's/^/  /' >&2
	echo "  Steps belong to the engine (decision L1); resolve a committed route" >&2
	echo "  instead: (%reflect-base-cell (lit NAME))." >&2
	exit 1
fi

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
# The engine's name comes from its own declaration, not from the directory it
# sits in: a checkout and an unpacked release are the same engine at two
# different paths.  See tools/contract/gen-engine-xon.sh's `name`.
ename=$(sed -n 's/^(engine-name "\(.*\)").*/\1/p' "$ENGINE_DIR/x-engine.xon" 2>/dev/null | head -1)
[ -n "$ename" ] || ename=$(basename "$ENGINE_DIR")
echo "base-routes: all $n routes the library walks are declared by $ename."
exit 0
