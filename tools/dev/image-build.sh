#!/bin/sh
# tools/dev/image-build.sh -- write a state image of a library, if it is stale.
#
#   sh tools/dev/image-build.sh LIB-FILE OUT-DIR [KEY-PATH...]
#       e.g. lib/x-core.x .images
#       e.g. /path/x-awk/tests/lib/harness.gen.x /path/x-awk/tests/lib/.images /path/x-awk/awk
#   IMG_CHECK=1 answers without writing: 0 current, 3 refused (marked), 4 stale
#   or absent.  X_SH names the wrapper (an installed tree's is not ./x.sh).
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
# X_IMG_WHO=1 makes a refused write name the holders of each unnameable word
# (minutes on a dialect-sized heap; the census alone is seconds).
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
# An installed tree has no tests/x/lib; a directory that is not there hashes
# as nothing rather than as an error.
key="$( { cat "$lib"; for d in lib tests/x/lib engine/tools/contract; do [ -d "$d" ] && find "$d" -name '*.x'; done | LC_ALL=C sort | xargs cat; cat tools/dev/image-write.x tools/dev/image-walk.x tools/dev/image-name.x; cat "$engine"; for p in "$@"; do find "$p" -name '*.x' | LC_ALL=C sort | xargs cat; done; } | shasum | cut -d' ' -f1)"
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
# A caller that only wants the answer -- the wrapper, for a bundle whose
# image is its installer's to write -- stops here.
[ -n "${IMG_CHECK:-}" ] && exit 4
echo "image-build: writing $img from $lib"
rm -f "$img" "$keyf" "$skip"
{ printf '(def %%IMG-LIB "%s") (def %%IMG-OUT "%s")\n' "$lib" "$img"; [ -n "${X_IMG_WHO:-}" ] && printf '(def %%IMG-WHO #t)\n'; cat tools/dev/image-write.x; } \
	| sh "${X_SH:-x.sh}" -q --no-image > "$out/$name.log" 2>&1 || true
grep 'objects:\|IMAGE TOTAL\|ERROR\|fault' "$out/$name.log" || true
# A refusal the writer states -- a type it cannot describe, a transient that
# raised in the child -- is exit 3 like an unnameable word: the caller
# boots from source, and the log says why.  The marker holds until the key
# changes, as below.
if grep -q '^image: refused\|^image: clearing a transient raised' "$out/$name.log"; then
	grep '^image: ' "$out/$name.log" >&2
	printf '%s\n' "$key" > "$keyf"
	: > "$skip"
	exit 3
fi
# The writer began, and neither a census nor a refusal followed: the library
# ENDED THE WRITER -- an entry that reads stdin at load read the writer's own
# script, or exited.  The child is told (%image-writing is bound there); a
# lang that loads and stops while it is bound images like any other.
# A raise in the writer itself is the writer's bug, said as such.
if grep -q '^\*\*\* ERROR' "$out/$name.log"; then
	echo "image-build: the writer raised: $(grep '^\*\*\* ERROR' "$out/$name.log" | head -1) -- see $out/$name.log" >&2
	exit 1
fi
# The writer died of a signal: its own bug, or an object it walked into that
# it should have refused, and the log's last lines are the shell's report.
if grep -q 'Segmentation fault\|Bus error\|Killed:\|Abort trap\|Illegal instruction' "$out/$name.log"; then
	echo "image-build: the writer crashed -- $(grep -o 'Segmentation fault\|Bus error\|Killed:[^|]*\|Abort trap\|Illegal instruction' "$out/$name.log" | head -1) -- see $out/$name.log" >&2
	exit 1
fi
# The writer began, and neither a census nor a refusal nor a crash followed:
# the library ENDED THE WRITER -- an entry that reads stdin at load read the
# writer's own script, or exited.  The child is told (%image-writing is
# bound there); a lang that loads and stops while it is bound images like
# any other.
if grep -q '^image: writer begins' "$out/$name.log" && ! grep -q '^objects:' "$out/$name.log"; then
	echo "image: refused -- $lib ended the writer while loading (an entry that reads stdin or exits at load; check %image-writing and load only)" >&2
	printf '%s\n' "$key" > "$keyf"
	: > "$skip"
	exit 3
fi
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
