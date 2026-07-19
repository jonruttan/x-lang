#!/bin/sh
# doctest-runner.sh -- run the GENERATED doctest spec through the standard
# harness (#16). tools/doctest.sh generates build/doctest-specs/doctests.spec.md
# from the library's (example ...) forms; this personality runner points the
# shared spec-runner core at that directory. `make doctest` chains the two.

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"

X_BIN="${X_BIN:-$SCRIPT_DIR/../../x}"
LANG_LIB="$SCRIPT_DIR/../../lib/x-core.x"
SPEC_PATH="$SCRIPT_DIR/../../build/doctest-specs"

. "$SCRIPT_DIR/../spec-runner.sh"
