#!/bin/sh
# tools/dev/image-build.sh -- write a state image of a library, if it is stale.
#
#   sh tools/dev/image-build.sh LIB-FILE OUT-DIR [KEY-PATH...]
#       e.g. lib/x-core.x .images
#       e.g. /path/x-awk/tests/lib/harness.gen.x /path/x-awk/tests/lib/.images /path/x-awk/awk
#   IMG_CHECK=1 answers without writing: 0 current, 3 refused (marked), 4 stale
#   or absent.  X_SH names the wrapper; unset, one is found -- ./x.sh in a
#   checkout, else <prefix>/bin/x beside an install, else the x on PATH.
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
#  A KEY-PATH IS A BUNDLE'S SOURCE, AND ONLY THE BUNDLE KNOWS HOW IT IS SPELT.
# This globbed '*.x' and nothing else, so a lang whose modules are written in
# anything else had them silently outside its own image key: editing one left
# the key unchanged, this script answered "is current", and the suite went on
# testing the library that was there BEFORE, out of the image, while a
# from-source run tested the one on disk.  Both legs green, at two different
# libraries -- the stale image the note above calls worse than a slow suite,
# and the one thing a diff cannot show you.
#
# THE PLATFORM STILL KNOWS ONLY ITS OWN SPELLING, and the default below names
# .x alone.  IMG_KEY_EXT is how a BUNDLE says what else its modules are written
# in: the caller that arms a tree is the only thing that can know, so nothing
# here has to carry a lang's vocabulary or be edited when a new one arrives.
#
# A KEY-PATH THAT IS A FILE IS HASHED AS ONE, which the note above has claimed
# since it was written and which `find FILE -name '*.x'` never did for anything
# but a .x: a module handed over directly hashed as NOTHING, in silence.
_caller_key() {
	for p in "$@"; do
		if [ -f "$p" ]; then
			cat "$p"
		else
			{ for e in ${IMG_KEY_EXT:-x}; do find "$p" -name "*.$e"; done; } \
				| LC_ALL=C sort | xargs cat
		fi
	done
}
key="$( { cat "$lib"; for d in lib tests/x/lib engine/tools/contract; do [ -d "$d" ] && find "$d" -name '*.x'; done | LC_ALL=C sort | xargs cat; cat tools/dev/image-write.x tools/dev/image-walk.x tools/dev/image-name.x; cat "$engine"; _caller_key "$@"; } | shasum | cut -d' ' -f1)"
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
# ONLY THE WRITE NEEDS A WRAPPER, so it is found here rather than at the top:
# a check answers from the key alone and must not fail for want of an x.
#
# X_SH IS NAMED BY THE WRAPPER AND BY NOBODY ELSE.  Six lang bundles call this
# script from their spec runners and not one of them sets it, so from an
# INSTALLED tree -- which has no ./x.sh -- every one of them wrote no image at
# all: `sh: x.sh: No such file or directory`, in the log beside the image that
# nobody reads, and a suite that quietly booted from source at ten times the
# cost.  A default that only works in a checkout is not a default.
if [ -z "${X_SH:-}" ]; then
	if [ -f "$root/x.sh" ]; then
		X_SH="$root/x.sh"
	elif [ -x "$root/../../bin/x" ]; then
		# An install: the tree is <prefix>/share/x and the wrapper
		# <prefix>/bin/x.
		X_SH="$root/../../bin/x"
	else
		X_SH="$(command -v x 2>/dev/null || true)"
	fi
	[ -n "$X_SH" ] || {
		echo "image-build: no x wrapper found for the writer -- set X_SH to one" >&2
		exit 2
	}
fi
echo "image-build: writing $img from $lib"
rm -f "$img" "$keyf" "$skip"
# THE WRITER RUNS ON HELIUM, booted through the wrapper -- and that boot is
# most of a write.  It ran with --no-image, from source every time, so that a
# host missing its own image could not write one and land back here: 2.3s of
# a 5.7s write on arm64, 29 times over in `make images`, once per pinned
# project's first boot.  X_IMAGE_NO_WRITE is the mode that answers the
# recursion without the source boot: a current image is used (the same helium
# in 0.4s), a stale or absent one is neither written nor used.  Measured
# 2026-09-12: an x.x write 3.7s from 5.7.
{ printf '(def %%IMG-LIB "%s") (def %%IMG-OUT "%s")\n' "$lib" "$img"; [ -n "${X_IMG_WHO:-}" ] && printf '(def %%IMG-WHO #t)\n'; cat tools/dev/image-write.x; } \
	| X_IMAGE_NO_WRITE=1 sh "$X_SH" -q > "$out/$name.log" 2>&1 || true
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
