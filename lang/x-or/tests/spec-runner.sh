#!/bin/sh
# lang/or/tests/spec-runner.sh -- x/or Personality Test Runner

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
SPEC_PATH="$SCRIPT_DIR/specs"
X_BIN="$SCRIPT_DIR/../../../x"
LANG_LIB="$SCRIPT_DIR/../lib/or-base.x"

. "$SCRIPT_DIR/../../../tests/spec-runner.sh"
