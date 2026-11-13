#!/bin/sh
# tools/tests/cov-spec-runner.sh -- Coverage tool test runner
#
# Runs .spec.md tests for the coverage tool on x-bin-profile, the engine
# build that marks evaluated nodes (-DX_COV) and ships in every release.
# Sources the shared test runner.

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
SPEC_PATH="${SPEC_PATH:-$SCRIPT_DIR/specs/cov}"
X_BIN="$SCRIPT_DIR/../../x-bin-profile"
LANG_LIB="$SCRIPT_DIR/../../lib/x-core.x"

if [ ! -f "$X_BIN" ]; then
    echo "x-bin-profile not found (run: make x-bin-profile)" >&2
    exit 1
fi

. "$SCRIPT_DIR/../../tests/spec-runner.sh"
