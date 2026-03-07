# # Computational Expressions in C
#
# ## tests/scm/spec-runner.sh -- Scheme Personality Test Runner
#
# @description BDD-style test runner for the Scheme personality
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
SCM_LIB="$SCRIPT_DIR/../../lib/scm.x"

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
  eval "printf \"$@\""
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

  # Run input through the Scheme personality.
  # Pipe scm.x library + test expression through the interpreter.
  VALUE="$(printf '%s\n' "$2" | cat "$SCM_LIB" - | "$X_BIN" 2>/dev/null | sed 's/^> //' | sed '/^$/d' | tail -1)"
  REQUIRE="$3"

  if [ "$VALUE" = "$REQUIRE" ]; then
    output "$SUCCESS_TEXT"
  else
    FAIL_COUNT=$((FAIL_COUNT+1))
    output "$FAIL_TEXT"
  fi
}

# Source all spec files.
for filename in "$SPEC_PATH"/*.spec.sh; do
  [ -f "$filename" ] || continue
  . "$filename"
done

# Summary.
if [ "$FAIL_COUNT" -gt 0 ]; then
  SUMMARY_COLOR="$ANSI_RED"
else
  SUMMARY_COLOR="$ANSI_GREEN"
fi
output "$SUMMARY_TEXT"

# Exit non-zero on failure.
[ "$FAIL_COUNT" -eq 0 ]
