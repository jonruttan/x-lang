#!/bin/sh
# # Computational Expressions in C
#
# ## lang/r7rs/tests/spec-runner.sh -- R7RS Personality Test Runner
#
# @description BDD-style test runner for the R7RS Scheme personality
# @author [Jon Ruttan](jonruttan@gmail.com)
# @copyright 2024 Jon Ruttan
# @license MIT No Attribution (MIT-0)
#
#     ., .,
#     {O,O}
#     (   )
#      " "

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
SPEC_PATH="$SCRIPT_DIR/specs"
X_BIN="$SCRIPT_DIR/../../../x"
LANG_LIB="$SCRIPT_DIR/../lib/r7rs-base.x"
READ_FN="%prim-read"

. "$SCRIPT_DIR/../../../tests/spec-runner.sh"
