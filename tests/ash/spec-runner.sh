#!/bin/sh
# # Computational Expressions in C
#
# ## tests/ash/spec-runner.sh -- ASH Shell Personality Test Runner
#
# @description BDD-style test runner for ash shell tokenizer and parser
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
LANG_LIB="$SCRIPT_DIR/../../lang/ash/lib/ash.x"

. "$SCRIPT_DIR/../spec-runner.sh"
