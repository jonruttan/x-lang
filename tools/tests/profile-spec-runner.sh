#!/bin/sh
# tools/tests/profile-spec-runner.sh -- Profiling tool test runner
#
# Runs .spec.md tests for x/tool/profile's eval counts on x-bin-profile: an
# engine without X_PROFILE never writes the count.
# Sources the shared test runner.

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
SPEC_PATH="${SPEC_PATH:-$SCRIPT_DIR/specs/profile}"
X_BIN="$SCRIPT_DIR/../../x-bin-profile"
LANG_LIB="$SCRIPT_DIR/../../lib/x-core.x"

if [ ! -f "$X_BIN" ]; then
    echo "x-bin-profile not found (run: make x-bin-profile)" >&2
    exit 1
fi

. "$SCRIPT_DIR/../../tests/spec-runner.sh"
