#!/bin/sh
# compliance.sh -- does an engine do what its x-engine.xon claims?
#
#   Usage: sh tools/check/compliance.sh [engine-dir]     (default: engine)
#
# The third leg of the contract.  check-engine-contract compares `provides`
# against `requires` as TEXT, so it cannot catch an engine that declares more than
# it has: such an engine passes the gate, is chosen by the resolver, and fails in
# the field -- loudly for a capability, SILENTLY for a guarantee.  This runs the
# generated suite that tries to falsify each declared row against the real engine.
#
# Under-declaring is harmless (the engine is treated as less capable than it is),
# so everything here tests the OVER-declaring direction only.
#
# Three parts, and the third is the one that keeps the other two honest:
#   STATIC    the digests in x-engine.xon still match the files they name, and
#             every atom each declared profile needs is actually declared.
#   DYNAMIC   the generated bare suite, run through x-lang's OWN conformance
#             runner (tests/x/conformance/runner.sh).  It arms the allocation
#             ceiling and loads no library, which is why a probe there sees
#             engine capabilities and not library ones -- and it needs nothing
#             from the engine but the engine: an artifact with no tests/ in it
#             is a legitimate subject, and so is an engine that never built an
#             x-lang-shaped harness.
#   UNTESTED  every declared row for which NO experiment exists is named out loud.
#             A suite that silently skips a claim is indistinguishable from one
#             that verified it, and the skipped rows here are guarantees -- the
#             kind whose violation is silent corruption.
set -e

ROOT="$(cd "$(dirname "$0")/../.." && pwd)"
cd "$ROOT"
ENGINE="${1:-engine}"
[ -d "$ENGINE" ] || { echo "compliance: no engine at $ENGINE" >&2; exit 2; }
ENGINE_ABS="$(cd "$ENGINE" && pwd)"
XON="$ENGINE_ABS/x-engine.xon"
[ -f "$XON" ] || { echo "compliance: no declaration at $XON" >&2; exit 2; }

# NO PRECONDITION ON THE ENGINE'S OWN HARNESS.  This used to require
# $ENGINE/tests/bare/bare-runner.sh and refuse without it -- a leftover from the
# first version, which really did drive that harness.  The rewrite moved the
# checks to ordinary spec files run through x-lang's conformance runner (below),
# and the requirement stayed behind, guarding a dependency that no longer
# existed.  Nothing read the variable.
#
# It was not harmless.  Compliance is x-lang asking whether an engine does what
# it claims, and an engine that supplies the harness it is judged by holds the
# arbiter's pen -- the same reason the conformance suite lives here and not
# there.  In practice the dead line refused two legitimate subjects: a released
# engine (an artifact ships no tests) and any second implementation that does
# not happen to build an x-lang-shaped smoke harness.  Found by pointing this at
# an unpacked dist tarball.

W="${TMPDIR:-/tmp}/compliance.$$"; mkdir -p "$W"
trap 'rm -rf "$W"' EXIT INT TERM
fail=0

digest() {
	if command -v sha256sum >/dev/null 2>&1; then sha256sum "$1" | awk '{print $1}'
	else shasum -a 256 "$1" | awk '{print $1}'; fi
}

# The engine's name comes from its own declaration, not from the directory it
# sits in: a checkout and an unpacked release are the same engine at two
# different paths.  See tools/contract/gen-engine-xon.sh's `name`.
ename=$(sed -n 's/^(engine-name "\(.*\)").*/\1/p' "$XON" 2>/dev/null | head -1)
[ -n "$ename" ] || ename=$(basename "$ENGINE_ABS")
echo "compliance: $ename"

# --- STATIC: the digests still describe the files ----------------------------
want_isa=$(sed -n 's/^(isa "sha256:\([0-9a-f]*\)").*/\1/p' "$XON" | head -1)
have_isa=$(digest "$ENGINE_ABS/tools/contract/isa.x")
if [ -n "$want_isa" ] && [ "$want_isa" != "$have_isa" ]; then
	echo "  STALE-DIGEST: isa row says $want_isa, isa.x hashes to $have_isa"; fail=1
fi
want_lay=$(sed -n 's/^(layout "sha256:\([0-9a-f]*\)").*/\1/p' "$XON" | head -1)
if [ -n "$want_lay" ]; then
	cat "$ENGINE_ABS/tools/contract/obj-layout.x" \
	    "$ENGINE_ABS/tools/contract/base-paths.x" \
	    "$ENGINE_ABS/tools/contract/base-layout.x" > "$W/layout-all" 2>/dev/null || true
	have_lay=$(digest "$W/layout-all")
	if [ "$want_lay" != "$have_lay" ]; then
		echo "  STALE-DIGEST: layout row says $want_lay, the descriptors hash to $have_lay"; fail=1
	fi
fi

# --- DYNAMIC: the planned checks ---------------------------------------------
# The generator emits DATA and a PLAN; the checks themselves are ordinary spec
# files under tools/contract/compliance/, run through x-lang's own bare runner.
# Nothing here generates x-lang.
sh tools/contract/gen-compliance.sh "$ENGINE_ABS" "$W/gen" >/dev/null
nrun=0; nbad=0
while read -r specfile datafile label; do
	nrun=$((nrun + 1))
	if [ "$datafile" = "-" ]; then
		out=$(X_ENGINE_DIR="$ENGINE_ABS" sh tests/x/conformance/runner.sh "$specfile" 2>&1) || true
	else
		out=$(X_ENGINE_DIR="$ENGINE_ABS" X_EXTRA_PRELUDE="$datafile" \
			sh tests/x/conformance/runner.sh "$specfile" 2>&1) || true
	fi
	if printf '%s' "$out" | grep -q ", 0 failed"; then
		printf "  ok    %s\n" "$label"
	else
		nbad=$((nbad + 1)); fail=1
		printf "  FAIL  %s\n" "$label"
		printf '%s\n' "$out" | grep -E "expected:|got:" | sed 's/^/        /'
	fi
done < "$W/gen/plan"
echo "  $nrun declared rows checked, $nbad failed."

# --- UNTESTED: declared rows with no experiment ------------------------------
awk '/^\(guarantee /{ l=$0; gsub(/[()]/,"",l); $0=l; print $2 }' "$XON" | sort -u > "$W/claimed-g"
awk '$3=="guarantee" {print $4}' "$W/gen/plan" | sort -u > "$W/tested-g"
comm -23 "$W/claimed-g" "$W/tested-g" > "$W/untested"
if [ -s "$W/untested" ]; then
	echo "  UNTESTED guarantees (declared, no experiment yet):"
	sed 's/^/    /' "$W/untested"
fi

if [ "$fail" -ne 0 ]; then
	echo "compliance: FAIL -- the engine does not do everything it declares."
	exit 1
fi
echo "compliance: every testable declared row held."
exit 0
