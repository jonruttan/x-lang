#!/bin/sh
SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
SPEC_PATH="$SCRIPT_DIR/specs"
X_BIN="$SCRIPT_DIR/../../../x"
LANG_LIB="$SCRIPT_DIR/../lib/sweet.x"
. "$SCRIPT_DIR/../../../tests/spec-runner.sh"
