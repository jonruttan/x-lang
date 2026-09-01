#!/bin/sh
# bump-pin.sh -- point tools/engine/engine.pin.xon at a published release.
#
#   sh tools/engine/bump-pin.sh vX.Y.Z
#
# The manual half of a release fan-out this replaces: open the release
# page, copy each platform's digest out of its .sha256 sidecar, paste
# them into the pin without transposing.  This script rewrites the
# (release ...) row and every (artifact ...) row's digest and URL from
# the sidecars directly.
#
# THE RULES, same ones fetch.sh enforces on the way down:
#
#   1. DIGESTS COME FROM THE SIDECARS, never computed here.  A pin that
#      hashes what it downloaded would agree with itself no matter what
#      arrived.
#   2. EVERY DECLARED PLATFORM MUST BE IN THE RELEASE.  A missing sidecar
#      is an error, never a silently dropped artifact row: a release that
#      lost a platform must not be able to disguise itself as a pin bump.
#   3. THE PIN IS REPLACED WHOLE OR NOT AT ALL.  Rows rewrite into a temp
#      copy; the pin is overwritten only after every row succeeded.
#
# The result is a working-tree edit: review it, run `make engine` to
# prove the fetch, commit.  This script does not touch git.
set -e

cd "$(dirname "$0")/../.."
PIN=tools/engine/engine.pin.xon
TAG="${1:?usage: sh tools/engine/bump-pin.sh vX.Y.Z}"

name=$(sed -n 's/^(engine "\([^"]*\)").*/\1/p' "$PIN" | head -1)
source_url=$(sed -n 's/^(source "\([^"]*\)").*/\1/p' "$PIN" | head -1)
[ -n "$name" ] || { echo "bump-pin: $PIN has no (engine \"...\") row" >&2; exit 2; }
[ -n "$source_url" ] || { echo "bump-pin: $PIN has no (source \"...\") row" >&2; exit 2; }
base="${source_url%.git}/releases/download/$TAG"

# The declared platforms, in the pin's own spellings (fetch.sh's parser).
rows=$(awk '/^\(artifact[ \t]/ {
	line = $0; sub(/;.*/, "", line); gsub(/[()"]/, " ", line)
	split(line, f, /[ \t]+/); print f[3], f[4]
}' "$PIN")
[ -n "$rows" ] || { echo "bump-pin: $PIN declares no (artifact ...) rows" >&2; exit 2; }

tmp="$PIN.bump.$$"
sed "s|^(release \"[^\"]*\")|(release \"$TAG\")|" "$PIN" > "$tmp"

for platform in $(echo "$rows" | tr ' ' '/'); do
	os=${platform%/*}
	arch=${platform#*/}
	asset="$name-$TAG-$os-$arch.tar.gz"
	url="$base/$asset"
	sidecar=$(curl -fsSL "$url.sha256") || {
		echo "bump-pin: no sidecar for $os/$arch at $url.sha256" >&2
		echo "  the pin declares this platform; the release must ship it" >&2
		rm -f "$tmp"; exit 1
	}
	hex=$(echo "$sidecar" | awk '{print $1}')
	case "$hex" in
	*[!0-9a-f]* | "")
		echo "bump-pin: sidecar for $os/$arch is not a sha256: $hex" >&2
		rm -f "$tmp"; exit 1
		;;
	esac
	# Keep the row's own column alignment: everything up to the first
	# quote survives, the quoted pair is replaced.
	awk -v os="$os" -v arch="$arch" -v rep="\"sha256:$hex\" \"$url\")" '
		/^\(artifact[ \t]/ {
			line = $0; sub(/;.*/, "", line); gsub(/[()"]/, " ", line)
			split(line, f, /[ \t]+/)
			if (f[3] == os && f[4] == arch) {
				print substr($0, 1, index($0, "\"") - 1) rep
				next
			}
		}
		{ print }' "$tmp" > "$tmp.2" && mv "$tmp.2" "$tmp"
done

mv "$tmp" "$PIN"
echo "bump-pin: $PIN now names $TAG"
grep -n "^(release\|^(artifact" "$PIN"
