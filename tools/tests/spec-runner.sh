#!/bin/sh
# tools/tests/spec-runner.sh -- Tool test runner
#
# Runs .spec.md tests for the tools suite.
# Sources the shared test runner.

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
SPEC_PATH="$SCRIPT_DIR/specs"
X_BIN="$SCRIPT_DIR/../../x"
LANG_LIB="$SCRIPT_DIR/../../lib/x-core.x"

. "$SCRIPT_DIR/../../tests/spec-runner.sh"
