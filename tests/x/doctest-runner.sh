#!/bin/sh
# doctest-runner.sh -- run the GENERATED doctest specs through the standard
# harness (#16). tools/check/doctest.sh generates one spec from the library's
# (example ...) forms and tools/check/doctest-split.awk cuts it into one file
# per library area under build/doctest-specs; this lang runner points the
# shared spec-runner core at that directory. `make doctest` chains the three.

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"

X_BIN="${X_BIN:-$SCRIPT_DIR/../../x-bin}"
LANG_LIB="$SCRIPT_DIR/../../lib/x-core.x"
SPEC_PATH="${SPEC_PATH:-$SCRIPT_DIR/../../build/doctest-specs}"

. "$SCRIPT_DIR/../spec-runner.sh"
