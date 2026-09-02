#!/bin/sh
# wrapper.sh -- x.sh's own entry points still evaluate what they are handed.
#
# WHY THIS GATE EXISTS.  The spec suite cannot see any of this.  Every spec
# runs `cat $LANG_LIB $tmpfile | $X_BIN` -- the runner talks to the ENGINE,
# deliberately, so a spec measures the language and not the shell around it.
# The consequence is that x.sh's argument surface had no test of any kind,
# and it showed: piping a program in (`echo '(write 1)' | sh x.sh`) printed a
# prompt, evaluated NOTHING, and exited 0.  Not a crash, not a diagnostic --
# a silent, successful no-op, in the most obvious way anyone would first try
# to use the thing.  It survived because nothing in the tree pipes into the
# wrapper, so nothing noticed.
#
# So the rule this file holds is narrow and blunt: THE WAYS IN MUST EVALUATE
# WHAT THEY ARE GIVEN, AND SAY SO IN THE EXIT STATUS.  A route that quietly
# does nothing is the failure mode being gated, which is why every case
# asserts on OUTPUT rather than on status alone -- exit 0 was the lie.
#
# Cheap on purpose (one engine boot per case, helium, no tower) so it can sit
# in gates-fast.  Every capture carries `|| true`: set -e does not spare a
# command substitution, and a wrapper that DIED would otherwise abort this
# script silently -- a gate that says nothing when the thing it guards is
# broken is worse than no gate.
set -e

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
PROJECT_DIR="$(cd "$SCRIPT_DIR/../.." && pwd)"
cd "$PROJECT_DIR" || exit 1

TMP=$(mktemp -d)
trap 'rm -rf "$TMP"' EXIT INT TERM

fails=0

# want NAME EXPECTED ACTUAL
want() {
	if [ "$2" = "$3" ]; then
		printf '  %s: ok\n' "$1"
	else
		printf 'wrapper: %s -- expected [%s], got [%s]\n' "$1" "$2" "$3" >&2
		fails=$((fails + 1))
	fi
}

got=$(sh x.sh -q -c '(write (+ 1 2))' 2>/dev/null || true)
want "-c evaluates an expression" "3" "$got"

# Repeatable and ORDERED: the second expression must see the first's def, so
# this fails both if -c stops after one and if the two arrive out of order.
got=$(sh x.sh -q -c '(def n 7)' -c '(write (* n 6))' 2>/dev/null || true)
want "-c is repeatable, in order" "42" "$got"

got=$(printf '(write (+ 1 2))\n' | sh x.sh -q 2>/dev/null || true)
want "stdin is program text" "3" "$got"

printf '(write "from-file")\n' > "$TMP/p.x"
got=$(sh x.sh -q -f "$TMP/p.x" 2>/dev/null || true)
want "-f evaluates a file" '"from-file"' "$got"

# -F loads and continues, so its file must be evaluated BEFORE the -c
# expressions that follow; the concatenation is the ordering assertion.
got=$(sh x.sh -q -F "$TMP/p.x" -c '(write "then-eval")' 2>/dev/null || true)
want "-F runs before -c" '"from-file""then-eval"' "$got"

# The status half of the rule.  A raise must reach the shell as a failure and
# the message must reach stderr, or a script cannot tell a broken run from an
# empty one -- which is exactly what the silent no-op looked like.
if sh x.sh -q -c '(no-such-binding)' >/dev/null 2>&1; then
	printf 'wrapper: a raised error exited 0\n' >&2
	fails=$((fails + 1))
else
	printf '  a raised error exits non-zero: ok\n'
fi

# `|| true`: this command is SUPPOSED to fail, and set -e does not spare a
# command substitution.
err=$(sh x.sh -q -c '(no-such-binding)' 2>&1 >/dev/null || true)
case "$err" in
	*no-such-binding*) printf '  the error reaches stderr: ok\n' ;;
	*)
		printf 'wrapper: error text not on stderr, got [%s]\n' "$err" >&2
		fails=$((fails + 1))
		;;
esac

# The dialect flag still selects: helium has no tower, xenon does.  One case,
# because a wrong dialect is the other way a route silently answers wrong.
got=$(sh x.sh -q -l xe -c '(write (+ 1/3 1/6))' 2>/dev/null || true)
want "-l selects the dialect" "1/2" "$got"

if [ "$fails" -gt 0 ]; then
	printf 'wrapper: %d failure(s).\n' "$fails" >&2
	exit 1
fi
printf 'wrapper: every entry point evaluates what it is handed.\n'
