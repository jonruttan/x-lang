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
# THE PLATFORM SHIPS IT; BUNDLES DO NOT VENDOR IT.  The same ruling
# release-refs.sh already carries, and this file is the case that proves it was
# right: three bundles had a byte-identical copy differing only in the name in
# line 2, and a trap bug in it had to be fixed in all three on the same day.
#
# THE BUG THAT MOVED IT.  `trap 'rm -rf "$work"' EXIT INT TERM` ran the cleanup
# on a signal and then FELL THROUGH to the next line, which wrote into the
# directory it had just removed.  A killed suite reported
#
#     spec-gate.sh: 58: cannot create /tmp/tmp.XXXX/clean: Directory nonexistent
#
# naming neither the signal nor the suite -- and, reproduced outside CI, could
# exit 0, which is a killed suite reporting SUCCESS.  Three copies, three
# identical edits, and nothing to stop a fourth bundle vendoring the bug again.
#
# WHY THIS EXISTS AT ALL.  spec-runner.sh exits non-zero on any failure, which
# is right for a developer at a prompt and wrong for a gate: a bundle carrying
# honest, documented debt is then permanently unreleasable, and release.yml
# refuses to publish anything ever.  So the gate asks a better question than
# "did anything fail".  It asks whether what failed is what we said would fail.
#
# BY NAME, NOT BY COUNT.  A budget of "9 failures" is satisfied by fixing one
# and breaking another, which is the exact event a ratchet is for.  This
# compares the SET of failing test names, so a swap is caught.
#
# BOTH DIRECTIONS ARE RED.  A failure that is not recorded is a regression.  A
# recorded failure that now passes is a fix nobody wrote down, and leaving it
# listed would quietly re-authorise the failure later.  x-lang's
# percent-globals gate takes the same line, for the same reason.
#
# WHAT A BUNDLE MUST PROVIDE: tests/spec-runner.sh and, unless KNOWN_FAILURES
# says otherwise, tests/contract/known-failures.txt.  Every variable
# spec-runner.sh honours (X, X_BIN, SPEC_PATH, SPEC_BATCH, ...) is honoured
# here, because this runs that script rather than reimplementing it.
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

# THE HANDLER HAS TO EXIT, and not doing so is how a KILLED suite reported a
# filesystem error instead.
#
# This was `trap 'rm -rf "$work"' EXIT INT TERM`.  On a signal the handler ran,
# removed the work directory, and then FELL THROUGH to the next line -- which
# writes into the directory it had just removed.  A suite killed by an OOM, a
# runaway guard or a cancelled CI job surfaced as
#
#     spec-gate.sh: 58: cannot create /tmp/tmp.XXXX/clean: Directory nonexistent
#
# and exit 143, naming neither the signal nor the suite.  Worse, it defeats the
# "a suite that did not run is not a suite that passed" check below by never
# reaching it -- the one guard written specifically so a suite that never ran
# cannot be mistaken for a green one.
#
# So EXIT cleans up, and a signal cleans up, SAYS which signal, and re-raises
# itself with the trap cleared -- so the parent sees a death by signal rather
# than an ordinary status, which is what a CI runner reads to tell "cancelled"
# from "failed".
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
