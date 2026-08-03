#!/bin/sh
# macos-notarize.sh -- Developer ID sign + notarize a macOS binary.
#
#   sh tools/macos-notarize.sh <path-to-binary>
#
# Re-signs the binary (replacing package.sh's ad-hoc signature) with a
# real Developer ID Application identity under the HARDENED RUNTIME --
# which notarization requires, and which the JIT survives only because
# entitlements.plist declares com.apple.security.cs.allow-jit /
# allow-unsigned-executable-memory -- then submits it to Apple's notary
# service and waits for a verdict.
#
# CI-only, credentials-only: package.sh calls this ONLY when
# MACOS_SIGN_IDENTITY is set (the release workflow sets it after importing
# the cert).  Without that env it is never invoked, so the local gate and
# the no-secrets release path stay ad-hoc-signed exactly as before.
#
# Env (all set by the release workflow from GitHub secrets -- never seen
# by anything but the runner):
#   MACOS_SIGN_IDENTITY     "Developer ID Application: Name (TEAMID)"
#   MACOS_NOTARY_KEY_PATH   path to the App Store Connect API .p8 key file
#   MACOS_NOTARY_KEY_ID     the key's Key ID
#   MACOS_NOTARY_ISSUER_ID  the key's Issuer ID
#   ENTITLEMENTS            entitlements plist (default: ./entitlements.plist)
#
# A .tar.gz cannot carry a stapled ticket (you can only staple a
# bundle/dmg/pkg), so none is stapled: the ticket lives in Apple's
# database and Gatekeeper verifies the signed binary online on first run.
set -eu

BIN="${1:?usage: macos-notarize.sh <binary>}"
ENTITLEMENTS="${ENTITLEMENTS:-entitlements.plist}"

: "${MACOS_SIGN_IDENTITY:?MACOS_SIGN_IDENTITY not set}"
: "${MACOS_NOTARY_KEY_PATH:?MACOS_NOTARY_KEY_PATH not set -- notarization needs the API key}"
: "${MACOS_NOTARY_KEY_ID:?MACOS_NOTARY_KEY_ID not set}"
: "${MACOS_NOTARY_ISSUER_ID:?MACOS_NOTARY_ISSUER_ID not set}"
[ -f "$BIN" ] || { echo "macos-notarize: no such binary: $BIN" >&2; exit 1; }
[ -f "$ENTITLEMENTS" ] || { echo "macos-notarize: no entitlements: $ENTITLEMENTS" >&2; exit 1; }

echo "macos-notarize: signing $BIN (Developer ID, hardened runtime)"
codesign --force --timestamp --options runtime \
	--entitlements "$ENTITLEMENTS" \
	--sign "$MACOS_SIGN_IDENTITY" "$BIN"
# --strict: a bad signature must fail here, not at the user's Gatekeeper.
codesign --verify --strict --verbose=2 "$BIN"

WORK=$(mktemp -d)
trap 'rm -rf "$WORK"' EXIT
ZIP="$WORK/engine.zip"
# ditto is Apple's blessed zipper for notarization submissions.
/usr/bin/ditto -c -k --keepParent "$BIN" "$ZIP"

echo "macos-notarize: submitting to the notary service (waiting for the verdict)"
xcrun notarytool submit "$ZIP" \
	--key "$MACOS_NOTARY_KEY_PATH" \
	--key-id "$MACOS_NOTARY_KEY_ID" \
	--issuer "$MACOS_NOTARY_ISSUER_ID" \
	--wait --output-format json > "$WORK/result.json"

# Parse without assuming jq: the final object carries "status":"Accepted".
status=$(grep -o '"status":"[^"]*"' "$WORK/result.json" | head -1 | sed 's/.*:"//;s/"//')
sub_id=$(grep -o '"id":"[^"]*"' "$WORK/result.json" | head -1 | sed 's/.*:"//;s/"//')
echo "macos-notarize: status=$status id=$sub_id"

if [ "$status" != "Accepted" ]; then
	echo "macos-notarize: NOT accepted -- fetching the notary log" >&2
	[ -n "$sub_id" ] && xcrun notarytool log "$sub_id" \
		--key "$MACOS_NOTARY_KEY_PATH" \
		--key-id "$MACOS_NOTARY_KEY_ID" \
		--issuer "$MACOS_NOTARY_ISSUER_ID" >&2 || true
	exit 1
fi

echo "macos-notarize: accepted (ticket lives in Apple's DB; Gatekeeper checks online -- no staple on a tarball)"
