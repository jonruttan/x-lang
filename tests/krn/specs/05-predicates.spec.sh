# 05-predicates.spec.sh -- Kernel predicates and numeric operations

describe 'Kernel predicates'
  it 'operative?' \
    '(operative? ($vau (x) e x))' 't'
  it 'operative? false on applicative' \
    '(null? (operative? ($lambda (x) x)))' 't'
  it 'applicative?' \
    '(applicative? ($lambda (x) x))' 't'
  it 'applicative? false on number' \
    '(null? (applicative? 42))' 't'
  it 'boolean? on #t' \
    '(boolean? #t)' 't'
  it 'boolean? on #f' \
    '(boolean? #f)' 't'
  it 'boolean? false' \
    '(null? (boolean? 42))' 't'
  it 'inert? on #inert' \
    '(inert? #inert)' 't'

describe 'number predicates'
  it 'zero?' \
    '(zero? 0)' 't'
  it 'zero? false' \
    '(null? (zero? 1))' 't'
  it 'positive?' \
    '(positive? 5)' 't'
  it 'negative?' \
    '(negative? (- 0 3))' 't'
  it 'even?' \
    '(even? 4)' 't'
  it 'even? false' \
    '(null? (even? 3))' 't'
  it 'odd?' \
    '(odd? 3)' 't'
  it 'odd? false' \
    '(null? (odd? 4))' 't'

describe 'numeric operations'
  it 'abs positive' \
    '(abs 5)' '5'
  it 'abs negative' \
    '(abs (- 0 5))' '5'
  it 'min' \
    '(min 3 7)' '3'
  it 'max' \
    '(max 3 7)' '7'
