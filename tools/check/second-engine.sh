#!/bin/sh
# second-engine.sh -- the contract apparatus works for an engine that is not ours.
#
# x-lang's whole engine-contract arc rests on a claim: the vocabulary, the
# generator and the resolver describe ANY engine meeting the contract, not just
# x-engine-c.  Nothing tested that claim while only one engine existed, and the
# first time the apparatus was pointed at a second one it produced two wrong
# answers:
#
#   - tools/check/engine-contract.sh hardcoded ext/x-engine-c, so the gate that
#     answers the resolver's question could not be asked about another engine.
#   - tools/contract/gen-engine-xon.sh added explicitly-grouped coordinates from
#     features.x WITHOUT intersecting them against the engine's own ISA, so an
#     engine with zero foreign-door rows had (provides isa/ffi-call) written into
#     its declaration BY THE TOOLING.  Compliance would then have audited a claim
#     the engine never made.
#
# Both are fixed.  This gate keeps them fixed by running the apparatus against
# tests/x/fixtures/engine-min -- a PAPER engine, contract files and nothing else,
# declaring `core` and no more -- and asserting the resolver's answer is the
# refusal it should be, naming exactly the groups that engine lacks.
#
# A fixture is cheaper than remembering.  The alternative is that these come back
# the next time the vocabulary grows, and are found by whoever writes the second
# engine for real -- which is the worst possible moment.
set -e

ROOT="$(cd "$(dirname "$0")/../.." && pwd)"
cd "$ROOT"
FIX="tests/x/fixtures/engine-min"
[ -d "$FIX" ] || { echo "second-engine: no fixture at $FIX" >&2; exit 2; }

W="${TMPDIR:-/tmp}/second-engine.$$"
mkdir -p "$W"
trap 'rm -rf "$W"' EXIT INT TERM
fail=0

# --- the declaration the generator writes for it -----------------------------
sh tools/contract/gen-engine-xon.sh "$FIX" > "$W/xon" 2>"$W/err" || {
	echo "second-engine: the generator failed against the fixture:" >&2
	sed 's/^/    /' "$W/err" >&2
	exit 1
}

# It must claim `core` and NOTHING above it.
profiles=$(awk '/^\(profile /{ gsub(/[()]/,""); print $2 }' "$W/xon" | sort | tr '\n' ' ')
if [ "$profiles" != "core " ]; then
	echo "  PROFILES: the paper engine should hold exactly 'core', got: $profiles"
	fail=1
fi

# It must NOT claim a capability it has no rows for.  This is the regression the
# generator shipped: explicit group membership applied to every engine.
for atom in isa/ffi-call isa/syscall isa/gc isa/sys; do
	if grep -q "^(provides $atom)\$" "$W/xon"; then
		echo "  FABRICATED: declaration claims $atom, which the fixture has no rows for"
		fail=1
	fi
done

# --- a PARTIALLY implemented group is not a capability ------------------------
# The generator used to derive (provides G) from "the engine has at least one row
# tagged for G".  That is not what a capability means -- docs/engine-contract.md
# defines one as "the coordinates in that group resolve", all of them -- and the
# gap is not academic: an engine implementing `error` and nothing else of the
# evaluator declared the whole 25-instruction isa/spine group, and the resolver
# then reported it satisfied.  The library would have died on its first `fn`, at
# runtime, after the one check whose entire job was to say so beforehand.
#
# Here the fixture is trimmed to cover all but ONE coordinate of a group it
# otherwise implements in full.  Derived from the real fixture rather than
# committed as a second one, so it cannot drift out of step with the first.
mkdir -p "$W/partial/tools/contract"
cp "$FIX/tools/contract/"*.x "$W/partial/tools/contract/" 2>/dev/null || true
awk '
	/^  \(/ {
		l = $0; sub(/;.*/, "", l); gsub(/[()]/, "", l); n = split(l, a, " ")
		if (n >= 2 && a[n] == "alloc") { seen++; if (seen == 1) next }
	}
	{ print }' "$FIX/tools/contract/isa.x" > "$W/partial/tools/contract/isa.x"

before=$(awk '/^  \(/{l=$0;sub(/;.*/,"",l);gsub(/[()]/,"",l);n=split(l,a," ");if(n>=2&&a[n]=="alloc")c++}END{print c+0}' "$FIX/tools/contract/isa.x")
after=$(awk  '/^  \(/{l=$0;sub(/;.*/,"",l);gsub(/[()]/,"",l);n=split(l,a," ");if(n>=2&&a[n]=="alloc")c++}END{print c+0}' "$W/partial/tools/contract/isa.x")
if [ "$after" -ne $((before - 1)) ]; then
	echo "  PARTIAL: the trim did not remove exactly one alloc row ($before -> $after);"
	echo "    the case below would prove nothing."
	fail=1
fi

# The engine SHIPS its declaration, so write it where an engine keeps it -- the
# resolver reads the file, not the generator.  Testing through a directory with
# no declaration would exercise the missing-file path instead of the coverage
# one, which is how the first draft of this case passed for the wrong reason.
sh tools/contract/gen-engine-xon.sh "$W/partial" > "$W/pxon" 2>"$W/perr" || {
	echo "  PARTIAL: the generator failed against the trimmed fixture:" >&2
	sed 's/^/    /' "$W/perr" >&2
	fail=1
}
if grep -q "^(provides isa/alloc)\$" "$W/pxon"; then
	echo "  PARTIAL: an engine missing one of the 12 alloc coordinates still"
	echo "    declared (provides isa/alloc).  A capability is coverage of the"
	echo "    group, not presence in it."
	fail=1
fi
if grep -q "^(profile core)\$" "$W/pxon"; then
	echo "  PARTIAL: the trimmed engine still holds the core profile, which it"
	echo "    cannot -- core names isa/alloc."
	fail=1
fi
cp "$W/pxon" "$W/partial/x-engine.xon"
X_ENGINE_DIR="$W/partial" sh tools/check/engine-contract.sh > "$W/pout" 2>&1 && {
	echo "  PARTIAL: the resolver ACCEPTED an engine with an incomplete group"
	fail=1
}
grep -q "SATISFACTION:.*isa/alloc" "$W/pout" || {
	echo "  PARTIAL: refusal did not name isa/alloc"
	fail=1
}

# --- an engine with NO declaration is refused, not accepted -------------------
# The gate printed "satisfaction and staleness UNCHECKED" and exited 0, so an
# engine directory it had never looked at passed.  Unknown is not satisfied.
mkdir -p "$W/undeclared/tools/contract"
cp "$FIX/tools/contract/"*.x "$W/undeclared/tools/contract/"
X_ENGINE_DIR="$W/undeclared" sh tools/check/engine-contract.sh > "$W/uout" 2>&1 && {
	echo "  UNDECLARED: an engine with no x-engine.xon was ACCEPTED"
	fail=1
}

# --- the resolver's answer ---------------------------------------------------
# It must REFUSE, and name what is missing.  A gate that only checked "it fails"
# would pass on a failure for any reason at all, including the gate being broken.
X_ENGINE_DIR="$FIX" sh tools/check/engine-contract.sh > "$W/out" 2>&1 && {
	echo "  RESOLVER: the paper engine was ACCEPTED; it cannot run this library"
	fail=1
}
for atom in isa/ffi-call isa/gc isa/sys isa/syscall; do
	grep -q "SATISFACTION:.*$atom" "$W/out" || {
		echo "  RESOLVER: refusal did not name the missing $atom"
		fail=1
	}
done

# The requires derivation must NOT be perturbed by the candidate: what lib/ needs
# is a property of lib/.  Deriving it through a reduced engine's coordinate map
# once made requires.x look stale for no longer needing a collector.
if grep -q "DERIVED:" "$W/out"; then
	echo "  DERIVED: judging a candidate perturbed the requires derivation --"
	echo "    what the library needs is a property of the library, not of the"
	echo "    engine being judged."
	sed -n '/DERIVED:/,+4p' "$W/out" | sed 's/^/    /'
	fail=1
fi

if [ "$fail" -ne 0 ]; then
	echo "FAIL: the contract apparatus is not engine-agnostic."
	exit 1
fi
echo "second-engine: the apparatus judges a non-C engine correctly (refused, naming 4 gaps;\n  a group missing one coordinate is not a capability)."
exit 0
