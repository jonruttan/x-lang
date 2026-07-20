#!/bin/sh
# spec-example-runner.sh -- run the GENERATED spec.md examples through the
# standard harness (#70 seam 2). tools/spec-examples.sh extracts them from
# docs/spec.md; this personality runner points the shared spec-runner core at
# the generated directory, exactly as doctest-runner.sh does for #16.

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"

X_BIN="${X_BIN:-$SCRIPT_DIR/../../x}"
LANG_LIB="${LANG_LIB:-$SCRIPT_DIR/../../lib/x-core.x}"
SPEC_PATH="$SCRIPT_DIR/../../build/spec-example-specs"

. "$SCRIPT_DIR/../spec-runner.sh"
