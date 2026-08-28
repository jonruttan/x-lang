#!/bin/sh
# package.sh -- build a relocatable per-platform binary tarball.
#
#   sh tools/release/package.sh [TAG] [OUTDIR]
#     TAG     version label in the name + top dir  (default: dev)
#     OUTDIR  where the tarball lands              (default: build/dist)
#
# Produces, for the host os/arch:
#   OUTDIR/x-<TAG>-<os>-<arch>.tar.gz          the install tree
#   OUTDIR/x-<TAG>-<os>-<arch>.tar.gz.sha256   coreutils-checkable
#
# The tarball is the exact `make install` tree -- bin/x (wrapper),
# libexec/x/x-bin (engine), share/x/{lib,apps,boot,tests} -- under one versioned
# top dir, RELOCATABLE: the wrapper resolves the engine and library from
# its own directory (../libexec, ../share), so it runs wherever it is
# unpacked.  A user adds x-<TAG>/bin to PATH; no compile, no toolchain.
#
# Self-proving: after packing, it EXTRACTS elsewhere and runs the
# unpacked x from an unrelated cwd -- the relocation is asserted, not
# assumed.  On macOS `make install` ad-hoc-signs the engine
# (entitlements.plist); a DOWNLOADED tarball still carries the Gatekeeper
# quarantine bit -- see the release notes' `xattr` line.  Full
# notarization needs a signing identity and is out of scope here.
set -eu

cd "$(dirname "$0")/../.."

TAG="${1:-dev}"
OUT="${2:-build/dist}"

os=$(uname -s | tr 'A-Z' 'a-z')   # darwin | linux
arch=$(uname -m)                  # arm64 | x86_64 | aarch64
name="x-$TAG-$os-$arch"

if command -v sha256sum >/dev/null 2>&1; then
	_sha() { sha256sum "$1"; }
elif command -v shasum >/dev/null 2>&1; then
	_sha() { shasum -a 256 "$1"; }
else
	echo "package: no sha256sum or shasum on PATH" >&2; exit 1
fi

STAGE=$(mktemp -d 2>/dev/null || echo "${TMPDIR:-/tmp}/pkg-stage.$$")
EXTRACT=$(mktemp -d 2>/dev/null || echo "${TMPDIR:-/tmp}/pkg-extract.$$")
mkdir -p "$STAGE" "$EXTRACT"
trap 'rm -rf "$STAGE" "$EXTRACT"' EXIT
fail() { echo "package: FAIL: $1" >&2; exit 1; }

# Stage the install tree under a versioned prefix (no sudo, all in $STAGE).
# `make install` builds the engine + boot amalgams if missing and self-checks
# the library with diff -r.
# X_RELEASE is passed, not derived (#435): the engine and the tree are
# stamped with the tag they SHIP under.  Left to the Makefile's default,
# `git describe` would answer from whatever the runner checked out -- a
# shallow clone, or a tag it never fetched -- and a tarball whose engine
# disagrees with its own release is exactly the confusion the stamp exists
# to end.
make --no-print-directory install PREFIX="/x-$TAG" DESTDIR="$STAGE" X_RELEASE="$TAG" >/dev/null \
	|| fail "make install failed"
[ -x "$STAGE/x-$TAG/bin/x" ]       || fail "no wrapper staged"
[ -x "$STAGE/x-$TAG/libexec/x/x-bin" ] || fail "no engine staged"

# Developer ID sign + notarize the staged engine BEFORE tarring -- only
# when the release workflow provided a real identity (secrets present).
# Unset (the local gate, and any release without notary secrets) leaves
# the ad-hoc signature `make install` applied: today's behaviour, no
# change.  Set: a failure here fails the package -- we never ship a
# binary that was meant to be notarized but wasn't.
if [ -n "${MACOS_SIGN_IDENTITY:-}" ] && [ "$os" = darwin ]; then
	sh tools/release/macos-notarize.sh "$STAGE/x-$TAG/libexec/x/x-bin" \
		|| fail "Developer ID sign + notarize failed"
fi

mkdir -p "$OUT"
TARBALL="$OUT/$name.tar.gz"
tar -czf "$TARBALL" -C "$STAGE" "x-$TAG"

# Prove the tarball relocates: unpack to a fresh root and run from a cwd
# that is neither the repo nor the unpack dir.
tar -xzf "$TARBALL" -C "$EXTRACT"
echo '(display (+ 40 2))(newline)' > "$EXTRACT/hello.x"
out=$( cd / && "$EXTRACT/x-$TAG/bin/x" -f "$EXTRACT/hello.x" 2>/dev/null | tail -1 )
[ "$out" = "42" ] || fail "the packaged x did not run after relocation (got: '$out')"

# ... and by RELATIVE invocation, `./`-spelled.  This proof only ever ran
# the wrapper by absolute path, so x-lang#188 shipped: a `./x-TAG/bin/x`
# call put a `./`-prefixed install root into the boot stream, import
# resolution read that as include-relative, and the boot failed with
# `include: cannot open`.  Absolute and bare-relative spellings both
# worked, so only this exact shape catches it.
out=$( cd "$EXTRACT" && "./x-$TAG/bin/x" -f "$EXTRACT/hello.x" 2>/dev/null | tail -1 )
[ "$out" = "42" ] || fail "the packaged x did not run by relative path (got: '$out')"

# The release stamps must describe THIS tarball, and must be the same facts
# the release manifest published -- the two are built by different CI jobs
# from the same tag, so nothing else compares them.  Recomputing the payload
# digest from the EXTRACTED tree proves the stamp describes the bytes that
# actually shipped (not the staging tree, and not the repo by assumption),
# and comparing it against the repo's proves it equals the manifest's
# (payload ...) row, which release-manifest.sh computes from the repo with
# this same script.  A tarball whose stamp is wrong is a tarball whose
# pairing guard lies, so this fails the package rather than shipping.
_tree="$EXTRACT/x-$TAG/share/x"
[ -f "$_tree/contract/release" ] || fail "no release stamp in the packaged tree"
[ -f "$_tree/contract/payload.sha256" ] || fail "no payload stamp in the packaged tree"
stamped_tag=$(cat "$_tree/contract/release")
[ "$stamped_tag" = "$TAG" ] \
	|| fail "packaged tree is stamped '$stamped_tag', not '$TAG'"
stamped=$(cat "$_tree/contract/payload.sha256")
shipped=$(sh tools/release/payload-digest.sh "$_tree") || fail "payload digest failed"
[ "$stamped" = "$shipped" ] \
	|| fail "payload stamp does not describe the shipped tree ($stamped vs $shipped)"
repo=$(sh tools/release/payload-digest.sh) || fail "payload digest failed"
[ "$stamped" = "$repo" ] \
	|| fail "packaged payload differs from the repo's, so it will differ from the release manifest ($stamped vs $repo)"

# THE SHARED SPEC RUNNER SHIPS, and the wrapper can say where it is.  A
# lang bundle runs its own specs with this runner, locating it as
# "$(x --share-dir)/tests" -- so a tarball missing either half leaves every
# bundle unable to test itself, which is exactly the state the old
# langs rotted in (docs/lang-contract.md).  Checked on the
# EXTRACTED tree, because that is what a user gets.
[ -f "$_tree/tests/spec-runner.sh" ] \
	|| fail "no shared spec runner in the packaged tree"
[ -f "$_tree/tests/spec-runner.awk" ] \
	|| fail "no spec-runner awk harness in the packaged tree"
#
# RUN FROM THE EXTRACT, NOT THE REPO.  The wrapper decides repo-vs-installed
# mode from the CWD (an lib/x.x under it), deliberately -- so an installed x
# invoked inside a checkout reads the checkout, and answering the checkout's
# root is then the honest answer, not a bug.  This gate runs with the repo as
# cwd, so it must step out to ask the packaged tree about itself.
_wrapper="$EXTRACT/x-$TAG/bin/x"
_said=$(cd "$EXTRACT" && "$_wrapper" --share-dir) || fail "x --share-dir failed in the packaged tree"
[ "$_said" = "$(cd "$_tree" && pwd)" ] \
	|| fail "x --share-dir answered '$_said', not the packaged tree"
[ -f "$_said/tests/spec-runner.sh" ] \
	|| fail "x --share-dir names a tree with no spec runner under it"
_eng=$(cd "$EXTRACT" && "$_wrapper" --engine-path) || fail "x --engine-path failed in the packaged tree"
[ -x "$_eng" ] || fail "x --engine-path names no executable engine: $_eng"

# The sidecar names the BARE tarball (so `sha256sum -c` works from OUTDIR).
( cd "$OUT" && _sha "$name.tar.gz" > "$name.tar.gz.sha256" )

echo "package: $TARBALL"
echo "package: $(cat "$OUT/$name.tar.gz.sha256")"
