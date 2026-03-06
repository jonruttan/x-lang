SPEC_PATH='specs'
RS_BIN='./rs'

ANSI_RESET="\33[0m"
ANSI_RED="\33[1;31m"
ANSI_GREEN="\33[1;32m"
ANSI_BLUE="\33[1;34m"

TEST_COUNT=0
FAIL_COUNT=0
PENDING_COUNT=0

#SUCCESS_TEXT='.'
#FAIL_TEXT='Failed $UNIT unit: it $IT, returned $VALUE instead of $REQUIRE'
UNIT_TEXT='\\nUnit $UNIT\\n'
SUCCESS_TEXT='${ANSI_GREEN}.${ANSI_RESET}'
FAIL_TEXT='\\n${ANSI_RED}Failed $UNIT unit: it $IT, returned $VALUE instead of $REQUIRE${ANSI_RESET}\\n'
PENDING_TEXT='\\n${ANSI_BLUE}Pending: $IT${ANSI_RESET}\\n'
SUMMARY_TEXT='\\n\\nExecuted ${TEST_COUNT} tests, ${PENDING_COUNT} pending, ${FAIL_COUNT} failing\\n'

output() {
  eval "echo -n $@"
}

# NOTE: Nesting isn't handled
define() {
  UNIT=$1
  output "$UNIT_TEXT"
}

it() {
  TEST_COUNT=$((TEST_COUNT+1))
  IT=$1
  if [ -e "$2" ]; then
    PENDING_COUNT=$((PENDING_COUNT+1))
    output $PENDING_TEXT
    return
  fi
  VALUE="$(echo "$2" | $RS_BIN  | sed -e 's/\\/\\\\/g')"
  REQUIRE=$3
  if [ $? -eq 0 -a "$VALUE" = "$REQUIRE" ]; then
    output $SUCCESS_TEXT
  else
    FAIL_COUNT=$((FAIL_COUNT+1))
    output $FAIL_TEXT
  fi
}

for filename in $SPEC_PATH/*.spec.sh; do
  . $filename
done

output $SUMMARY_TEXT
