#!/bin/sh
SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
SPEC_PATH="$SCRIPT_DIR/specs"
X_BIN="$SCRIPT_DIR/../../../x"
LANG_LIB="$SCRIPT_DIR/../lib/sweet-base.x"
REPL_CMD=" "
READ_FN="%test-read"
. "$SCRIPT_DIR/../../../tests/spec-runner.sh"
