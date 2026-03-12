#!/bin/sh
# # Computational Expressions in C
#
# ## lang/krn/tests/spec-runner.sh -- Kernel Personality Test Runner
#
# @description BDD-style test runner for the Kernel personality
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
LANG_LIB="$SCRIPT_DIR/../lib/krn-base.x"

. "$SCRIPT_DIR/../../../tests/spec-runner.sh"
