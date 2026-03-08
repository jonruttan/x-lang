#!/bin/sh
# # Computational Expressions in C
#
# ## tests/x/spec-runner.sh -- x-lang Test Runner
#
# @description BDD-style test runner for the x-lang base language
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
LANG_LIB="$SCRIPT_DIR/../../lib/x.x"

. "$SCRIPT_DIR/../spec-runner.sh"
