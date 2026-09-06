#!/bin/sh
# tools/dev/image-build.sh -- write a state image of a library, if it is stale.
#
#   sh tools/dev/image-build.sh LIB-FILE OUT-DIR [KEY-PATH...]
#       e.g. lib/x-core.x .images
#       e.g. /path/x-awk/tests/lib/harness.gen.x /path/x-awk/tests/lib/.images /path/x-awk/awk
#
# Writes OUT-DIR/<lib file name>.ximg with tools/dev/image-write.x imaging a
# CHILD base that loaded LIB-FILE, and OUT-DIR/<name>.key beside it.  The key
# is what the image depends on: the library file, every .x under lib/,
# tests/x/lib/ and the engine's contract directory, the writer and the walk
# it includes, the engine binary -- an image is a heap laid out by one
# engine release and holds every definition the library made, so a change to
# any of those is a different image -- and every .x under each KEY-PATH,
# which is how a lang bundle's harness names the bundle's own modules: the
# platform rule hashes the platform, and the caller adds what it loaded on
# top.  A matching key skips the write, which is the point: a write is a few
# seconds, a load a third of one.
#
# Needs an engine carrying (image rebuild!); x.sh honours X_BIN.  Runs from a
# CHECKOUT: the writer's includes and the key's directories are repo-relative.
#
# Exit 0: the image is current or was written.  Exit 3: this library holds
# words no image can carry (the unnameable rule below) and boots from
# source.  Anything else: the write failed and OUT-DIR/<name>.log says how.
#
# @author [Jon Ruttan](jonruttan@gmail.com)
# @copyright 2026 Jon Ruttan
# @license MIT No Attribution (MIT-0)
set -e
lib="$1"; out="$2"
[ -n "$lib" ] && [ -n "$out" ] || { echo "usage: image-build.sh LIB-FILE OUT-DIR [KEY-PATH...]" >&2; exit 2; }
shift 2
root="$(cd "$(dirname "$0")/../.." && pwd)"
cd "$root"
name="$(basename "$lib")"
mkdir -p "$out"
img="$out/$name.ximg"; keyf="$out/$name.key"
engine="${X_BIN:-$root/x-bin}"
# The test libraries and the two engine contract files they include sit
# outside lib/; a key that read only lib/ kept an image of tests/x/lib/isa.x
# current across a change to either.  The caller's KEY-PATHs come last, in
# the order given; a path that is a file is hashed as one.
key="$( { cat "$lib"; find lib tests/x/lib engine/tools/contract -name '*.x' | LC_ALL=C sort | xargs cat; cat tools/dev/image-write.x tools/dev/image-walk.x tools/dev/image-name.x; cat "$engine"; for p in "$@"; do find "$p" -name '*.x' | LC_ALL=C sort | xargs cat; done; } | shasum | cut -d' ' -f1)"
# A library the writer could not name (see the unnameable rule below) is
# remembered by a marker beside the key, so the answer is not re-derived by
# a failed write on every run: the marker holds until the key changes.
skip="$out/$name.unnameable"
if [ -f "$keyf" ] && [ "$(cat "$keyf")" = "$key" ]; then
	if [ -f "$img" ]; then
		echo "image-build: $img is current"
		exit 0
	elif [ -f "$skip" ]; then
		echo "image-build: $lib has unnameable words -- boots from source"
		exit 3
	fi
fi
echo "image-build: writing $img from $lib"
rm -f "$img" "$keyf" "$skip"
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
# call that reaches it; it is not written.  Exit 3 tells a caller building
# the whole set apart from a failed write: this library boots from source.
if ! grep -q 'unnameable: 0' "$out/$name.log"; then
	echo "image-build: $img has unnameable words -- not kept; see $out/$name.log" >&2
	rm -f "$img"
	printf '%s\n' "$key" > "$keyf"
	: > "$skip"
	exit 3
fi
printf '%s\n' "$key" > "$keyf"
