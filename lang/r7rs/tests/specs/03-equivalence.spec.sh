# 03-equivalence.spec.sh -- R7RS 6.1 Equivalence predicates

describe 'eqv?'
  it 'eqv? same boolean true' \
    '(eqv? #t #t)' 't'
  it 'eqv? same boolean false' \
    '(eqv? #f #f)' 't'
  it 'eqv? same symbol' \
    '(eqv? (quote a) (quote a))' 't'
  it 'eqv? different symbols' \
    '(null? (eqv? (quote a) (quote b)))' 't'
  it 'eqv? same number' \
    '(eqv? 42 42)' 't'
  it 'eqv? different numbers' \
    '(null? (eqv? 1 2))' 't'
  it 'eqv? same char' \
    '(eqv? #\a #\a)' 't'
  it 'eqv? different chars' \
    '(null? (eqv? #\a #\b))' 't'
  it 'eqv? empty lists' \
    '(eqv? () ())' 't'
  it 'eqv? string to symbol' \
    '(null? (eqv? "a" (quote a)))' 't'
  it 'eqv? number to char' \
    '(null? (eqv? 65 #\A))' 't'

describe 'eq?'
  it 'eq? same symbol' \
    '(eq? (quote a) (quote a))' 't'
  it 'eq? different symbols' \
    '(null? (eq? (quote a) (quote b)))' 't'
  it 'eq? empty lists' \
    '(eq? () ())' 't'
  it 'eq? booleans' \
    '(eq? #t #t)' 't'

describe 'equal?'
  it 'equal? same lists' \
    '(equal? (list 1 2 3) (list 1 2 3))' 't'
  it 'equal? different lists' \
    '(null? (equal? (list 1 2) (list 1 3)))' 't'
  it 'equal? nested lists' \
    '(equal? (list 1 (list 2 3)) (list 1 (list 2 3)))' 't'
  it 'equal? strings' \
    '(equal? "abc" "abc")' 't'
  it 'equal? different strings' \
    '(null? (equal? "abc" "abd"))' 't'
  it 'equal? numbers' \
    '(equal? 42 42)' 't'
  it 'equal? mixed types' \
    '(null? (equal? 1 "1"))' 't'
  it 'equal? dotted pairs' \
    '(equal? (cons 1 2) (cons 1 2))' 't'
  it 'equal? deep nested' \
    '(equal? (list (list 1 (list 2)) (list 3)) (list (list 1 (list 2)) (list 3)))' 't'
  it 'equal? chars' \
    '(equal? #\a #\a)' 't'
