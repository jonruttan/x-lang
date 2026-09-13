#!/bin/sh
# # x-lang -- the lang kit
#
# ## tools/lang-kit/spec-gate.sh -- the suite, judged against recorded failures
#
# @description Runs a bundle's spec suite and compares its failures to
#   tests/contract/known-failures.txt.  Green when they match exactly.
# @author [Jon Ruttan](jonruttan@gmail.com)
# @copyright 2026 Jon Ruttan
# @license MIT No Attribution (MIT-0)
#
#     ., .,
#     {O,O}
#     (   )
#      " "
#
# The platform ships this gate; a bundle runs it rather than vendoring a copy.
#
# spec-runner.sh exits non-zero on any failure, which is right at a prompt and
# wrong for a release gate: a bundle carrying documented debt would then be
# permanently unreleasable.  This asks instead whether what failed is what the
# contract records.
#
# The comparison is by name, over the set of failing tests, rather than by
# count -- a budget of "9 failures" is satisfied by fixing one and breaking
# another.
#
# Both directions are red.  A failure that is not recorded is a regression; a
# recorded failure that now passes must be struck from the list, or it
# re-authorises that failure later.  x-lang's percent-globals gate is the same
# shape.
#
# A bundle provides tests/spec-runner.sh and, unless KNOWN_FAILURES says
# otherwise, tests/contract/known-failures.txt.  Every variable spec-runner.sh
# honours (X, X_BIN, SPEC_PATH, SPEC_BATCH, ...) is honoured here, because this
# runs that script rather than reimplementing it.
#
# BUNDLE is the bundle root; the shim that sources this sets it.
set -e

BUNDLE="${BUNDLE:-$(pwd)}"
CONTRACT="${KNOWN_FAILURES:-$BUNDLE/tests/contract/known-failures.txt}"

[ -f "$CONTRACT" ] || {
	echo "spec-gate: no contract at $CONTRACT" >&2
	exit 2
}

work=$(mktemp -d)

# A signal handler must not fall through: cleanup removes the work directory,
# and the lines below write into it.  Falling through also skips the
# "did not run" check further down, which is what keeps a suite that never ran
# from reading as a green one.
#
# So EXIT cleans up, and a signal cleans up, names the signal, and re-raises it
# with the trap cleared.  The parent then sees a death by signal rather than an
# ordinary status, which is how a CI runner tells "cancelled" from "failed".
cleanup() { rm -rf "$work"; }
trap cleanup EXIT
trap 'cleanup; echo "spec-gate: killed by SIGINT -- the suite did not finish" >&2; trap - INT; kill -INT $$' INT
trap 'cleanup; echo "spec-gate: killed by SIGTERM -- the suite did not finish" >&2; trap - TERM; kill -TERM $$' TERM

# The runner exits non-zero on failures, which is the whole reason this wrapper
# exists -- so its status is captured rather than allowed to end the script.
# `set -e` would otherwise kill us before we could read the output.
status=0
sh "$BUNDLE/tests/spec-runner.sh" > "$work/out" 2>&1 || status=$?
sed 's/\x1b\[[0-9;]*m//g' "$work/out" > "$work/clean"
cat "$work/clean"

# A suite that did not run is not a suite that passed.  Without this a crash
# before the first spec produces no FAIL lines, matches an empty diff against a
# contract listing none, and reports green -- the worst possible answer.
totals=$(sed -n 's/^\([0-9][0-9]*\) tests,.*/\1/p' "$work/clean" | tail -1)
if [ -z "$totals" ] || [ "$totals" = 0 ]; then
	echo "" >&2
	echo "spec-gate: FAIL -- the suite reported no totals line, so it did not run" >&2
	echo "  runner exited $status; its output is above" >&2
	exit 1
fi

sed -n 's/^FAIL: //p' "$work/clean" | sort -u > "$work/actual"
grep -v '^[[:space:]]*#' "$CONTRACT" | grep -v '^[[:space:]]*$' | sort -u > "$work/known"

comm -23 "$work/actual" "$work/known" > "$work/new"
comm -13 "$work/actual" "$work/known" > "$work/fixed"

echo ""
echo "spec-gate: $totals tests, $(wc -l < "$work/actual" | tr -d ' ') failed, $(wc -l < "$work/known" | tr -d ' ') recorded"

rc=0
if [ -s "$work/new" ]; then
	echo "" >&2
	echo "spec-gate: REGRESSION -- these failed and are not recorded:" >&2
	sed 's/^/    /' "$work/new" >&2
	rc=1
fi

if [ -s "$work/fixed" ]; then
	echo "" >&2
	echo "spec-gate: these are recorded as failing but PASS now:" >&2
	sed 's/^/    /' "$work/fixed" >&2
	echo "  remove them from $(basename "$CONTRACT") -- the list may only shrink," >&2
	echo "  and a fix left unrecorded re-authorises the failure later." >&2
	rc=1
fi

[ "$rc" = 0 ] || exit 1

echo "spec-gate: ok -- the failures are exactly the recorded ones"
