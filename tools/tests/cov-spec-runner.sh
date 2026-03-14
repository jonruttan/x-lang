#!/bin/sh
# tools/tests/cov-spec-runner.sh -- Coverage tool test runner
#
# Runs .spec.md tests for the coverage tool using x-cov binary.
# Sources the shared test runner.

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
SPEC_PATH="$SCRIPT_DIR/specs/cov"
X_BIN="$SCRIPT_DIR/../../x-cov"
LANG_LIB="$SCRIPT_DIR/../../lib/x-core.x"

if [ ! -f "$X_BIN" ]; then
    echo "x-cov not found (run: make x-cov)" >&2
    exit 1
fi

. "$SCRIPT_DIR/../../tests/spec-runner.sh"
