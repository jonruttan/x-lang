#!/bin/sh
# fetch.sh -- acquire the engine tools/engine/engine.pin.xon names, and print
# the directory it landed in.  `make engine` links that path; nothing else here
# knows about links.
#
#   sh tools/engine/fetch.sh                 acquire per the pin
#   PIN=other.xon sh tools/engine/fetch.sh   read a different pin (the smoke)
#
# SHELL, AND NOT BY HABIT.  This runs before there is an engine to run x with,
# which is the one place in tools/ where the charter's "logic lives in x" cannot
# apply: parsing the pin IS the step that gets us an engine.
#
# WHAT IT GUARANTEES, in the order the rules matter:
#
#   1. A DECLARED ARTIFACT THAT FAILS IS AN ERROR, never a quiet source build.
#      The fallback exists for platforms nobody publishes for -- the Pi, 32-bit
#      -- and firing it on a failed download would turn "the release is broken"
#      into "the build took eleven minutes today" and hide it forever.
#   2. NOTHING IS PUBLISHED UNVERIFIED.  The download lands on a pid-tagged temp
#      path, is digested there, and is renamed into place only if it matches.  A
#      rejected download is quarantined as <dest>.rejected rather than deleted,
#      because the bytes are the evidence.  (x-lang's own Pin fetch learned this
#      as #145: it wrote the final path first, so a rejected amalgam became the
#      booted amalgam.)
#   3. AN EXISTING VALID TREE IS HONOURED.  Same digest, no network.  Offline is
#      the normal case for everyone who has built once.
set -e

cd "$(dirname "$0")/../.."
PIN="${PIN:-tools/engine/engine.pin.xon}"
[ -f "$PIN" ] || { echo "engine: no pin at $PIN" >&2; exit 2; }

say() { echo "engine: $*" >&2; }

digest() {
	if command -v shasum >/dev/null 2>&1; then shasum -a 256 "$1" | cut -d' ' -f1
	else sha256sum "$1" | cut -d' ' -f1; fi
}

# --- the closed vocabulary ---------------------------------------------------
# An unknown form is an error, the same ruling pin.xon's loader follows: a
# manifest that silently ignores what it does not understand cannot be extended
# without wondering which readers obeyed which half of it.
bad=$(sed -n 's/^(\([a-z-]*\)[ )].*/\1/p' "$PIN" | sort -u \
	| grep -vxE 'engine|release|artifact|source' || true)
[ -z "$bad" ] || { echo "engine: unknown form(s) in $PIN: $bad" >&2; exit 2; }

name=$(sed -n 's/^(engine "\([^"]*\)").*/\1/p' "$PIN" | head -1)
release=$(sed -n 's/^(release "\([^"]*\)").*/\1/p' "$PIN" | head -1)
source_url=$(sed -n 's/^(source "\([^"]*\)").*/\1/p' "$PIN" | head -1)
[ -n "$name" ] || { echo "engine: $PIN names no (engine \"...\")" >&2; exit 2; }

# --- which platform is this ---------------------------------------------------
# The contract's spellings, not uname's.  See the pin file's header for why this
# is the one place uname is the right answer.
case "$(uname -s)" in
	Darwin) os=darwin ;;
	Linux)  os=linux ;;
	*BSD)   os=bsd ;;
	*)      os=unknown ;;
esac
case "$(uname -m)" in
	arm64|aarch64)  arch=arm64 ;;
	x86_64|amd64)   arch=x86-64 ;;
	i[3456]86)      arch=i386 ;;
	*)              arch=unknown ;;
esac

row=$(sed -n "s/^(artifact $os $arch \"sha256:\([0-9a-f]*\)\" \"\([^\"]*\)\").*/\1 \2/p" "$PIN" | head -1)

# --- the source arm -----------------------------------------------------------
# Reached ONLY when the pin declares no artifact for this platform.  It says so
# out loud: a build that quietly takes eleven minutes instead of eleven seconds
# should tell you which arm it is on.
if [ -z "$row" ]; then
	if [ -f ext/x-engine-c/Makefile ]; then
		say "no artifact declared for $os/$arch -- building the submodule from source"
		echo "ext/x-engine-c"
		exit 0
	fi
	[ -n "$source_url" ] || {
		echo "engine: no artifact for $os/$arch and no (source \"...\") to build from" >&2
		exit 1; }
	[ -n "$release" ] || {
		echo "engine: no artifact for $os/$arch and no (release \"...\") to clone at" >&2
		exit 1; }
	dest="build/engine-src/$name-$release"
	if [ ! -d "$dest" ]; then
		say "no artifact declared for $os/$arch -- cloning $name $release to build from source"
		mkdir -p "$(dirname "$dest")"
		git clone --depth 1 --branch "$release" --recursive "$source_url" "$dest.tmp.$$" >&2
		mv "$dest.tmp.$$" "$dest"
	fi
	echo "$dest"
	exit 0
fi

want=${row%% *}
url=${row#* }
dest="build/engine/$name-$release-$os-$arch"

# --- already here, and provably the right bytes -------------------------------
if [ -f "$dest/.digest" ] && [ "$(cat "$dest/.digest")" = "$want" ]; then
	echo "$dest"
	exit 0
fi

mkdir -p build/engine
tmp="build/engine/.fetch.$$.tar.gz"
trap 'rm -rf "$tmp" "$tmp.d"' EXIT INT TERM

say "fetching $name $release for $os/$arch"
if command -v curl >/dev/null 2>&1; then
	curl -fsSL "$url" -o "$tmp" || { echo "engine: fetch failed: $url" >&2; exit 1; }
elif command -v wget >/dev/null 2>&1; then
	wget -q "$url" -O "$tmp" || { echo "engine: fetch failed: $url" >&2; exit 1; }
else
	echo "engine: neither curl nor wget is available; fetch $url by hand and" >&2
	echo "  unpack it, then: make X_ENGINE_DIR=/path/to/unpacked" >&2
	exit 1
fi

got=$(digest "$tmp")
if [ "$got" != "$want" ]; then
	mkdir -p "$dest.rejected"
	mv "$tmp" "$dest.rejected/$(basename "$url")"
	echo "engine: DIGEST MISMATCH -- refusing to use this download" >&2
	echo "  url:      $url" >&2
	echo "  expected: $want" >&2
	echo "  got:      $got" >&2
	echo "  the bytes are kept at $dest.rejected for inspection; do not use them" >&2
	exit 1
fi

# Unpack beside the destination and rename ONE directory into place, so a
# consumer never sees a half-extracted tree -- the same publish-by-rename the
# JIT's object cache needed (#391) for the same reason.
rm -rf "$tmp.d"; mkdir -p "$tmp.d"
tar -xzf "$tmp" -C "$tmp.d"
inner=$(ls -d "$tmp.d"/*/ 2>/dev/null | head -1)
[ -n "$inner" ] || { echo "engine: $url unpacked to no directory" >&2; exit 1; }
rm -rf "$dest"
mv "$inner" "$dest"
printf '%s\n' "$want" > "$dest/.digest"
say "verified and unpacked to $dest"
echo "$dest"
