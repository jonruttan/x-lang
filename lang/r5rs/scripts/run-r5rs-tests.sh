#!/bin/sh
# run-r5rs-tests.sh -- Run adapted R5RS test suite
#
# Usage: sh lang/r5rs/scripts/run-r5rs-tests.sh

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
cat "$SCRIPT_DIR/../lib/r5rs.x" \
    "$SCRIPT_DIR/r5rs-harness.x" \
    "$SCRIPT_DIR/r5rs-tests.x" \
  | "$SCRIPT_DIR/../../../x" 2>/dev/null
