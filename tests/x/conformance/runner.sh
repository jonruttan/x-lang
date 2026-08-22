#!/bin/sh
# runner.sh -- run x-lang's conformance suite against ANY engine.
#
#   Usage: sh tests/x/conformance/runner.sh [spec.md ...]
#   Env:   X_BIN         the engine binary        (default: ./x-bin)
#          X_ENGINE_DIR  the engine's root        (default: ext/x-engine-c)
#          PROFILE       which profile to run     (default: every one)
#
# CONFORMANCE ASKS: IS THIS A CORRECT x-lang EVALUATOR?  It is the language's
# definition of correct, which is why it lives here and not in an engine.  An
# implementation that owned this suite would become the arbiter of the contract
# every other implementation is judged against, and x-engine-rust's only recourse
# against a C quirk would be to reproduce it.
#
# NOT the same as two neighbouring things:
#   - the engine's tests/bare SMOKE harness asks "does THIS engine stand up",
#     and belongs to the engine.  This runner deliberately does not reuse it:
#     borrowing an engine's runner hands the arbiter role back through the door
#     the suite's location just closed.
#   - COMPLIANCE (tools/check/compliance.sh) asks "does this engine do what IT
#     CLAIMS", and is generated from the engine's own x-engine.xon.  Conformance
#     does not care what an engine claims.
#
# LOADS NOTHING.  Every other runner in tests/ cats a library onto stdin, so what
# it measures is the library's surface -- variadic `+` is lib/x/core/arithmetic.x
# sitting on a BINARY primitive, and testing it says nothing about the engine.
# Here each case is one engine process fed a short prelude and the case source.
#
# THE OBSERVATION CHANNEL IS `error`.  A bare engine has no printer -- display and
# write are x-lang -- and it does NOT echo results either (verified: a plain
# `(+ 1 2)` prints nothing at all).  So a case signals through `error`, whose text
# the engine's read-eval loop prints as `*** ERROR: <text>`.  The prelude below
# defines %ok for that, so a case reads as an assertion rather than as plumbing.
# A CRASH prints neither "ok" nor a reason, so a wrong answer and a dead engine
# stay distinguishable.
#
# CWD IS THE ENGINE'S ROOT, because the catalog prelude includes the engine's own
# committed base paths, and `include` resolves against the current directory.
# Under decision L1 every engine ships those descriptors, so this works for any
# engine, not just the C one.
set -e

ROOT="$(cd "$(dirname "$0")/../../.." && pwd)"
cd "$ROOT"
SUITE="$ROOT/tests/x/conformance"
ENGINE_DIR="${X_ENGINE_DIR:-$ROOT/ext/x-engine-c}"
ENGINE="${X_BIN:-$ROOT/x-bin}"
LIMIT="${X_ALLOC_LIMIT_OBJS:-2000000}"

[ -x "$ENGINE" ] || { echo "conformance: no engine at $ENGINE (set X_BIN)" >&2; exit 2; }
[ -d "$ENGINE_DIR" ] || { echo "conformance: no engine dir at $ENGINE_DIR (set X_ENGINE_DIR)" >&2; exit 2; }

if [ $# -gt 0 ]; then
	SPECS="$*"
elif [ -n "${PROFILE:-}" ]; then
	[ -d "$SUITE/$PROFILE" ] || { echo "conformance: no such profile: $PROFILE" >&2; exit 2; }
	SPECS=$(find "$SUITE/$PROFILE" -name '*.spec.md' | sort)
else
	SPECS=$(find "$SUITE" -name '*.spec.md' | sort)
fi
[ -n "$SPECS" ] || { echo "conformance: no specs found" >&2; exit 2; }

WORK="${TMPDIR:-/tmp}/conformance.$$"
mkdir -p "$WORK"
trap 'rm -rf "$WORK"' EXIT INT TERM

# The prelude every case gets.  Kept to the BARE-CALLABLE set on purpose -- fn,
# match, def, error, first, rest, eq?, +, include -- because anything richer would
# be testing the prelude rather than the engine.  %ok is the assertion; %coord is
# the catalog door (prim-ref does not exist bare: it is x-level, and the committed
# base paths reach the prims CELL, whose first is the catalog itself).
cat > "$WORK/prelude" <<'PRE'
(alloc-limit! LIMIT)
(def %ok (fn (self c) (match (c (error "ok")) (#t (error "no")))))
(include "tools/contract/base-paths.x")
(def %assoc (fn (self k l)
  (match ((eq? l ()) ())
         ((eq? (first (first l)) k) (first l))
         (#t (self k (rest l))))))
(def %walk (fn (self steps o)
  (match ((eq? steps ()) o)
         ((eq? (first steps) (lit f)) (self (rest steps) (first o)))
         (#t (self (rest steps) (rest o))))))
(def %cat (first (%walk (rest (rest (%assoc (lit prims) %base-paths))) (%base))))
(def %coord (fn (self ns m)
  (match ((eq? (%assoc ns %cat) ()) ())
         (#t (rest (%assoc m (rest (%assoc ns %cat))))))))
PRE
sed "s/LIMIT/$LIMIT/" "$WORK/prelude" > "$WORK/prelude.x"

RED=$(printf "\033[1;31m"); GREEN=$(printf "\033[1;32m")
BLUE=$(printf "\033[1;34m"); DIM=$(printf "\033[2m"); OFF=$(printf "\033[0m")
total=0; failed=0

for spec in $SPECS; do
	[ -f "$spec" ] || { echo "conformance: no such spec: $spec" >&2; exit 2; }
	printf "%s%s%s\n" "$BLUE" "${spec#$SUITE/}" "$OFF"

	rm -rf "$WORK/cases"; mkdir -p "$WORK/cases"
	# Same shape as every other spec file here: ### name, a fenced block, ---,
	# then the expected value indented.  A `covers:` line is metadata for the
	# coverage gate and is skipped by the splitter.
	awk -v out="$WORK/cases" '
		/^### / { n++; name = substr($0, 5); state = "pre"
		          printf "%s", name > (out "/" n ".name"); next }
		!n { next }
		/^covers:/ { next }
		/^```/ { if (state == "pre") { state = "code"; next }
		         if (state == "code") { state = "aftercode"; next } }
		state == "code" { print > (out "/" n ".code"); next }
		/^---[ \t]*$/ && state == "aftercode" { state = "want"; next }
		state == "want" && $0 ~ /[^ \t]/ {
			line = $0; sub(/^[ \t]+/, "", line)
			print line > (out "/" n ".want"); state = "done"; next }
	' "$spec"

	i=1
	while [ -f "$WORK/cases/$i.code" ]; do
		name=$(cat "$WORK/cases/$i.name")
		want=""
		[ -f "$WORK/cases/$i.want" ] && want=$(cat "$WORK/cases/$i.want")

		got=$( cd "$ENGINE_DIR" && { cat "$WORK/prelude.x"; cat "$WORK/cases/$i.code"; } \
			| "$ENGINE" 2>&1 | sed "/^[ \t]*$/d" | tail -1 )

		total=$((total + 1))
		if [ "$got" = "$want" ]; then
			printf "%s.%s" "$GREEN" "$OFF"
		else
			failed=$((failed + 1))
			# An empty result is the engine DYING, not answering -- name it, so a
			# crash is never read as a wrong answer.
			shown="$got"
			[ -z "$got" ] && shown="(no output -- the engine produced nothing; a crash)"
			printf "\n%sFAIL: %s\n  expected: %s\n  got:      %s%s\n" \
				"$RED" "$name" "$want" "$shown" "$OFF"
		fi
		i=$((i + 1))
	done
	printf "\n"
done

printf "%sengine: %s%s\n" "$DIM" "$ENGINE" "$OFF"
if [ "$failed" -gt 0 ]; then
	printf "%s%d conformance checks, %d failed%s\n" "$RED" "$total" "$failed" "$OFF"
	exit 1
fi
printf "%s%d conformance checks, 0 failed%s\n" "$GREEN" "$total" "$OFF"
