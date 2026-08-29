#!/bin/sh
# # Computational Expressions in C
#
# ## tools/check/langs.sh -- run every lang bundle against THIS working tree
#
# @description Reads tools/contract/langs.x, runs each bundle's spec suite
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
# THE COMPANION TO check-seam, NOT A REPLACEMENT.  Seam asks whether the
# platform still PROVIDES the names a lang is promised -- eight seconds, fast
# tier, catches a rename.  This asks whether the langs still RUN, which is
# minutes and catches everything else.  Deep tier.
#
# ADVISORY ABOUT PRESENCE, STRICT ABOUT REGRESSION.  A bundle lives in its own
# repository and this tree must build for someone who cloned nothing else, so a
# missing bundle is announced and skipped rather than fatal.  A bundle that is
# HERE and got worse is fatal.
#
# X_LANGS_DIR overrides where bundles are looked for.  LANGS='krn sweet' runs a
# subset, for the loop where you already know which one you are chasing.
#
# PARALLEL IS NOT FORCED, AND THAT COST AN HOUR TO LEARN.  The first draft ran
# every bundle with PARALLEL=1 for speed.  r7rs is 21 spec files each booting a
# full tower, and the shared runner's own header says it: "a per-process guard
# cannot fix memory exhaustion from many heavy specs loading in PARALLEL; for
# that lower PARALLEL_JOBS."  Under load whole batches get killed by the alloc
# ceiling, report no result, and the runner counts every one as a failure --
# r7rs came back 637 of 637 red on one run and 58 on the next, with nothing
# changed between them.
#
# A GATE THAT FLAKES IS WORSE THAN NO GATE: it trains you to re-run until green,
# which is the same as not having it.  So the runners get their own default,
# which is serial.  Export PARALLEL yourself if you want to trade that back.
set -e

ROOT="$(cd "$(dirname "$0")/../.." && pwd)"
MANIFEST="$ROOT/tools/contract/langs.x"

[ -f "$MANIFEST" ] || { echo "langs: no $MANIFEST" >&2; exit 1; }

# Read the manifest the way every other one here is read: textually, by row.
DEFAULT_DIR="$(sed -n 's/^(langs-dir "\([^"]*\)").*/\1/p' "$MANIFEST" | head -1)"
LANGS_DIR="${X_LANGS_DIR:-$ROOT/$DEFAULT_DIR}"

if [ ! -d "$LANGS_DIR" ]; then
	echo "langs: SKIPPED -- no bundles at $LANGS_DIR"
	echo "  set X_LANGS_DIR to point at a directory of lang bundles"
	exit 0
fi

# THE X UNDER TEST IS THIS TREE'S WRAPPER, and that is the whole point of the
# gate.  A bundle runner asks `x --share-dir` where the platform lives, and mode
# detection is cwd-based -- from a bundle directory the x on PATH answers the
# INSTALL, so a suite run without this would score the last release rather than
# the change you are about to push.
X_UNDER_TEST="$ROOT/x.sh"
[ -x "$X_UNDER_TEST" ] || { echo "langs: no wrapper at $X_UNDER_TEST" >&2; exit 1; }

_fails=0
_skips=0
_ratchet=""

printf '%-8s %8s %8s %8s   %s\n' "LANG" "TESTS" "FAILED" "BUDGET" "VERDICT"

# One row per lang: NAME DIR TESTS FAILED
sed -n 's/^(lang "\([^"]*\)"  *"\([^"]*\)"  *\([0-9]*\)  *\([0-9]*\)).*/\1 \2 \3 \4/p' "$MANIFEST" \
| while read -r name dir want_tests budget; do
	if [ -n "${LANGS:-}" ]; then
		case " $LANGS " in *" $name "*) ;; *) continue ;; esac
	fi

	D="$LANGS_DIR/$dir"
	if [ ! -f "$D/tests/spec-runner.sh" ]; then
		printf '%-8s %8s %8s %8s   %s\n' "$name" "-" "-" "$budget" "SKIPPED (not present)"
		echo "$name" >> "$ROOT/.langs-skips.$$"
		continue
	fi

	# PARSED IN AWK, and neither half of that is fussiness.  BSD sed does not
	# interpret \033 in a pattern, so the obvious ANSI strip silently matches
	# nothing on macOS and the coloured summary line never anchors.  And a
	# greedy .* before a digit class eats all but the last digit -- "74 tests"
	# captures 4, "80 failed" captures 0, and a bundle 80 specs in the red
	# reports green.  Both of those were live in the first draft of this file.
	line="$(cd "$D" && X="$X_UNDER_TEST" sh tests/spec-runner.sh 2>&1 \
		| awk '{
			gsub(/\033\[[0-9;]*m/, "")
			if ($0 ~ /^[0-9]+ tests, [0-9]+ failed/) print $1 " " $3
		}' \
		| tail -1)"

	tests="${line% *}"
	failed="${line#* }"

	# NO RESULT IS A FAILURE, never a pass.  A suite whose harness died prints
	# no summary line at all, and treating a missing number as zero is how a
	# broken platform reads as a green one.
	if [ -z "$line" ] || [ -z "$failed" ]; then
		printf '%-8s %8s %8s %8s   %s\n' "$name" "?" "?" "$budget" "FAIL (no result -- suite did not report)"
		echo "$name" >> "$ROOT/.langs-fails.$$"
		continue
	fi

	verdict="ok"
	bad=0
	if [ "$failed" -gt "$budget" ]; then
		verdict="FAIL (+$((failed - budget)) over budget)"; bad=1
	elif [ "$failed" -lt "$budget" ]; then
		verdict="improved -- ratchet langs.x to $failed"
	fi
	# A SUITE THAT SHRANK is compared against a number that described a bigger
	# run, so the budget stops meaning what it said.  Loud, not fatal: a bundle
	# is free to reorganise its specs, and the fix is to re-record.
	if [ "$tests" -lt "$want_tests" ]; then
		verdict="$verdict; suite shrank $want_tests->$tests, re-record"
	fi

	printf '%-8s %8s %8s %8s   %s\n' "$name" "$tests" "$failed" "$budget" "$verdict"
	# if/fi, NOT `[ ... ] && echo`.  Under set -e a trailing test that is FALSE
	# is a non-zero last command, which kills this pipeline's subshell before
	# the summary below ever runs -- so a clean run of every lang exited 1 with
	# no verdict line.  The happy path is the one that trips it.
	if [ "$bad" = 1 ]; then echo "$name" >> "$ROOT/.langs-fails.$$"; fi
done

# The loop above runs in a subshell (the pipe), so its counters do not survive
# it.  Files do.
if [ -f "$ROOT/.langs-skips.$$" ]; then
	_skips="$(wc -l < "$ROOT/.langs-skips.$$" | tr -d ' ')"
	rm -f "$ROOT/.langs-skips.$$"
fi
if [ -f "$ROOT/.langs-fails.$$" ]; then
	_fails="$(wc -l < "$ROOT/.langs-fails.$$" | tr -d ' ')"
	rm -f "$ROOT/.langs-fails.$$"
fi

echo
if [ "$_fails" -gt 0 ]; then
	echo "langs: FAIL -- $_fails bundle(s) worse than tools/contract/langs.x records"
	exit 1
fi
echo "langs: ok ($_skips skipped as absent)"
