#!/bin/sh
# # Computational Expressions in C
#
# ## tools/check/bundles.sh -- run every lang bundle against THIS working tree
#
# @description Reads tools/contract/bundles.x, runs each bundle's spec suite
#   against the checkout, and fails if any of them got worse.
# @author [Jon Ruttan](jonruttan@gmail.com)
# @copyright 2026 Jon Ruttan
# @license MIT No Attribution (MIT-0)
#
#     ., .,
#     {O,O}
#     (   )
#      " "
#
# A companion to check-seam rather than a replacement.  Seam asks whether the
# platform still provides the names a lang is promised -- eight seconds, fast
# pass, and catches a rename.  This asks whether the langs still run, which
# takes minutes and catches the rest.  Deep pass.
#
# Presence is advisory, regression is strict.  A bundle lives in its own
# repository and this tree must build for someone who cloned nothing else, so a
# missing bundle is announced and skipped.  A bundle that is present and got
# worse is fatal.
#
# X_BUNDLE_DIR overrides where bundles are looked for.  BUNDLES='krn sweet' runs a
# subset.  BUNDLES_LOG_DIR keeps each suite's whole output as NAME.log there, so
# the failing tests can be named after the run.
#
# PARALLEL is not forced, and the runners default to serial here.  Several
# bundles are many spec files each booting a full tower, and the shared
# runner's header states the limit: "a per-process guard cannot fix memory
# exhaustion from many heavy specs loading in PARALLEL; for that lower
# PARALLEL_JOBS."  Under load whole batches are killed by the alloc ceiling and
# report no result, which the runner counts as failures -- so the same tree
# scores differently run to run.  Export PARALLEL to trade that back.
set -e

ROOT="$(cd "$(dirname "$0")/../.." && pwd)"
MANIFEST="$ROOT/tools/contract/bundles.x"

[ -f "$MANIFEST" ] || { echo "bundles: no $MANIFEST" >&2; exit 1; }

# Read the manifest the way every other one here is read: textually, by row.
DEFAULT_DIR="$(sed -n 's/^(bundles-dir "\([^"]*\)").*/\1/p' "$MANIFEST" | head -1)"
BUNDLES_DIR="${X_BUNDLE_DIR:-$ROOT/$DEFAULT_DIR}"

if [ ! -d "$BUNDLES_DIR" ]; then
	echo "bundles: SKIPPED -- no bundles at $BUNDLES_DIR"
	echo "  set X_BUNDLE_DIR to point at a directory of lang bundles"
	exit 0
fi

# The x under test is this tree's wrapper.  A bundle runner asks
# `x --share-dir` where the platform lives, and mode detection is cwd-based:
# from a bundle directory the x on PATH answers the install, so a suite run
# without this scores the last release rather than the working tree.
X_UNDER_TEST="$ROOT/x.sh"
[ -x "$X_UNDER_TEST" ] || { echo "bundles: no wrapper at $X_UNDER_TEST" >&2; exit 1; }

_fails=0
_skips=0
_ratchet=""

printf '%-8s %8s %8s %8s   %s\n' "LANG" "TESTS" "FAILED" "BUDGET" "VERDICT"

# One row per lang: NAME DIR TESTS FAILED
sed -n 's/^(bundle "\([^"]*\)"  *"\([^"]*\)"  *\([0-9]*\)  *\([0-9]*\)).*/\1 \2 \3 \4/p' "$MANIFEST" \
| while read -r name dir want_tests budget; do
	if [ -n "${BUNDLES:-}" ]; then
		case " $BUNDLES " in *" $name "*) ;; *) continue ;; esac
	fi

	D="$BUNDLES_DIR/$dir"
	if [ ! -f "$D/tests/spec-runner.sh" ]; then
		printf '%-8s %8s %8s %8s   %s\n' "$name" "-" "-" "$budget" "SKIPPED (not present)"
		echo "$name" >> "$ROOT/.bundles-skips.$$"
		continue
	fi
	# A directory with no bundle.xon is not a bundle to this platform: the
	# wrapper would not find it either.  Skipped like one that is not there.
	if [ ! -f "$D/bundle.xon" ]; then
		printf '%-8s %8s %8s %8s   %s\n' "$name" "-" "-" "$budget" "SKIPPED (no bundle.xon)"
		echo "$name" >> "$ROOT/.bundles-skips.$$"
		continue
	fi

	# Parsed in awk, for two reasons.  BSD sed does not interpret \033 in a
	# pattern, so an ANSI strip written that way matches nothing on macOS and
	# the coloured summary line never anchors.  And a greedy .* before a digit
	# class eats all but the last digit: "74 tests" captures 4 and "80 failed"
	# captures 0, so a bundle 80 specs in the red reads as green.
	# The suite runs inside the bundle's directory, so the log directory is
	# made absolute here, where it was named.
	log=/dev/null
	if [ -n "${BUNDLES_LOG_DIR:-}" ]; then
		mkdir -p "$BUNDLES_LOG_DIR"
		log="$(cd "$BUNDLES_LOG_DIR" && pwd)/$name.log"
	fi
	line="$(cd "$D" && X="$X_UNDER_TEST" sh tests/spec-runner.sh 2>&1 \
		| tee "$log" \
		| awk '{
			gsub(/\033\[[0-9;]*m/, "")
			if ($0 ~ /^[0-9]+ tests, [0-9]+ failed/) print $1 " " $3
		}' \
		| tail -1)"

	tests="${line% *}"
	failed="${line#* }"

	# No result is a failure, never a pass.  A suite whose harness died prints
	# no summary line at all, and a missing number treated as zero would make
	# a broken platform read as a green one.
	if [ -z "$line" ] || [ -z "$failed" ]; then
		printf '%-8s %8s %8s %8s   %s\n' "$name" "?" "?" "$budget" "FAIL (no result -- suite did not report)"
		echo "$name" >> "$ROOT/.bundles-fails.$$"
		continue
	fi

	verdict="ok"
	bad=0
	if [ "$failed" -gt "$budget" ]; then
		verdict="FAIL (+$((failed - budget)) over budget)"; bad=1
	elif [ "$failed" -lt "$budget" ]; then
		verdict="improved -- ratchet bundles.x to $failed"
	fi
	# A suite that shrank is compared against a number describing a bigger
	# run, so the budget no longer means what it said.  Loud, not fatal: a
	# bundle may reorganise its specs, and the fix is to re-record.
	if [ "$tests" -lt "$want_tests" ]; then
		verdict="$verdict; suite shrank $want_tests->$tests, re-record"
	fi

	printf '%-8s %8s %8s %8s   %s\n' "$name" "$tests" "$failed" "$budget" "$verdict"
	# if/fi, NOT `[ ... ] && echo`.  Under set -e a trailing test that is FALSE
	# is a non-zero last command, which kills this pipeline's subshell before
	# the summary below ever runs -- so a clean run of every lang exited 1 with
	# no verdict line.  The happy path is the one that trips it.
	if [ "$bad" = 1 ]; then echo "$name" >> "$ROOT/.bundles-fails.$$"; fi
done

# The loop above runs in a subshell (the pipe), so its counters do not survive
# it.  Files do.
if [ -f "$ROOT/.bundles-skips.$$" ]; then
	_skips="$(wc -l < "$ROOT/.bundles-skips.$$" | tr -d ' ')"
	rm -f "$ROOT/.bundles-skips.$$"
fi
if [ -f "$ROOT/.bundles-fails.$$" ]; then
	_fails="$(wc -l < "$ROOT/.bundles-fails.$$" | tr -d ' ')"
	rm -f "$ROOT/.bundles-fails.$$"
fi

echo
if [ "$_fails" -gt 0 ]; then
	echo "bundles: FAIL -- $_fails bundle(s) worse than tools/contract/bundles.x records"
	exit 1
fi
echo "bundles: ok ($_skips skipped as absent)"
