#!/bin/sh
# engine-contract.sh -- hold the engine-contract vocabulary against the ISA.
#
# tools/contract/features.x is the closed vocabulary an engine's x-engine.xon and
# x-lang's requires.x both quote from.  A vocabulary that drifts from the surface
# it describes is worse than none: it reads as authority while naming nothing.
# This gate keeps the two in step.
#
# WHAT IT CHECKS
#   1. TOTAL      every isa.x row lands in exactly one capability group -- by its
#                 tag, or by explicit membership for a split tag.  A new C row
#                 cannot appear without being classified in the same commit.
#   2. DISJOINT   no coordinate is claimed by two groups.
#   3. GROUNDED   every explicitly-listed coordinate actually exists in isa.x, so
#                 a group cannot outlive the rows it names.
#   4. CLOSED     every atom named in a profile resolves -- to a capability, or to
#                 a profile defined before it.  No forward or dangling references.
#   5. SEPARATE   no profile names a PARAMETER.  Width, arch and OS are values an
#                 engine reports, not capabilities it has; `word-size = 8` in a
#                 requirement would lock out the 32-bit Pi.  Per-module needs go
#                 to tools/contract/constraints.x instead.
#
# WHY 1 AND 2 ARE THE POINT.  The `ffi` tag carries eleven rows that split three
# ways -- the pointer CASTS (mandatory: boot reads header words through them), the
# foreign DOOR (dlopen/dlsym/ptr-call), and the raw SYSCALL door.  Treating the
# tag as one group would have made dlopen mandatory for every engine, including a
# sandboxed one, and would have put the sandbox target out of reach on paper while
# it works in fact.  Since that split is hand-drawn, it is exactly the thing that
# rots -- so the partition is machine-checked against isa.x rather than trusted.
#
# Usage: sh tools/check/engine-contract.sh
set -e

ROOT="$(cd "$(dirname "$0")/../.." && pwd)"
cd "$ROOT"

FEAT="tools/contract/features.x"
# The engine under test.  Parameterised, because the question this gate answers --
# does this engine provide what x-lang needs -- is the RESOLVER's question, and a
# resolver that can only consider one engine is not resolving anything.  Found by
# pointing the apparatus at a second engine for the first time: everything else in
# the toolchain already took an engine directory, and this did not.
ENGINE_DIR="${X_ENGINE_DIR:-engine}"

# The engine's name comes from its own declaration, not from the directory it
# sits in: a checkout sits in `x-engine-c` and an unpacked release sits in
# `x-engine-c-<release>-<os>-<arch>`, and they are the same engine.  Reporting
# the path would hand a reader a name their pin.xon can never match.  See
# tools/contract/gen-engine-xon.sh's `name`.
engine_name() {
	_n=$(sed -n 's/^(engine-name "\(.*\)").*/\1/p' "$ENGINE_DIR/x-engine.xon" 2>/dev/null | head -1)
	[ -n "$_n" ] || _n=$(basename "$(cd "$ENGINE_DIR" 2>/dev/null && pwd -P || printf '%s' "$ENGINE_DIR")")
	printf '%s' "$_n"
}

# TWO ENGINES, TWO QUESTIONS, and conflating them was a bug this gate shipped
# with.  The REFERENCE surface is the language's own view of what instructions
# exist; the CANDIDATE is whatever engine is being judged.
#
#   partition + derived requires  ->  REFERENCE.  "What does lib/ need?" is a
#       property of lib/, and deriving it through a candidate's coordinate map
#       made a reduced engine appear to shrink the library's requirements: point
#       this at an engine with no collector and requires.x is reported stale for
#       no longer needing one.  The library needs exactly what it needs.
#   satisfaction + staleness      ->  CANDIDATE.  "Can THIS engine run it?"
#
# Found by pointing the apparatus at a second engine for the first time, which
# is what that exercise is for.
REFERENCE_DIR="${X_REFERENCE_DIR:-engine}"
ISA="$REFERENCE_DIR/tools/contract/isa.x"
REQ="tools/contract/requires.x"
CONS="tools/contract/constraints.x"
[ -f "$FEAT" ] || { echo "engine-contract: no vocabulary at $FEAT" >&2; exit 2; }
# The ISA is the ENGINE's file.  A missing one means an uninitialised submodule,
# not a passing check -- say so rather than reporting ok over nothing, which is
# the vacuous-pass shape the split turned up four times.
[ -f "$ISA" ] || { echo "engine-contract: no reference ISA at $ISA (submodule not initialised?)" >&2; exit 2; }

fail=0
note() { echo "  $1"; fail=1; }

# --- the ISA's view: coordinate -> tag --------------------------------------
# Catalog rows are (ns method tag); bare/keep rows are (name tag).  Both reduce
# to "coordinate tag", with a bare name keyed by itself.
awk '
	/^\(def %isa-catalog/ { sect="catalog"; next }
	/^\(def %isa-bare/    { sect="bare";    next }
	/^\(def %isa-keep/    { sect="keep";    next }
	/^\(def %isa-aliases/ { sect="";        next }   # x-level aliases: not C rows
	/^\(def %isa-values/  { sect="";        next }   # values, not instructions
	/^  \(/ {
		if (sect == "") next
		# Reassigning $0 re-splits with awk default FS, which ignores the
		# leading indent; split() with an explicit regex FS does not, and
		# yields an empty first field that shifts every coordinate.
		l = $0; sub(/;.*/, "", l); gsub(/[()]/, "", l); $0 = l
		if (sect == "catalog" && NF >= 3) print $1 "/" $2, $3
		else if (sect != "catalog" && NF >= 2) print $1, $2
	}
' "$ISA" > /tmp/ec-isa.$$

# --- the vocabulary's view ---------------------------------------------------
# capabilities: atom -> source (a tag, a build flag, `rows`, or `-`)
awk '/^\(def %feature-capabilities/{f=1;next} /^\)\)\)/{f=0}
     f && /^  \(/ { l=$0; sub(/;.*/,"",l); gsub(/[()]/,"",l); $0=l
                    if (NF>=2) print $1, $2 }' "$FEAT" > /tmp/ec-caps.$$
# explicit group membership: atom coordinate...
awk '/^\(def %feature-group-rows/{f=1;next} /^\)\)\)/{f=0}
     f && /^  \(/ { l=$0; sub(/;.*/,"",l); gsub(/[()]/,"",l); $0=l; print }' "$FEAT" > /tmp/ec-rows.$$
awk '/^\(def %feature-parameters/{f=1;next} /^\)\)\)/{f=0}
     f && /^  \(/ { l=$0; sub(/;.*/,"",l); gsub(/[()]/,"",l); $0=l; print $1 }' "$FEAT" > /tmp/ec-params.$$
# A profile row spans as many lines as it needs, so accumulate until its parens
# balance and emit ONE line per profile.  Treating each physical line as a row
# silently turned `core` into four bogus profiles named after their first atom --
# and passed, because those atoms happened to be real capabilities.
awk '/^\(def %feature-profiles/{f=1;next} /^\)\)\)/{f=0}
     f {
       l=$0; sub(/;.*/,"",l)
       if (l ~ /^[ \t]*$/) next
       buf = (buf == "" ? l : buf " " l)
       n = gsub(/\(/, "(", buf); m = gsub(/\)/, ")", buf)
       if (n > 0 && n == m) { gsub(/[()]/, "", buf); $0 = buf; $1=$1; print; buf = "" }
     }' "$FEAT" > /tmp/ec-prof-raw.$$

trap 'rm -f /tmp/ec-*.$$' EXIT INT TERM

# --- 1/2/3: the partition ----------------------------------------------------
echo "engine-contract:"

# tags that a capability claims wholesale
awk '$2 != "rows" && $2 != "-" { print $2 }' /tmp/ec-caps.$$ | sort -u > /tmp/ec-tagclaim.$$
# coordinates claimed explicitly, with their group
awk '{ for (i=2;i<=NF;i++) print $i, $1 }' /tmp/ec-rows.$$ | sort > /tmp/ec-explicit.$$

# (3) grounded: every explicit coordinate exists in the ISA
while read -r coord grp; do
	grep -q "^$coord " /tmp/ec-isa.$$ || note "GROUNDED: $grp names $coord, which is not an isa.x row"
done < /tmp/ec-explicit.$$

# (2) disjoint: no coordinate listed twice
dupes=$(awk '{print $1}' /tmp/ec-explicit.$$ | sort | uniq -d)
[ -z "$dupes" ] || note "DISJOINT: coordinate claimed by two groups: $dupes"

# (1) total: every ISA row is covered by its tag OR by an explicit row
while read -r coord tag; do
	if grep -q "^$tag$" /tmp/ec-tagclaim.$$; then continue; fi
	if grep -q "^$coord " /tmp/ec-explicit.$$; then continue; fi
	note "TOTAL: $coord (tag $tag) belongs to no capability group"
done < /tmp/ec-isa.$$

# a tag that is claimed wholesale must not ALSO be split explicitly
while read -r coord grp; do
	t=$(awk -v c="$coord" '$1==c {print $2}' /tmp/ec-isa.$$)
	if [ -n "$t" ] && grep -q "^$t$" /tmp/ec-tagclaim.$$; then
		note "DISJOINT: $coord is claimed both by tag $t and explicitly by $grp"
	fi
done < /tmp/ec-explicit.$$

# --- 4/5: profiles -----------------------------------------------------------
awk '{print $1}' /tmp/ec-caps.$$ | sort -u > /tmp/ec-atoms.$$
seen=""
while read -r line; do
	[ -n "$line" ] || continue
	name=$(echo "$line" | awk '{print $1}')
	for atom in $(echo "$line" | cut -d' ' -f2-); do
		if grep -q "^$atom$" /tmp/ec-params.$$; then
			note "SEPARATE: profile $name names the PARAMETER $atom -- parameters are values, not capabilities (see constraints.x)"
			continue
		fi
		if grep -q "^$atom$" /tmp/ec-atoms.$$; then continue; fi
		case " $seen " in *" $atom "*) continue ;; esac
		note "CLOSED: profile $name names $atom, which is neither a capability nor an earlier profile"
	done
	seen="$seen $name"
done < /tmp/ec-prof-raw.$$

# --- 6: requires.x is DERIVED, and re-derived here ---------------------------
# Rows are computed from the tree, never authored: join every (prim-ref ns method)
# site and every bare `syscall` call against the coordinate->group map, keep the
# ABOVE-CORE groups, and diff.  A row cannot be added by opinion, and cannot go
# stale when its subject changes.
if [ -f "$REQ" ]; then
	# coordinate -> group: explicit membership wins, else the tag's owner
	awk '{ for (i=2;i<=NF;i++) print $i, $1 }' /tmp/ec-rows.$$ | sort > /tmp/ec-cg-exp.$$
	awk '$2 != "rows" && $2 != "-" { print $2, $1 }' /tmp/ec-caps.$$ | sort -k1,1 > /tmp/ec-cg-tag.$$
	sort -k2,2 /tmp/ec-isa.$$ > /tmp/ec-isa-bytag.$$
	join -1 2 -2 1 -o 1.1,2.2 /tmp/ec-isa-bytag.$$ /tmp/ec-cg-tag.$$ | sort > /tmp/ec-cg-bytag.$$
	{ cat /tmp/ec-cg-exp.$$
	  awk 'NR==FNR{o[$1];next} !($1 in o)' /tmp/ec-cg-exp.$$ /tmp/ec-cg-bytag.$$
	} | sort -u > /tmp/ec-cg.$$

	: > /tmp/ec-derived.$$
	find lib apps -name '*.x' -type f | sort | while IFS= read -r f; do
		grep -hoE "\(prim-ref [^)]*\)[^)]*\)|\(prim-ref '[a-z0-9!?*/%<>=+-]+ '[^ )]+\)" "$f" 2>/dev/null \
		 | sed -E "s/\(lit ([^)]*)\)/\1/g; s/'//g; s/\(prim-ref //; s/\)+$//" \
		 | awk '{print $1"/"$2}' | sort -u > /tmp/ec-uf.$$
		g=""
		[ -s /tmp/ec-uf.$$ ] && g=$(join /tmp/ec-cg.$$ /tmp/ec-uf.$$ 2>/dev/null | awk '{print $2}' || true)
		# the bare syscall door is not a catalog coordinate, so it is matched by name
		if grep -qF "(syscall " "$f" 2>/dev/null; then g="$g
isa/syscall"; fi
		# `grep` finding nothing is the COMMON case here, not an error -- without
		# the guard `set -e` aborts the whole gate on the first core-only file.
		g=$(printf '%s\n' "$g" | grep -E "isa/(ffi-call|syscall|sys|gc)" | sort -u | tr '\n' ' ' | sed 's/ $//' || true)
		# `if`, not `[ ... ] && ...`: a core-only file makes the test the loop's
		# last command, and a false test would fail the whole pipeline under set -e.
		if [ -n "$g" ]; then echo "$f $g" >> /tmp/ec-derived.$$; fi
	done
	awk '/^  \(needs /{ l=$0; sub(/;.*/,"",l); gsub(/[()]/,"",l); gsub(/"/,"",l); $0=l
	                    printf "%s", $2; for(i=3;i<=NF;i++) printf " %s", $i; print "" }' "$REQ" \
	  | sort > /tmp/ec-req-man.$$
	sort -o /tmp/ec-derived.$$ /tmp/ec-derived.$$

	# The declared profile must COVER every above-core capability the tree
	# reaches.  Under-declaring is the unsafe direction: it would let a project
	# pair with an engine that cannot load files the library actually uses.
	decl=$(awk '/^  \(profile /{ l=$0; gsub(/[()]/,"",l); $0=l; print $2 }' "$REQ")
	if [ -n "$decl" ]; then
		grep "^$decl " /tmp/ec-prof-raw.$$ | cut -d' ' -f2- | tr ' ' '\n' | grep -v '^$' > /tmp/ec-decl-atoms.$$ || true
		# Expand to a FIXPOINT, then drop the profile names themselves: posix
		# names gc which names core, so one pass leaves two profile names sitting
		# in the atom set and every later membership test asks whether the engine
		# "provides core", which nothing does.
		while :; do
			expanded=0
			: > /tmp/ec-decl-next.$$
			while read -r a; do
				if grep -q "^$a " /tmp/ec-prof-raw.$$; then
					grep "^$a " /tmp/ec-prof-raw.$$ | cut -d' ' -f2- | tr ' ' '\n' | grep -v '^$' >> /tmp/ec-decl-next.$$
					expanded=1
				else
					echo "$a" >> /tmp/ec-decl-next.$$
				fi
			done < /tmp/ec-decl-atoms.$$
			sort -u -o /tmp/ec-decl-next.$$ /tmp/ec-decl-next.$$
			mv /tmp/ec-decl-next.$$ /tmp/ec-decl-atoms.$$
			[ "$expanded" = 0 ] && break
		done
		awk '{for(i=2;i<=NF;i++) print $i}' /tmp/ec-derived.$$ | sort -u > /tmp/ec-need.$$
		while read -r g; do
			grep -q "^$g$" /tmp/ec-decl-atoms.$$ || note "PROFILE: requires.x declares $decl, which does not include $g -- but the tree reaches it"
		done < /tmp/ec-need.$$
	fi
	if ! diff -u /tmp/ec-req-man.$$ /tmp/ec-derived.$$ > /tmp/ec-req-diff.$$ 2>&1; then
		echo "  DERIVED: requires.x disagrees with the tree (-manifest +derived):"
		grep '^[-+][^-+]' /tmp/ec-req-diff.$$ | sed 's/^/    /'
		fail=1
	fi
fi

# --- 7: the engine's declaration is current, and SATISFIES us ----------------
# This is what the whole vocabulary is for.  Two checks, and they are different
# questions: is x-engine.xon still what the generator would produce (a stale
# declaration is a lie with a timestamp), and does what it declares COVER what
# this library needs (the satisfaction test that replaces the old isa-digest
# equality compare -- superset, so a richer engine is never refused).
XON="$ENGINE_DIR/x-engine.xon"
if [ ! -f "$XON" ]; then
	# SILENCE IS NOT A PASS.  Without a declaration there is nothing to satisfy,
	# and skipping quietly reported an engine as fine when the gate had not looked
	# at it -- the vacuous-pass shape, in the gate that answers the resolver's
	# question.  Unknown is not wrong, but it has to say so.
	# ...and it has to FAIL, not merely say so.  The message alone was still a
	# vacuous pass: this gate answers "can this engine run the library?", it
	# exited 0 for an engine it had not looked at, and `make test` went green.
	# An engine with no declaration cannot be paired with anything -- that is a
	# refusal, and an easily fixed one.
	note "no declaration at $XON -- nothing to satisfy"
	echo "    (generate one: sh tools/contract/gen-engine-xon.sh $ENGINE_DIR)"
fi
if [ -f "$XON" ]; then
	if ! sh tools/contract/gen-engine-xon.sh "$ENGINE_DIR" > /tmp/ec-xon-gen.$$ 2>/tmp/ec-xon-err.$$; then
		note "GENERATOR: gen-engine-xon.sh failed against $ENGINE_DIR:"
		sed 's/^/    /' /tmp/ec-xon-err.$$
	elif ! diff -u "$XON" /tmp/ec-xon-gen.$$ > /tmp/ec-xon-diff.$$ 2>&1; then
		note "STALE: $XON is not what the generator produces (-committed +generated):"
		grep '^[-+][^-+]' /tmp/ec-xon-diff.$$ | sed 's/^/    /'
	fi

	# satisfaction: every atom the declared profile needs must be provided
	awk '/^\(provides /{ l=$0; gsub(/[()]/,"",l); $0=l; print $2 }' "$XON" | sort -u > /tmp/ec-xon-prov.$$
	if [ -s /tmp/ec-decl-atoms.$$ ]; then
		miss=""
		while read -r a; do
			grep -q "^$a$" /tmp/ec-xon-prov.$$ || miss="$miss $a"
		done < /tmp/ec-decl-atoms.$$
		if [ -n "$miss" ]; then
			note "SATISFACTION: $ENGINE_DIR does not provide what requires.x needs:$miss"
		else
			echo "  satisfaction: $(engine_name) provides everything requires.x needs."
		fi
	fi
fi

# --- 8: parameter VALUES are in the vocabulary too ---------------------------
# The parameter NAMES were closed and their values were not, so `os` accepted any
# word at all.  That is not a hypothetical: the spellings darwin/linux/bsd and
# arm64/x86-64/i386 were real and enforced, but only inside ONE ENGINE'S build
# script (gen-build-params.sh), while the conformance suite compared %param-os
# against those same literals.  A second engine stamping its own toolchain's
# names -- Rust says `macos` and `aarch64` for the same machines -- reports true
# facts in a vocabulary nothing can read, and every comparison against a literal
# fails silently.  The vocabulary belongs to the language, so it is checked here.
awk '/^\(def %feature-parameters/{f=1;next} /^\)\)\)/{f=0}
     f && /^  \(/ { l=$0; sub(/;.*/,"",l); gsub(/[()]/,"",l); $0=l
                    if (NF >= 2) print }' "$FEAT" > /tmp/ec-pvals.$$

# A parameter with no declared values is OPEN and accepts anything; `unknown` is
# always legal and means the build could not say.
param_legal() {
	_row=$(awk -v k="$1" '$1 == k { print; exit }' /tmp/ec-pvals.$$)
	[ -n "$_row" ] || return 0
	[ "$2" = "unknown" ] && return 0
	printf '%s\n' "$_row" | cut -d' ' -f2- | tr ' ' '\n' | grep -qx -- "$2"
}

# Every value a constraint binds must be spellable.  constraints.x is committed,
# so this half is checkable in any tree, built or not.
if [ -f "$CONS" ]; then
	sed -n 's/^  (constraint "[^"]*" \([a-z-]*\) = \([^)]*\)).*/\1 \2/p' "$CONS" \
	| while read -r _k _v; do
		if ! param_legal "$_k" "$_v"; then
			echo "  PARAM-VALUE: constraints.x binds $_k = $_v, which is not in the"
			echo "    vocabulary.  Add it to %feature-parameters or fix the row."
			echo "FAILVALUE" >> /tmp/ec-pvfail.$$
		fi
	done
fi

# And every value an engine STAMPS, when there is a stamp to read.  Unlike
# x-engine.xon this file is a build output -- the C engine gitignores it -- so a
# source tree that has never been built legitimately has none.  Absence is
# reported rather than passed over, but it is not a failure: nothing is being
# claimed that could be wrong.
STAMP="$ENGINE_DIR/x-engine-build.xon"
if [ -f "$STAMP" ]; then
	sed -n 's/^(param \([a-z-]*\) \([^)"]*\))[[:space:]]*$/\1 \2/p' "$STAMP" \
	| while read -r _k _v; do
		if ! param_legal "$_k" "$_v"; then
			echo "  PARAM-VALUE: $STAMP reports $_k = $_v, which is not in the"
			echo "    vocabulary.  x-lang compares these against literals, so a"
			echo "    spelling only this engine knows reads as a different machine."
			echo "FAILVALUE" >> /tmp/ec-pvfail.$$
		fi
	done
else
	echo "  no build stamp at $STAMP -- parameter values unchecked (not built yet)"
fi
# The loops above run in subshells under `|`, so `fail=1` inside them would be
# lost.  A marker file is how the verdict gets back out.
if [ -f /tmp/ec-pvfail.$$ ]; then fail=1; rm -f /tmp/ec-pvfail.$$; fi

if [ "$fail" -ne 0 ]; then
	echo "FAIL: the vocabulary and the engine ISA disagree."
	exit 1
fi

ncap=$(wc -l < /tmp/ec-caps.$$ | tr -d ' ')
nisa=$(wc -l < /tmp/ec-isa.$$ | tr -d ' ')
nprof=$(wc -l < /tmp/ec-prof-raw.$$ | tr -d ' ')
echo "  $ncap capabilities partition $nisa ISA rows; $nprof profiles closed; parameters kept separate."
exit 0
