#!/bin/sh
# changelog-collect.sh -- the changelog entries the commits since a tag carry.
#
# A feat, fix or perf commit carries its changelog entry in its own message:
# a line reading `Changelog:`, then the entry as it appears in CHANGELOG.md,
# up to the message's trailers.  No commit edits CHANGELOG.md, so two pull
# requests never edit the same line of it, and merging one leaves the others
# mergeable.  The file is written once, at release, from this script.
#
#   changelog-collect.sh [FROM [TO]]
#
# walks TO (HEAD) back to FROM (the newest tag) along the first parent and
# prints the entries, newest first, each followed by a link line for every
# pull request it names -- ready to go under the new `## [N]` heading.  A
# merge of a pull request is one group, its own commits read for entries;
# a run of commits made straight on the branch is another.  An entry that
# does not name its own pull request has `([#N])` put after its lead
# sentence, N from the merge commit.  A group that added lines to
# CHANGELOG.md is left out: its entry is in the file already.
#
#   changelog-collect.sh --check [--since COMMIT] [FROM [TO]]
#
# prints nothing but the groups that have a feat, fix or perf commit and no
# entry, and exits 1 when there is one.  With --since, a group that is an
# ancestor of COMMIT is not checked: the rule began there.
#
# Without a tag in reach -- a shallow checkout -- there is nothing to walk,
# so this says so and exits 0.
set -e

cd "$(dirname "$0")/../.."

PR_URL=${CHANGELOG_PR_URL:-https://github.com/jonruttan/x-lang/pull}

check=0
since=""
while [ $# -gt 0 ]; do
	case "$1" in
		--check) check=1; shift ;;
		--since) since=$2; shift 2 ;;
		*) break ;;
	esac
done
from=${1:-$(git describe --tags --abbrev=0 2>/dev/null || true)}
to=${2:-HEAD}
if [ -z "$from" ]; then
	echo "changelog-collect: SKIPPED -- no tag in reach, so there are no commits since one to read"
	exit 0
fi

# The entry a commit's message carries: the lines after `Changelog:`, the
# trailers and blank lines at the end dropped.  Prints nothing for none.
entry_of() {
	git log -1 --format=%B "$1" | awk '
		/^Changelog:$/ { on = 1; next }
		on { line[++n] = $0 }
		END {
			while (n > 0 && (line[n] ~ /^$/ || line[n] ~ /^[A-Za-z][A-Za-z-]*: /)) {
				n--
			}
			for (i = 1; i <= n; i++) {
				print line[i]
			}
		}'
}

# Whether any commit of the group, given on stdin, is a feat, fix or perf.
needs_entry() {
	while read -r c; do
		if git log -1 --format=%s "$c" | grep -q '^\(feat\|fix\|perf\)[(:]'; then
			return 0
		fi
	done
	return 1
}

# Print one entry: the text, `([#N])` added after the lead sentence when it
# names no pull request, then a link line for each pull request named.
print_entry() {
	n=$1
	text=$2
	if [ -n "$n" ] && ! printf '%s\n' "$text" | grep -q "\[#$n\]"; then
		text=$(printf '%s\n' "$text" | awk -v n="$n" '
			!done && /\*\*.*\*\*/ { sub(/\*\*[^*]*\*\*/, "&" " ([#" n "])"); done = 1 }
			!done && NR == 1 { $0 = $0 " ([#" n "])"; done = 1 }
			{ print }')
	fi
	printf '%s\n\n' "$text"
	printf '%s\n' "$text" | grep -o '\[#[0-9][0-9]*\]' | sort -u | sed 's/^\[#\(.*\)\]$/\1/' |
	while read -r k; do
		printf '[#%s]: %s/%s\n' "$k" "$PR_URL" "$k"
	done
	printf '\n'
}

# One group: NUMBER (or empty), HEAD commit, and the group's commits on stdin.
group() {
	n=$1
	head=$2
	commits=$(cat)
	if [ -n "$since" ] && git merge-base --is-ancestor "$head" "$since" 2>/dev/null; then
		return 0
	fi
	# A group that added lines to CHANGELOG.md wrote its entry there: the
	# style before this script, or a release commit.  One that only took lines
	# out moved its entry into a commit, and is read like any other.
	added=$(git diff --numstat "$head^" "$head" -- CHANGELOG.md 2>/dev/null | awk '{ n += $1 } END { print n + 0 }')
	if [ "$added" -gt 0 ]; then
		return 0
	fi
	found=0
	for c in $commits; do
		e=$(entry_of "$c")
		if [ -n "$e" ]; then
			found=1
			if [ "$check" = 0 ]; then
				print_entry "$n" "$e"
			fi
		fi
	done
	if [ "$check" = 1 ] && [ "$found" = 0 ] && printf '%s\n' "$commits" | needs_entry; then
		if [ -n "$n" ]; then
			echo "changelog-commits: #$n -- $(git log -1 --format=%s "$head")"
		else
			echo "changelog-commits: $(git log -1 --format='%h %s' "$head")"
		fi
		return 1
	fi
	return 0
}

# Walk the first parent, newest first: a pull request's merge is a group of
# the commits it brought; consecutive commits made straight on the branch are
# one group, their newest the head.  Any other merge -- a branch taking
# main in -- brings commits that are main's, grouped by their own merges, and
# is passed over: the branch's commits on either side of it stay one group.
bad=0
run=""
run_head=""
flush_run() {
	if [ -n "$run" ]; then
		if ! printf '%s\n' $run | group "" "$run_head"; then
			bad=1
		fi
		run=""
		run_head=""
	fi
}
for h in $(git log --first-parent --format=%H "$from..$to"); do
	parents=$(git log -1 --format=%P "$h")
	set -- $parents
	n=$(git log -1 --format=%s "$h" | sed -n 's/^Merge pull request #\([0-9][0-9]*\) .*/\1/p')
	if [ $# -ge 2 ] && [ -n "$n" ]; then
		flush_run
		if ! git log --no-merges --format=%H "$1..$2" | group "$n" "$h"; then
			bad=1
		fi
	elif [ $# -ge 2 ]; then
		:
	else
		if [ -z "$run" ]; then
			run_head=$h
		fi
		run="$run $h"
	fi
done
flush_run

if [ "$check" = 1 ]; then
	if [ "$bad" = 1 ]; then
		echo "changelog-commits: FAIL -- a feat, fix or perf commit carries its entry after a 'Changelog:' line in its message" >&2
		exit 1
	fi
	# A branch must not ADD to CHANGELOG.md either: the file is written at
	# release, and a pull request that adds its paragraph puts every other
	# open one in conflict the moment it merges.  What a merge would add is
	# the net difference from the merge base with origin/main -- a commit
	# that added and a later one that took back leave nothing -- and a
	# release branch, which carries a `release:` commit, is the one that may.
	# Without origin/main in reach there is nothing to compare against.
	if git rev-parse -q --verify origin/main >/dev/null 2>&1; then
		mb=$(git merge-base "$to" origin/main 2>/dev/null || true)
		if [ -n "$mb" ] && [ "$mb" != "$(git rev-parse "$to")" ]; then
			net=$(git diff --numstat "$mb" "$to" -- CHANGELOG.md 2>/dev/null | awk '{ n += $1 } END { print n + 0 }')
			if [ "$net" -gt 0 ] && ! git log --format=%s "$mb..$to" | grep -q '^release: '; then
				echo "changelog-commits: FAIL -- this branch adds $net lines to CHANGELOG.md; the file is written at release, and an entry goes after a 'Changelog:' line in the commit" >&2
				exit 1
			fi
		fi
	fi
	echo "changelog-commits: ok (every feat, fix and perf since $from carries its entry, and nothing adds to CHANGELOG.md)"
fi
