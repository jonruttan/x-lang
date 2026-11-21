#!/bin/sh
# install.sh -- copy the official bundles into an install's bundles directory.
#
#   sh tools/bundles/install.sh DEST
#
# `make install` runs this with DEST the install's bundles/, where the
# wrapper looks.  Each bundle tools/bundles/NAME.pin.xon pins is copied from
# deps/bundles/NAME, as `make bundles` (fetch.sh) acquired it.
#
# A pinned bundle that is absent, or was acquired at another pin, fails the
# install: a release does not ship without a bundle it names.  Only the
# pinned bundles are copied; whatever else is under deps/bundles/ stays
# there.  With nothing pinned DEST is not created.
#
#   BUNDLE_PINS=DIR   read the pins from DIR (the gate's fixture)
#   BUNDLE_SRC=DIR    copy from DIR
set -e

[ -n "${1:-}" ] || { echo "usage: sh tools/bundles/install.sh DEST" >&2; exit 2; }
DEST=$1
case "$DEST" in
	/*) ;;
	*) DEST="$(pwd)/$DEST" ;;
esac

cd "$(dirname "$0")/../.."
PINS="${BUNDLE_PINS:-tools/bundles}"
SRC="${BUNDLE_SRC:-deps/bundles}"

for _pin in "$PINS"/*.pin.xon; do
	[ -f "$_pin" ] || continue
	_name=$(basename "$_pin" .pin.xon)
	if [ ! -f "$SRC/$_name/bundle.xon" ] || ! cmp -s "$_pin" "$SRC/$_name.pin"; then
		echo "bundles: the official bundle '$_name' is not acquired at its pin -- run 'make bundles'" >&2
		exit 1
	fi
	mkdir -p "$DEST"
	rm -rf "${DEST:?}/$_name"
	cp -R "$SRC/$_name" "$DEST/$_name"
	diff -r "$SRC/$_name" "$DEST/$_name"
done
