#!/bin/sh
# tools/dev/image-build.sh -- write a state image of a library, if it is stale.
#
#   sh tools/dev/image-build.sh LIB-FILE OUT-DIR      # e.g. lib/x-core.x .images
#
# Writes OUT-DIR/<lib file name>.ximg with tools/dev/image-write.x imaging a
# CHILD base that loaded LIB-FILE, and OUT-DIR/<name>.key beside it.  The key
# is what the image depends on: every .x under lib/, the writer and the walk
# it includes, and the engine binary -- an image is a heap laid out by one
# engine release and holds every definition the library made, so a change to
# any of those is a different image.  A matching key skips the write, which is
# the point: the writer takes a minute and a half, the load a quarter second.
#
# Needs an engine carrying (image rebuild!); x.sh honours X_BIN.
#
# @author [Jon Ruttan](jonruttan@gmail.com)
# @copyright 2026 Jon Ruttan
# @license MIT No Attribution (MIT-0)
set -e
lib="$1"; out="$2"
[ -n "$lib" ] && [ -n "$out" ] || { echo "usage: image-build.sh LIB-FILE OUT-DIR" >&2; exit 2; }
root="$(cd "$(dirname "$0")/../.." && pwd)"
cd "$root"
name="$(basename "$lib")"
mkdir -p "$out"
img="$out/$name.ximg"; keyf="$out/$name.key"
engine="${X_BIN:-$root/x-bin}"
key="$( { find lib -name '*.x' | LC_ALL=C sort | xargs cat; cat tools/dev/image-write.x tools/dev/image-walk.x tools/dev/image-name.x; cat "$engine"; } | shasum | cut -d' ' -f1)"
if [ -f "$img" ] && [ -f "$keyf" ] && [ "$(cat "$keyf")" = "$key" ]; then
	echo "image-build: $img is current"
	exit 0
fi
echo "image-build: writing $img from $lib"
rm -f "$img" "$keyf"
{ printf '(def %%IMG-LIB "%s") (def %%IMG-OUT "%s")\n' "$lib" "$img"; cat tools/dev/image-write.x; } \
	| sh x.sh -q > "$out/$name.log" 2>&1 || true
grep 'objects:\|IMAGE TOTAL\|ERROR\|fault' "$out/$name.log" || true
# The writer is the left side of a pipe, so its death is invisible to set -e;
# the image on disk is the only witness that counts.
if [ ! -s "$img" ]; then
	echo "image-build: no image written -- see $out/$name.log" >&2
	exit 1
fi
# An unnameable is a word the loader will restore as nil -- a JIT entry
# point, a lent object.  An image carrying one is a crash waiting for the
# call that reaches it; it is not written.
if ! grep -q 'unnameable: 0' "$out/$name.log"; then
	echo "image-build: $img has unnameable words -- not kept; see $out/$name.log" >&2
	rm -f "$img"
	exit 1
fi
printf '%s\n' "$key" > "$keyf"
