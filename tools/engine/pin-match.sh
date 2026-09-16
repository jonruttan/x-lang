#!/bin/sh
# pin-match.sh -- refuse an engine directory the pin does not name.
#
# A tree linked to the wrong engine BUILDS, BOOTS and passes the whole spec
# suite.  What breaks is writing a STATE IMAGE: the image reader takes its
# root names from the engine's own tools/contract/base-layout.x, and a
# contract of a different age names a root the image does not carry.  The
# failure surfaces as `root-not-in-image` and `image load failed`, neither of
# which mentions the engine, and `make check-seam` passes anyway while a
# cached image is current -- so the first honest signal can arrive days after
# the link was made, pointing at whatever was edited last.
#
# The link is where that is cheap to catch, so it is caught here.
#
# A directory whose name carries no version is left alone: an engine checkout
# under development has no release to compare against.  X_ENGINE_ANY=1 skips
# the check, which is what to pass when trying an engine before its pin moves.
set -eu

dir=${1:?usage: pin-match.sh ENGINE-DIR [PIN-FILE]}
pin=${2:-tools/engine/engine.pin.xon}

if [ -n "${X_ENGINE_ANY:-}" ]; then exit 0; fi
if [ ! -f "$pin" ]; then exit 0; fi

release=$(sed -n 's/^(release "\([^"]*\)").*/\1/p' "$pin" | head -1)
if [ -z "$release" ]; then exit 0; fi

# The version a release artifact or a source clone carries in its directory
# name -- x-engine-c-v0.2.11-darwin-arm64, x-engine-c-v0.2.11.  Digits and
# dots only: a class that admitted letters or dashes would swallow the
# platform suffix and call every artifact a mismatch.
have=$(basename "$dir" | sed -n 's/.*-\(v[0-9][0-9.]*\).*/\1/p')
if [ -z "$have" ]; then exit 0; fi
if [ "$have" = "$release" ]; then exit 0; fi

echo "engine: $(basename "$dir") is $have, and $pin names $release." >&2
echo "" >&2
echo "A tree on the wrong engine builds, boots and passes the specs; what" >&2
echo "fails is writing a state image, as \`root-not-in-image\` rather than as" >&2
echo "anything naming the engine." >&2
echo "" >&2
echo "  make engine              acquire and link what the pin names" >&2
echo "  X_ENGINE_ANY=1 make ...  link this one anyway" >&2
exit 1
