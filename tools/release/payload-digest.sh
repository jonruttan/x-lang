#!/bin/sh
# payload-digest.sh -- one digest over everything a release SHIPS as
# library: the release's PAYLOAD fingerprint.
#
#   sh tools/release/payload-digest.sh          # repo:    lib, apps, build/boot
#   sh tools/release/payload-digest.sh ROOT     # install: ROOT/{lib,apps,boot}
#
# Prints one 64-hex line, nothing else.
#
# WHY THIS EXISTS (#435).  The ISA fingerprint answers "will this amalgam
# run on this engine's C surface?" -- a question about ext/x-eval-c/tools/contract/isa.x,
# which is deliberately fixed and minimal.  It answers NOTHING about which
# release a tree is: isa.x is byte-identical across v0.3.1-rc10, v0.4.0
# and v0.5.0, as are obj-layout.x, base-paths.x and base-layout.x, while
# lib/ moved 83 files between the first two.  A key derived from any of
# those contracts cannot tell two releases apart; a key derived from what
# the release actually ships can, and does so by construction.
#
# The digest is a Merkle root, not a hash of a tarball: each file is
# digested, the "DIGEST  label/path" lines are sorted under LC_ALL=C, and
# the listing itself is digested.  That makes the answer independent of
# directory-walk order, of tar/gzip framing, and of the mtimes and modes a
# copy does not preserve -- and identical whether computed from the repo
# (lib, apps, build/boot) or from an install tree (share/x/{lib,apps,boot}),
# because both are labelled lib/, apps/ and boot/.  `make install` copies
# lib and apps verbatim and proves it with diff -r, so the two agree by
# construction, which is what lets an installed engine and a release
# manifest compare fingerprints at all.
set -u

# Resolve the caller's ROOT before the cd below moves the cwd out from
# under a relative one (`make install DESTDIR=./stage` hands us exactly
# that).
ROOT="${1:-}"
if [ -n "$ROOT" ]; then
	ROOT=$(cd "$ROOT" 2>/dev/null && pwd) \
		|| { echo "payload-digest: no such directory: ${1}" >&2; exit 1; }
fi

cd "$(dirname "$0")/../.." || exit 1

if command -v sha256sum >/dev/null 2>&1; then
	_digest() { sha256sum "$@" | awk '{print $1}'; }
elif command -v shasum >/dev/null 2>&1; then
	_digest() { shasum -a 256 "$@" | awk '{print $1}'; }
else
	echo "payload-digest: no sha256sum or shasum on PATH" >&2; exit 1
fi

if [ -n "$ROOT" ]; then
	set -- "$ROOT/lib" lib "$ROOT/apps" apps "$ROOT/boot" boot
else
	set -- lib lib apps apps build/boot boot
fi

# Validate the whole set BEFORE hashing any of it.  The walk below runs
# inside a command substitution ending in `sort`, whose exit status is the
# one the caller sees -- a `find` that died in there would leave a shorter
# listing and a perfectly clean status, which is a partial payload wearing
# a complete payload's face.  Nothing to hash means nothing to compare, so
# every absence and every irregular entry is a refusal here, up front.
_check() {
	while [ "$#" -gt 0 ]; do
		[ -d "$1" ] || { echo "payload-digest: no such directory: $1" >&2; return 1; }
		# A symlink is neither hashed by `-type f` nor reported by it: it
		# would drop out of the listing without a word, and a payload key
		# that silently omits files is worse than no key.
		if [ -n "$(find "$1" ! -type d ! -type f -print 2>/dev/null | head -1)" ]; then
			echo "payload-digest: $1 holds a non-regular entry (symlink, fifo, socket)" >&2
			find "$1" ! -type d ! -type f -print >&2
			return 1
		fi
		shift 2
	done
}
_check "$@" || exit 1

# The listing: every payload file as "DIGEST  label/relative/path", sorted
# by the whole line under LC_ALL=C so the order is a property of the tree
# rather than of this machine's locale or filesystem.
listing=$(
	while [ "$#" -gt 0 ]; do
		dir=$1; label=$2; shift 2
		find "$dir" -type f -print | while IFS= read -r f; do
			rel=${f#"$dir"/}
			printf '%s  %s/%s\n' "$(_digest "$f")" "$label" "$rel"
		done
	done | LC_ALL=C sort
) || exit 1

# An empty listing would digest to the hash of "" -- a perfectly valid
# 64-hex answer for a tree that shipped nothing.  Refuse it: silence is
# how a payload key becomes a constant.
[ -n "$listing" ] || { echo "payload-digest: no payload files found" >&2; exit 1; }

printf '%s\n' "$listing" | _digest
