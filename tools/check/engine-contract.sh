#!/bin/sh
# engine-contract.sh -- hold the engine-contract vocabulary against the ISA.
#
# tools/contract/features.x is the closed vocabulary an engine's x-engine.xon and
# x-lang's requires.x both quote from.  A vocabulary that drifts from the surface
# it describes is worse than none: it reads as authority while naming nothing.
# This gate keeps the two in step.
#
# What it checks
#   1. total      every isa.x row lands in exactly one capability group -- by its
#                 tag, or by explicit membership for a split tag.  A new C row
#                 cannot appear without being classified in the same commit.
#   2. disjoint   no coordinate is claimed by two groups.
#   3. grounded   every explicitly-listed coordinate actually exists in isa.x, so
#                 a group cannot outlive the rows it names.
#   4. closed     every atom named in a profile resolves -- to a capability, or to
#                 a profile defined before it.  No forward or dangling references.
#   5. separate   no profile names a parameter.  Width, arch and OS are values an
#                 engine reports, not capabilities it has; `word-size = 8` in a
#                 requirement would lock out the 32-bit Pi.  Per-module needs go
#                 to tools/contract/constraints.x instead.
#
# Checks 1 and 2 carry the weight, because the groups are hand-drawn.  The `ffi`
# tag carries eleven rows that split three ways: the pointer casts (mandatory --
# boot reads header words through them), the foreign door (dlopen/dlsym/
# ptr-call), and the raw syscall door.  Treating the tag as one group makes
# dlopen mandatory for every engine, a sandboxed one included, putting that
# target out of reach on paper while it works in fact.  So the partition is
# machine-checked against isa.x rather than trusted.
#
# The checks that hold the library -- 1 to 6, and the constraints.x half of 8 --
# run in x: tools/check/engine-contract.x reads the committed files as forms, on
# this tree's built engine.  The checks that judge the candidate engine -- 7, and
# the build-stamp half of 8 -- stay here, so an engine that cannot run x is still
# refused by name.
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

# Two engines, two questions.  The reference surface is the language's own view
# of what instructions exist; the candidate is whatever engine is being judged.
#
#   partition + derived requires  ->  reference.  "What does lib/ need?" is a
#       property of lib/.  Deriving it through a candidate's coordinate map lets
#       a reduced engine appear to shrink the library's requirements: pointed at
#       an engine with no collector, requires.x reads as stale for no longer
#       needing one.  The library needs exactly what it needs.
#   satisfaction + staleness      ->  candidate.  "Can this engine run it?"
REFERENCE_DIR="${X_REFERENCE_DIR:-engine}"
ISA="$REFERENCE_DIR/tools/contract/isa.x"
REQ="tools/contract/requires.x"
CONS="tools/contract/constraints.x"
[ -f "$FEAT" ] || { echo "engine-contract: no vocabulary at $FEAT" >&2; exit 2; }
# The ISA is the ENGINE's file.  A missing one means no engine was acquired,
# not a passing check -- say so rather than reporting ok over nothing, which is
# the vacuous-pass shape the split turned up four times.
[ -f "$ISA" ] || { echo "engine-contract: no reference ISA at $ISA (run: make engine)" >&2; exit 2; }

fail=0
note() { echo "  $1"; fail=1; }

CACHE="build/engine-contract.lib"
trap 'rm -f /tmp/ec-*.$$ "$CACHE.$$"' EXIT INT TERM

echo "engine-contract:"

# --- 1-6, and the values constraints.x binds: the library, in x --------------
# The files the library half reads ride argv, the sources one path to a word:
# the shell enumerates and x reads (tools/README.md).
set -f
IFS='
'
set -- "$FEAT" "$ISA" "$REQ" "$CONS" $(find lib apps -name '*.x' -type f | sort)

# The library half's answer depends only on its arguments, the files they name,
# and the program, wrapper and engine that read them, so a clean answer is kept
# in build/ under a digest of all of those, the way check-boot-order keeps its
# verdict (#325).  check-second-engine asks this gate about three more engines,
# and the library's answer is the same each time.  An answer with findings, or
# from a run that did not finish, is not kept.  The candidate engine is not an
# input.  A file of the candidate's handed to the library half would be digested
# with the rest, so check-second-engine still sees a derivation it perturbed.
if command -v sha256sum >/dev/null 2>&1; then
	digest() { sha256sum "$@"; }
else
	digest() { shasum -a 256 "$@"; }
fi
inputs=$(for f in tools/check/engine-contract.sh tools/check/engine-contract.x x.sh "${X_BIN:-x-bin}" \
		engine/tools/contract/base-paths.x engine/tools/contract/obj-layout.x "$@"; do
	if [ -f "$f" ]; then printf '%s\n' "$f"; fi
done)
key=$({ printf '%s\n' "$@"; digest $inputs; } | digest | cut -d' ' -f1)
unset IFS
set +f

xrc=0
fresh=1
if [ -n "$key" ] && [ -f "$CACHE" ] && [ "$(head -n 1 "$CACHE")" = "$key" ] \
	&& [ "$(tail -n 1 "$CACHE")" = "@@end" ]; then
	tail -n +2 "$CACHE" > /tmp/ec-lib.$$
	: > /tmp/ec-lib-err.$$
	fresh=0
else
	sh x.sh --no-pin -q -f tools/check/engine-contract.x -- "$@" \
		> /tmp/ec-lib.$$ 2> /tmp/ec-lib-err.$$ || xrc=$?
fi

# Each section becomes /tmp/ec-NAME.$$.  They carry the findings and the data
# checks 7 and 8 read, so a run that fails, or stops before its last section,
# fails the gate rather than leaving those checks nothing to judge.
lib_failed() {
	note "LIBRARY: tools/check/engine-contract.x $1"
	sed 's/^/    /' /tmp/ec-lib-err.$$
}
if [ "$xrc" -ne 0 ]; then
	lib_failed "exited $xrc"
elif [ "$(tail -n 1 /tmp/ec-lib.$$)" != "@@end" ]; then
	lib_failed "stopped before its last section"
else
	awk -v stem="/tmp/ec-" -v pid=".$$" '
		/^@@/   { f = stem substr($0, 3) pid; printf "" > f; next }
		f != "" { print > f }' /tmp/ec-lib.$$
	for s in notes decl-atoms cons-notes pvals counts; do
		[ -f "/tmp/ec-$s.$$" ] || note "LIBRARY: tools/check/engine-contract.x printed no $s section"
	done
fi
if [ -s /tmp/ec-notes.$$ ]; then
	cat /tmp/ec-notes.$$
	fail=1
fi
if [ "$fresh" = 1 ] && [ -n "$key" ] && [ "$fail" -eq 0 ] && [ ! -s /tmp/ec-cons-notes.$$ ] \
	&& mkdir -p build; then
	{ printf '%s\n' "$key"; cat /tmp/ec-lib.$$; } > "$CACHE.$$" && mv -f "$CACHE.$$" "$CACHE" || true
fi

# --- 7: the engine's declaration is current, and SATISFIES us ----------------
# This is what the whole vocabulary is for.  Two checks, and they are different
# questions: is x-engine.xon still what the generator would produce (a stale
# declaration is a lie with a timestamp), and does what it declares COVER what
# this library needs (the satisfaction test that replaces the old isa-digest
# equality compare -- superset, so a richer engine is never refused).
XON="$ENGINE_DIR/x-engine.xon"
if [ ! -f "$XON" ]; then
	# Silence is not a pass.  Without a declaration there is nothing to satisfy,
	# and an engine the gate has not looked at must not report as fine.  It has
	# to fail rather than merely say so: this gate answers "can this engine run
	# the library?", and exiting 0 for an unexamined engine takes `make test`
	# green with it.  An engine with no declaration cannot be paired with
	# anything, so it is refused.
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

	# satisfaction: every atom the declared profile needs must be provided.
	# engine-contract.x expanded the profile into /tmp/ec-decl-atoms.$$.
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

# Every value a constraint binds must be spellable.  constraints.x is committed,
# so this half needs no build stamp; engine-contract.x checked it above.
if [ -s /tmp/ec-cons-notes.$$ ]; then
	cat /tmp/ec-cons-notes.$$
	fail=1
fi

# A parameter with no declared values is OPEN and accepts anything; `unknown` is
# always legal and means the build could not say.  /tmp/ec-pvals.$$ holds a line
# for each parameter that declares values: its name, then the values.
param_legal() {
	_row=$(awk -v k="$1" '$1 == k { print; exit }' /tmp/ec-pvals.$$)
	[ -n "$_row" ] || return 0
	[ "$2" = "unknown" ] && return 0
	printf '%s\n' "$_row" | cut -d' ' -f2- | tr ' ' '\n' | grep -qx -- "$2"
}

# And every value an engine STAMPS, when there is a stamp to read.  Unlike
# x-engine.xon this file is a build output -- the C engine gitignores it -- so a
# source tree that has never been built legitimately has none.  Absence is
# reported rather than passed over, but it is not a failure: nothing is being
# claimed that could be wrong.  When the library half printed no parameter rows
# the stamp cannot be judged, and the gate has already failed.
STAMP="$ENGINE_DIR/x-engine-build.xon"
if [ ! -f "$STAMP" ]; then
	echo "  no build stamp at $STAMP -- parameter values unchecked (not built yet)"
elif [ -f /tmp/ec-pvals.$$ ]; then
	sed -n 's/^(param \([a-z-]*\) \([^)"]*\))[[:space:]]*$/\1 \2/p' "$STAMP" \
	| while read -r _k _v; do
		if ! param_legal "$_k" "$_v"; then
			echo "  PARAM-VALUE: $STAMP reports $_k = $_v, which is not in the"
			echo "    vocabulary.  x-lang compares these against literals, so a"
			echo "    spelling only this engine knows reads as a different machine."
			echo "FAILVALUE" >> /tmp/ec-pvfail.$$
		fi
	done
fi
# The loop above runs in a subshell under `|`, so `fail=1` inside it would be
# lost.  A marker file is how the verdict gets back out.
if [ -f /tmp/ec-pvfail.$$ ]; then fail=1; rm -f /tmp/ec-pvfail.$$; fi

if [ "$fail" -ne 0 ]; then
	echo "FAIL: the vocabulary and the engine ISA disagree."
	exit 1
fi

read -r ncap nisa nprof < /tmp/ec-counts.$$
echo "  $ncap capabilities partition $nisa ISA rows; $nprof profiles closed; parameters kept separate."
exit 0
