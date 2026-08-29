#!/bin/sh
# release-version.sh -- the tag, the library version and the changelog agree.
#
# THREE PLACES HOLD ONE FACT, and nothing held them together.  v0.6.0 shipped
# reporting `helium 0.5.2` in its banner and in `x -V`, because the tag and the
# changelog moved and lib/x-core.x's x-lib-version did not.  The release stamp
# (share/x/contract/release) was correct, so pinning and the pairing guard were
# unaffected -- only the number a user is shown was wrong, which is the kind of
# defect that survives precisely because nothing loads it.
#
# CHECKED, NOT GENERATED, and that is forced.  x-lib-version lives in
# lib/x-core.x, which ships verbatim and is covered by the release's PAYLOAD
# fingerprint -- a value written into it at build time would change that digest
# on every build and make the fingerprint describe the builder rather than the
# release.  So the three stay separate and this holds them equal.
#
# ONLY MEANINGFUL AT A TAG.  On any other commit `git describe --exact-match`
# says nothing and there is no release to agree with, so this skips and says
# so: a gate that invented an answer on a dev checkout would be noise every
# other day of the week.
set -e

cd "$(dirname "$0")/../.."

TAG=$(git describe --tags --exact-match 2>/dev/null || true)
if [ -z "$TAG" ]; then
	echo "release-version: SKIPPED -- not at a tag, so there is no release to agree with"
	exit 0
fi

# The tag is the authority: it is what the release workflow publishes under and
# what an installed tree stamps into share/x/contract/release.
WANT=${TAG#v}

LIB=$(sed -n 's/^(def x-lib-version "\([^"]*\)").*/\1/p' lib/x-core.x | head -1)
[ -n "$LIB" ] || { echo "release-version: cannot read x-lib-version from lib/x-core.x" >&2; exit 2; }

# The newest RELEASED section, skipping [Unreleased].
LOG=$(sed -n 's/^## \[\([0-9][^]]*\)\].*/\1/p' CHANGELOG.md | head -1)
[ -n "$LOG" ] || { echo "release-version: cannot read a version from CHANGELOG.md" >&2; exit 2; }

fail=0
if [ "$LIB" != "$WANT" ]; then
	echo "release-version: tag is $TAG but lib/x-core.x says x-lib-version \"$LIB\"" >&2
	echo "  the banner and \`x -V\` would report $LIB for a release called $TAG" >&2
	fail=1
fi
if [ "$LOG" != "$WANT" ]; then
	echo "release-version: tag is $TAG but CHANGELOG.md's newest entry is [$LOG]" >&2
	fail=1
fi

[ "$fail" = 0 ] || { echo "release-version: FAIL -- bump the one that is behind" >&2; exit 1; }
echo "release-version: ok ($TAG: x-lib-version, CHANGELOG and tag agree)"
