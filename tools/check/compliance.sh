#!/bin/sh
# compliance.sh -- does an engine do what its x-engine.xon claims?
#
#   Usage: sh tools/check/compliance.sh [engine-dir]     (default: ext/x-engine-c)
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
#   DYNAMIC   the generated bare suite, run by the engine's own tests/bare harness
#             (it arms the allocation ceiling and loads nothing, which is why a
#             probe there sees engine capabilities and not library ones).
#   UNTESTED  every declared row for which NO experiment exists is named out loud.
#             A suite that silently skips a claim is indistinguishable from one
#             that verified it, and the skipped rows here are guarantees -- the
#             kind whose violation is silent corruption.
set -e

ROOT="$(cd "$(dirname "$0")/../.." && pwd)"
cd "$ROOT"
ENGINE="${1:-ext/x-engine-c}"
[ -d "$ENGINE" ] || { echo "compliance: no engine at $ENGINE" >&2; exit 2; }
ENGINE_ABS="$(cd "$ENGINE" && pwd)"
XON="$ENGINE_ABS/x-engine.xon"
[ -f "$XON" ] || { echo "compliance: no declaration at $XON" >&2; exit 2; }

RUNNER="$ENGINE_ABS/tests/bare/bare-runner.sh"
[ -f "$RUNNER" ] || { echo "compliance: engine has no bare harness at $RUNNER" >&2; exit 2; }

W="${TMPDIR:-/tmp}/compliance.$$"; mkdir -p "$W"
trap 'rm -rf "$W"' EXIT INT TERM
fail=0

digest() {
	if command -v sha256sum >/dev/null 2>&1; then sha256sum "$1" | awk '{print $1}'
	else shasum -a 256 "$1" | awk '{print $1}'; fi
}

echo "compliance: $(basename "$ENGINE_ABS")"

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
