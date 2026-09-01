#!/bin/sh
# fan-out-langs.sh -- run every language bundle's suite against an x, and
# stage the release bump for the ones that pass.
#
#   sh tools/release/fan-out-langs.sh TAG /path/to/x [LANGS_DIR]
#
# The x-lang half of a release fan-out: eight bundles, each needing the
# same four motions -- point X at the new tree, run the suite, bump
# (requires-release ...) in lang.xon, leave the change for review.  This
# script sequences them and stops exactly where a human should look:
#
#   - NOTHING IS PUSHED and no PR is opened.  A green bundle gets a LOCAL
#     branch (bump/x-lang-TAG) carrying the one-line lang.xon commit; a
#     red one gets a log and a report line.  Red means the release
#     surfaced a real incompatibility -- staging a bump over it would be
#     the lie this script exists to prevent.
#   - THE USER'S CHECKOUTS ARE NEVER TOUCHED.  Each bundle is built in a
#     temporary worktree off origin/<default>; dirty trees and checked-out
#     feature branches are invisible to the run.  The bump branch survives
#     the worktree; the worktree does not survive the run.
#   - AN EXISTING BUMP BRANCH IS REFUSED, per bundle, not reset -- it may
#     carry the operator's own edits.  Delete it to redo that bundle.
#
# X is a launcher that answers --share-dir (an installed x, a release
# unpack's x, or a checkout's x.sh).  Bundles with the kit gate run
# tests/spec-gate.sh (failures compared to the bundle's known set);
# bundles not yet migrated run tests/spec-runner.sh raw, and the report
# says which door was used.  Suites run one bundle at a time.
#
# Logs land in build/fanout-TAG/<bundle>.log.  Exit 1 when any bundle is
# red or skipped, 0 when every bundle staged.
set -e

ROOT="$(cd "$(dirname "$0")/../.." && pwd)"
TAG="${1:?usage: sh tools/release/fan-out-langs.sh TAG /path/to/x [LANGS_DIR]}"
XBIN="${2:?usage: sh tools/release/fan-out-langs.sh TAG /path/to/x [LANGS_DIR]}"
LANGS="${3:-$ROOT/../languages}"

case "$XBIN" in /*) ;; *) XBIN="$(pwd)/$XBIN" ;; esac
[ -x "$XBIN" ] || { echo "fan-out: $XBIN is not executable" >&2; exit 2; }
"$XBIN" --share-dir >/dev/null 2>&1 || {
	echo "fan-out: $XBIN does not answer --share-dir; point at an x launcher" >&2
	exit 2
}
[ -d "$LANGS" ] || { echo "fan-out: no bundle directory at $LANGS" >&2; exit 2; }

LOGS="$ROOT/build/fanout-$TAG"
mkdir -p "$LOGS"
BRANCH="bump/x-lang-$TAG"
WORK=$(mktemp -d)
trap 'rm -rf "$WORK"' EXIT

staged=""; red=""; skipped=""

for repo in "$LANGS"/*/; do
	name=$(basename "$repo")
	[ -d "$repo/.git" ] || continue
	log="$LOGS/$name.log"

	if git -C "$repo" show-ref --verify --quiet "refs/heads/$BRANCH"; then
		echo "$name: SKIP -- $BRANCH already exists; delete it to redo"
		skipped="$skipped $name"
		continue
	fi
	# A bundle without a remote is legitimate (local-only); its default
	# branch is the base then, and the report says which base was used.
	if git -C "$repo" remote get-url origin >/dev/null 2>&1; then
		git -C "$repo" fetch -q origin || {
			echo "$name: SKIP -- fetch failed"
			skipped="$skipped $name"
			continue
		}
		head=$(git -C "$repo" symbolic-ref -q --short refs/remotes/origin/HEAD \
			| sed 's|^origin/||')
		base="origin/${head:-main}"
	else
		base="main"
		git -C "$repo" show-ref --verify --quiet refs/heads/main || {
			echo "$name: SKIP -- no origin and no local main to base on"
			skipped="$skipped $name"
			continue
		}
	fi

	wt="$WORK/$name"
	[ -L "$wt" ] && rm "$wt"      # a sibling link from an earlier bundle
	git -C "$repo" worktree add -q "$wt" -b "$BRANCH" "$base"

	# A bundle may declare (requires-lang "NAME") siblings it expects
	# BESIDE itself; the isolated worktree has none, so link each
	# declared sibling's checkout in.  Read-only use: the suite loads
	# the sibling's lang tree, it does not run the sibling's gate.
	for lang in $(sed -n 's/^(requires-lang "\([^"]*\)".*/\1/p' "$wt/lang.xon"); do
		for cand in "$LANGS/$lang" "$LANGS/x-$lang"; do
			if [ -d "$cand" ] && [ ! -e "$WORK/$(basename "$cand")" ]; then
				ln -s "$cand" "$WORK/$(basename "$cand")"
			fi
		done
	done

	if [ -f "$wt/tests/spec-gate.sh" ]; then
		door="gate"; runner="tests/spec-gate.sh"
	else
		door="raw suite (no kit gate yet)"; runner="tests/spec-runner.sh"
	fi

	if ( cd "$wt" && X="$XBIN" sh "$runner" ) > "$log" 2>&1; then
		sed "s|^(requires-release \"[^\"]*\")|(requires-release \"$TAG\")|" \
			"$wt/lang.xon" > "$wt/lang.xon.new"
		if cmp -s "$wt/lang.xon" "$wt/lang.xon.new"; then
			rm -f "$wt/lang.xon.new"
			echo "$name: SKIP -- green ($door) but no (requires-release ...) row to bump"
			skipped="$skipped $name"
			git -C "$repo" worktree remove -f "$wt"
			git -C "$repo" branch -q -D "$BRANCH"
			continue
		fi
		mv "$wt/lang.xon.new" "$wt/lang.xon"
		git -C "$wt" commit -q lang.xon -m "chore: require x-lang $TAG ($door green)"
		echo "$name: staged -- $BRANCH off $base ($door green)"
		staged="$staged $name"
	else
		echo "$name: RED ($door) -- $(tail -1 "$log")"
		echo "  log: $log"
		red="$red $name"
		git -C "$repo" worktree remove -f "$wt"
		git -C "$repo" branch -q -D "$BRANCH"
		continue
	fi
	git -C "$repo" worktree remove -f "$wt" 2>/dev/null || true
done

echo
echo "fan-out $TAG: staged:${staged:- none}"
echo "fan-out $TAG: red:${red:- none}"
echo "fan-out $TAG: skipped:${skipped:- none}"
[ -z "$red$skipped" ]
