#!/bin/sh
# changelog-commits.sh -- every feat, fix or perf commit since the newest tag
# carries its changelog entry in its message.
#
# The changelog is written at release from the commits (tools/release/
# changelog-collect.sh), so an entry a commit does not carry is one the
# release cannot have.  Checked here, before the merge, where the author can
# still amend.  Commits older than the commit that added the collector are not
# held to a rule that did not exist yet.
set -e

cd "$(dirname "$0")/../.."

floor=$(git log --format=%H --diff-filter=A -- tools/release/changelog-collect.sh 2>/dev/null | tail -1)
if [ -n "$floor" ]; then
	sh tools/release/changelog-collect.sh --check --since "$floor"
else
	sh tools/release/changelog-collect.sh --check
fi
