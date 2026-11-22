#!/bin/sh
# fetch.sh -- acquire the official bundles the pins beside this file name.
#
#   sh tools/bundles/fetch.sh
#
# An official bundle is a library, or an app, that an x-lang release carries.
# Each has one pin here, tools/bundles/NAME.pin.xon, in the form the pin tool
# reads:
#
#   (name "net")
#   (release "v0.1.0")
#   (bundle "sha256:..." "https://.../x-net-v0.1.0.tar.gz")
#
# `make bundles` runs this.  Each pinned bundle lands in deps/bundles/NAME,
# which is where a checkout's wrapper looks, so a missed import finds it, and
# `make install` copies it from there into the install's bundles/.
#
# The pin tool does the work: (Pin install ...) downloads the archive,
# digests it before unpacking it, and replaces a previous copy only once the
# new one has verified.  This script adds one thing, the same the engine fetch
# has: a bundle already acquired at its pin is left alone, with no network.
# The pin it was acquired at is kept beside it, deps/bundles/NAME.pin, and a
# pin that differs is what makes it fetched again.
#
# x-lang imports no bundle, so nothing here is needed to build or test it:
# this is for an install, and for a checkout that wants what a release has.
#
#   BUNDLE_PINS=DIR   read the pins from DIR (the gate's fixture)
#   BUNDLE_DEST=DIR   acquire into DIR
set -e

cd "$(dirname "$0")/../.."
PINS="${BUNDLE_PINS:-tools/bundles}"
DEST="${BUNDLE_DEST:-deps/bundles}"

_bf_die() {
	echo "bundles: $*" >&2
	exit 1
}

mkdir -p "$DEST"
DEST=$(cd "$DEST" && pwd)
case "$DEST" in
	*\"* | *\\*) _bf_die "the destination path contains a quote or backslash: $DEST" ;;
esac

_TMP=$(mktemp -d) || exit 1
trap 'rm -rf "$_TMP"' EXIT
trap 'exit 130' INT
trap 'exit 143' TERM

_found=0
for _pin in "$PINS"/*.pin.xon; do
	[ -f "$_pin" ] || continue
	_found=1
	_name=$(sed -n 's/^(name "\([^"]*\)").*/\1/p' "$_pin" | head -1)
	[ -n "$_name" ] || _bf_die "$_pin names no bundle: it has no (name \"...\") row"
	# The file is named for the bundle it pins, so the directory lists them.
	[ "$(basename "$_pin" .pin.xon)" = "$_name" ] \
		|| _bf_die "$_pin pins '$_name': the file is named for its bundle, $_name.pin.xon"

	if [ -f "$DEST/$_name/bundle.xon" ] && cmp -s "$_pin" "$DEST/$_name.pin"; then
		echo "bundles: $_name is as pinned"
		continue
	fi

	_abs="$(cd "$(dirname "$_pin")" && pwd)/$(basename "$_pin")"
	case "$_abs" in
		*\"* | *\\*) _bf_die "the pin's path contains a quote or backslash: $_abs" ;;
	esac
	printf '(alloc-limit! 300000000)\n(import x/tool/pin)\n(Pin install "file://%s" "%s")\n' \
		"$_abs" "$DEST" > "$_TMP/install.x"
	# The record goes first: a failed acquisition must not leave a record
	# that says the bundle is as pinned.
	rm -f "$DEST/$_name.pin"
	sh x.sh --no-pin -q -f "$_TMP/install.x" || _bf_die "$_name was not acquired"
	cp "$_pin" "$DEST/$_name.pin"
done

[ "$_found" = 1 ] || echo "bundles: no official bundle is pinned"
