#!/bin/sh
# # Computational Expressions in C
#
# ## tests/spec-runner.sh -- Shared Test Runner
#
# @description BDD-style test runner for x-lang personalities
# @author [Jon Ruttan](jonruttan@gmail.com)
# @copyright 2024 Jon Ruttan
# @license MIT No Attribution (MIT-0)
#
#     ., .,
#     {O,O}
#     (   )
#      " "
#
# Usage: Each personality runner sets SPEC_PATH, X_BIN, and LANG_LIB,
#        then sources this file.
#
#   SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
#   SPEC_PATH="$SCRIPT_DIR/specs"
#   X_BIN="$SCRIPT_DIR/../../x"
#   LANG_LIB="$SCRIPT_DIR/../../lib/x.x"
#   . "$SCRIPT_DIR/../spec-runner.sh"

ANSI_RESET="\33[0m"
ANSI_RED="\33[1;31m"
ANSI_GREEN="\33[1;32m"
ANSI_BLUE="\33[1;34m"

TEST_COUNT=0
FAIL_COUNT=0
PENDING_COUNT=0

UNIT_TEXT='\n${ANSI_BLUE}$UNIT${ANSI_RESET}\n'
SUCCESS_TEXT='${ANSI_GREEN}.${ANSI_RESET}'
FAIL_TEXT='\n${ANSI_RED}FAIL: $UNIT: $IT\n  expected: $REQUIRE\n  got:      $VALUE${ANSI_RESET}\n'
PENDING_TEXT='${ANSI_BLUE}p${ANSI_RESET}'
SUMMARY_TEXT='\n\n${SUMMARY_COLOR}${TEST_COUNT} tests, ${FAIL_COUNT} failed, ${PENDING_COUNT} pending${ANSI_RESET}\n'

output() {
  eval "printf '%b' \"$@\""
}

describe() {
  UNIT="$1"
  output "$UNIT_TEXT"
}

it() {
  TEST_COUNT=$((TEST_COUNT+1))
  IT="$1"

  # Pending test (no input/expected).
  if [ $# -lt 3 ]; then
    PENDING_COUNT=$((PENDING_COUNT+1))
    output "$PENDING_TEXT"
    return
  fi

  # Run input through the interpreter.
  # Pipe language library + test expression through the interpreter.
  # The REPL prefixes each line with "> ". Strip prompts, keep only the
  # last result line (ignore intermediate results and the EOF prompt).
  VALUE="$(printf '%s\n' "$2" | cat "$LANG_LIB" - | "$X_BIN" 2>/dev/null | sed 's/^> //' | sed '/^$/d' | tail -1)"
  REQUIRE="$3"

  if [ "$VALUE" = "$REQUIRE" ]; then
    output "$SUCCESS_TEXT"
  else
    FAIL_COUNT=$((FAIL_COUNT+1))
    output "$FAIL_TEXT"
  fi
}

# Source all spec files in parallel.
_TMPDIR=$(mktemp -d)
_N=0
for filename in "$SPEC_PATH"/*.spec.sh; do
  [ -f "$filename" ] || continue
  _I=$_N
  _N=$((_N+1))
  (
    TEST_COUNT=0; FAIL_COUNT=0; PENDING_COUNT=0
    . "$filename"
    printf '%d %d %d\n' "$TEST_COUNT" "$FAIL_COUNT" "$PENDING_COUNT" > "$_TMPDIR/$_I.cnt"
  ) &
done

wait

# Collect counts.
_I=0
while [ "$_I" -lt "$_N" ]; do
  read _T _F _P < "$_TMPDIR/$_I.cnt"
  TEST_COUNT=$((TEST_COUNT + _T))
  FAIL_COUNT=$((FAIL_COUNT + _F))
  PENDING_COUNT=$((PENDING_COUNT + _P))
  _I=$((_I+1))
done
rm -rf "$_TMPDIR"

# Summary.
if [ "$FAIL_COUNT" -gt 0 ]; then
  SUMMARY_COLOR="$ANSI_RED"
else
  SUMMARY_COLOR="$ANSI_GREEN"
fi
output "$SUMMARY_TEXT"

# Exit non-zero on failure.
[ "$FAIL_COUNT" -eq 0 ]
