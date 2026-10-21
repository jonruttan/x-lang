#!/bin/sh
# provide-names.sh -- no provide list under lib/ names a %-private.
#
# The scan is the lang kit's (tools/lang-kit/provide-names.sh), which holds a
# bundle to the same rule; this runs it over the library.
#
# Usage: sh tools/check/provide-names.sh [FILE...]; without arguments it
# scans every .x under lib/.
set -u
cd "$(dirname "$0")/../.."
# shellcheck disable=SC2046,SC2086
exec sh tools/lang-kit/provide-names.sh ${*:-$(find lib -name '*.x' | sort)}
