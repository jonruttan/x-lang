#!/bin/sh
# # Computational Expressions in C
#
# ## tests/r7rs/spec-runner.sh -- R7RS Personality Test Runner
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
X_BIN="$SCRIPT_DIR/../../x"
LANG_LIB="$SCRIPT_DIR/../../lang/r7rs/lib/r7rs.x"

. "$SCRIPT_DIR/../spec-runner.sh"
