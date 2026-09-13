#!/bin/sh
# engine-seam.sh -- the runtime library names its engine in one place.
#
# x-lang is implementation-agnostic by design: x-engine-c is one engine, and a
# second implementation should require no edit to lib/.  This gate holds that:
# `ext/<engine>` may appear in lib/ only in the seam file, or in a row listed
# here with its reason.
#
# The seam is lib/x/boot/engine.x -- both boot contract includes plus the engine
# root as data.  Pointing x-lang at another engine is a change to that one file.
#
# Comments are exempt.  Several modules cite the layout contract by path in a
# doc string, and forbidding that would trade documentation for a tidier grep.
# What matters is that no module resolves a path to a specific engine on its
# own.  One site keeps its literal for the reason given in its row below:
# centralising it would make a stronger check vacuous.
set -e

ROOT="$(cd "$(dirname "$0")/../.." && pwd)"
cd "$ROOT"

SEAM="lib/x/boot/engine.x"
[ -f "$SEAM" ] || { echo "engine-seam: no seam at $SEAM" >&2; exit 2; }

# path => why it may name the engine directly
exempt_reason() {
	case "$1" in
		"$SEAM")
			echo "the seam itself" ;;
		lib/x/tool/compile.x)
			# check-path-literals greps for "-I..." LITERALS and asserts each names
			# a real directory.  That assertion exists because the JIT's include
			# paths broke silently during the engine split and only CI's
			# STRESS-gated lane caught it.  Routing them through the seam's
			# %engine-root would remove the literals, the grep would match nothing,
			# and the check would pass while checking nothing -- trading a live,
			# machine-checked assertion for a tidier grep.  The literal stays.
			echo "keeps -I literals so check-path-literals can verify they exist" ;;
		lib/img.x)
			# The state-image loader's dialect boots with no library and so no
			# seam: it is what runs BEFORE anything that could define
			# %engine-root.  It reaches the two contract files it needs -- the
			# base paths and the object layout -- by the same engine link the
			# seam itself resolves, and nothing else in it names the engine.
			echo "boots before the seam exists; reaches the contract by the engine link" ;;
		*) return 1 ;;
	esac
}

# Naming an engine has two spellings, and a module may use neither:
# `ext/x-engine-c` (one implementation, by its repo path) or `engine/` (the
# seam's symlink).  The second reads as engine-agnostic, but a module that
# reaches through it is still resolving the engine's layout on its own behalf
# rather than taking it from the seam.  Matching only the first would also
# leave the gate matching a spelling lib/ no longer uses.
PATTERN='ext/x-engine|"engine/|-Iengine/'

fail=0
found=$(grep -rlnE "$PATTERN" lib --include='*.x' 2>/dev/null | sort || true)
for f in $found; do
	# Only occurrences that RESOLVE a path count.  Two kinds are documentation and
	# are dropped: `;` comments, and doc-form strings -- (doc ...), (note ...) and
	# their siblings, which several modules use to tell a reader where the layout
	# contract lives.  Forbidding those would trade real documentation for a tidier
	# grep; a reader told where the contract is can go and read it.
	hits=$(sed 's/;.*//' "$f" \
		| grep -vE '^[[:space:]]*\((doc|note|sample|example|returns|param)[[:space:]]' \
		| grep -cE "$PATTERN" || true)
	[ "$hits" -gt 0 ] || continue
	if reason=$(exempt_reason "$f"); then
		printf "  ok      %-28s (%s)\n" "$f" "$reason"
	else
		printf "  UNSEAMED %-27s names an engine directly (%s occurrences)\n" "$f" "$hits"
		fail=1
	fi
done

if [ "$fail" -ne 0 ]; then
	echo "FAIL: the runtime library must name its engine only in $SEAM."
	echo "  Use %engine-root / %engine-contract-root from the seam, or add a row to"
	echo "  this script's exemptions with the reason the literal has to stay."
	exit 1
fi
echo "engine-seam: lib/ names its engine only where it is meant to."
exit 0
