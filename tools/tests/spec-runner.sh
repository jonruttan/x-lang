#!/bin/sh
# tools/tests/spec-runner.sh -- Tool test runner
#
# Runs .spec.md tests for the tools suite.
# Sources the shared test runner.

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
SPEC_PATH="${SPEC_PATH:-$SCRIPT_DIR/specs}"
X_BIN="$SCRIPT_DIR/../../x-bin"
LANG_LIB="$SCRIPT_DIR/../../lib/x-core.x"

# Top-level specs only: specs/cov/ needs the -DX_COV engine and is owned
# by cov-spec-runner.sh.  No explicit args = name them here (the shared
# runner treats arguments as the exact spec list, #222).
[ $# -eq 0 ] && set -- "$SPEC_PATH"/*.spec.md

. "$SCRIPT_DIR/../../tests/spec-runner.sh"
