# 05-booleans.spec.sh -- R7RS 6.3 Booleans

describe 'boolean?'
  it 'boolean? on true' \
    '(boolean? #t)' 't'
  it 'boolean? on false' \
    '(boolean? #f)' 't'
  it 'boolean? on number' \
    '(null? (boolean? 0))' 't'
  it 'boolean? on string' \
    '(null? (boolean? ""))' 't'
  it 'boolean? on nil' \
    '(boolean? ())' 't'

describe 'not'
  it 'not true' \
    '(null? (not #t))' 't'
  it 'not false' \
    '(not #f)' 't'
  it 'not 3' \
    '(null? (not 3))' 't'
  it 'not nil' \
    '(not ())' 't'

describe 'boolean=?'
  it 'boolean=? both true' \
    '(boolean=? #t #t)' 't'
  it 'boolean=? both false' \
    '(boolean=? #f #f)' 't'
  it 'boolean=? true false' \
    '(null? (boolean=? #t #f))' 't'
  it 'boolean=? false true' \
    '(null? (boolean=? #f #t))' 't'
