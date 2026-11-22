#!/bin/sh
# # x-lang -- the bundle kit
#
# ## tools/bundle-kit/roll.sh -- roll a bundle's release: the tarball and its pin
#
# @description Archives what a consumer of a bundle needs at a tag, digests
#   the archive, and writes the bundle.pin.xon that names it.
# @author [Jon Ruttan](jonruttan@gmail.com)
# @copyright 2026 Jon Ruttan
# @license MIT No Attribution (MIT-0)
#
#     ., .,
#     {O,O}
#     (   )
#      " "
#
#   BUNDLE=. sh "$(x --share-dir)/tools/bundle-kit/roll.sh" TAG [OUT]
#
# Writes three files into OUT (default dist/), named for the repository:
#
#   REPO-TAG.tar.gz          the bundle
#   REPO-TAG.tar.gz.sha256   its digest, as shasum prints it
#   bundle.pin.xon           the pin: the bundle's name, the tag, the digest
#                            and the URL the tarball is published at
#
# The tarball holds what runs, not the repository: bundle.xon, lib/, and
# LICENSE and README.md where the bundle has them, under one directory
# REPO-TAG/, with a file `version` holding the tag.  The suite, the tooling
# and the CI stay in the repository.  It is cut from the tag with git archive,
# so an uncommitted file is not in it, and gzip writes no time, so the same
# tag rolls the same bytes.
#
# The repository is read, never derived from the bundle's name: a bundle named
# net may live at x-lib-net, or anywhere its author keeps it.  It is
# BUNDLE_REPO where that is set, as OWNER/REPO, then GITHUB_REPOSITORY, then
# the origin remote.  The published URL is that repository's GitHub release
# for the tag; BUNDLE_URL_BASE names another place the three files will sit.
set -e

BUNDLE="${BUNDLE:-$(pwd)}"
BUNDLE=$(cd "$BUNDLE" && pwd)
cd "$BUNDLE"

_roll_die() {
	echo "bundle-kit roll: $*" >&2
	exit 1
}

TAG="${1:-}"
[ -n "$TAG" ] || _roll_die "usage: roll.sh TAG [OUT]"
OUT="${2:-dist}"

git rev-parse --verify --quiet "$TAG^{commit}" >/dev/null \
	|| _roll_die "no such tag or commit: $TAG"

# The declaration as it is at the tag, which is what the tarball carries.
_XON=$(git show "$TAG:bundle.xon" 2>/dev/null) \
	|| _roll_die "no bundle.xon at $TAG"
NAME=$(printf '%s\n' "$_XON" | sed -n 's/^(name "\([^"]*\)").*/\1/p' | head -1)
[ -n "$NAME" ] || _roll_die "bundle.xon at $TAG has no (name \"...\") row"
git cat-file -e "$TAG:lib/$NAME" 2>/dev/null \
	|| _roll_die "no lib/$NAME at $TAG: a bundle's modules are under lib/, in a directory of its name"

REPO="${BUNDLE_REPO:-${GITHUB_REPOSITORY:-}}"
if [ -z "$REPO" ]; then
	_url=$(git remote get-url origin 2>/dev/null) \
		|| _roll_die "no origin remote: set BUNDLE_REPO to OWNER/REPO"
	# https://HOST/OWNER/REPO(.git) and git@HOST:OWNER/REPO(.git)
	REPO=$(printf '%s\n' "$_url" | sed -e 's/\.git$//' -e 's|.*[:/]\([^/:]*/[^/]*\)$|\1|')
fi
case "$REPO" in
	*/*/* | /* | */ | *\"* | *\\* | *' '*) _roll_die "not an OWNER/REPO: $REPO" ;;
	*/*) ;;
	*) _roll_die "not an OWNER/REPO: $REPO" ;;
esac
STEM="${REPO##*/}-$TAG"
BASE="${BUNDLE_URL_BASE:-https://github.com/$REPO/releases/download/$TAG}"

# What a consumer needs.  A path the tag does not have is left out.
PATHS="bundle.xon lib"
for _p in LICENSE README.md; do
	if git cat-file -e "$TAG:$_p" 2>/dev/null; then PATHS="$PATHS $_p"; fi
done

mkdir -p "$OUT"
_TMP=$(mktemp -d) || exit 1
trap 'rm -rf "$_TMP"' EXIT
trap 'exit 130' INT
trap 'exit 143' TERM
printf '%s\n' "$TAG" > "$_TMP/version"
chmod 644 "$_TMP/version"

# --add-file is git 2.38's.  Without the stamp an installed bundle cannot say
# what release it is, so an older git is refused rather than worked around.
# shellcheck disable=SC2086
git archive --format=tar --prefix="$STEM/" "--add-file=$_TMP/version" "$TAG" $PATHS \
	> "$_TMP/bundle.tar" 2> "$_TMP/err" \
	|| { cat "$_TMP/err" >&2; _roll_die "git archive failed (--add-file needs git 2.38)"; }
gzip -n -9 < "$_TMP/bundle.tar" > "$OUT/$STEM.tar.gz"

if command -v shasum >/dev/null 2>&1; then
	DG=$(shasum -a 256 "$OUT/$STEM.tar.gz" | cut -d' ' -f1)
else
	DG=$(sha256sum "$OUT/$STEM.tar.gz" | cut -d' ' -f1)
fi
printf '%s  %s\n' "$DG" "$STEM.tar.gz" > "$OUT/$STEM.tar.gz.sha256"

{
	printf '(name "%s")\n' "$NAME"
	printf '(release "%s")\n' "$TAG"
	printf '(bundle "sha256:%s" "%s/%s.tar.gz")\n' "$DG" "$BASE" "$STEM"
	case "$BASE" in
		https://github.com/*) printf '(source "https://github.com/%s.git")\n' "$REPO" ;;
	esac
} > "$OUT/bundle.pin.xon"

echo "bundle-kit roll: $OUT/$STEM.tar.gz"
echo "bundle-kit roll: $OUT/$STEM.tar.gz.sha256"
echo "bundle-kit roll: $OUT/bundle.pin.xon"
