# 15-lib-logic.spec.sh -- Tests for logic library
# Spec: Section 15 - Lib: Logic

describe 'boolean?'
  it 'true for t' '(boolean? t)' 't'
  it 'true for nil' '(boolean? ())' 't'
  it 'false for number' '(if (boolean? 42) "y" "n")' '"n"'

describe 'default-to'
  it 'returns value when non-nil' '(default-to 0 42)' '42'
  it 'returns default when nil' '(default-to 0 ())' '0'

describe 'until'
  it 'iterates until predicate holds' \
    '(until (fn (x) (> x 10)) inc 1)' '11'

describe 'equal?'
  it 'compares numbers' '(equal? 5 5)' 't'
  it 'compares different numbers' '(if (equal? 5 6) "y" "n")' '"n"'
  it 'compares strings' '(equal? "hi" "hi")' 't'
  it 'compares nil' '(equal? () ())' 't'
