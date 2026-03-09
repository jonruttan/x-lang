# 06-lists.spec.sh -- R7RS 6.4 Pairs and lists

describe 'pair basics'
  it 'cons creates pair' \
    '(cons 1 2)' '(1 . 2)'
  it 'cons with list' \
    '(cons 1 (list 2 3))' '(1 2 3)'
  it 'car of cons' \
    '(car (cons 1 2))' '1'
  it 'cdr of cons' \
    '(cdr (cons 1 2))' '2'
  it 'pair? on pair' \
    '(pair? (cons 1 2))' 't'
  it 'pair? on list' \
    '(pair? (list 1 2))' 't'
  it 'pair? on number' \
    '(null? (pair? 42))' 't'
  it 'pair? on nil' \
    '(null? (pair? ()))' 't'

describe 'list constructor'
  it 'list creates list' \
    '(list 1 2 3)' '(1 2 3)'
  it 'list single element' \
    '(list 42)' '(42)'
  it 'list empty' \
    '(null? (list))' 't'

describe 'list predicates'
  it 'list? on proper list' \
    '(list? (list 1 2 3))' 't'
  it 'list? on empty' \
    '(list? ())' 't'
  it 'list? on dotted pair' \
    '(null? (list? (cons 1 2)))' 't'
  it 'list? on atom' \
    '(null? (list? 42))' 't'
  it 'null? on nil' \
    '(null? ())' 't'
  it 'null? on list' \
    '(null? (null? (list 1)))' 't'

describe 'make-list'
  it 'make-list with fill' \
    '(make-list 3 0)' '(0 0 0)'
  it 'make-list with value' \
    '(make-list 4 (quote x))' '(x x x x)'
  it 'make-list zero length' \
    '(null? (make-list 0 1))' 't'

describe 'list operations'
  it 'length' \
    '(length (list 1 2 3))' '3'
  it 'length empty' \
    '(length ())' '0'
  it 'append two lists' \
    '(append (list 1 2) (list 3 4))' '(1 2 3 4)'
  it 'append empty' \
    '(null? (append () ()))' 't'
  it 'append nested' \
    '(append (list 1) (append (list 2) (list 3)))' '(1 2 3)'
  it 'reverse' \
    '(reverse (list 1 2 3))' '(3 2 1)'
  it 'reverse empty' \
    '(null? (reverse ()))' 't'

describe 'list access'
  it 'list-ref first' \
    '(list-ref (list 10 20 30) 0)' '10'
  it 'list-ref last' \
    '(list-ref (list 10 20 30) 2)' '30'
  it 'list-tail' \
    '(list-tail (list 1 2 3 4) 2)' '(3 4)'
  it 'list-tail zero' \
    '(list-tail (list 1 2 3) 0)' '(1 2 3)'

describe 'list-copy'
  it 'list-copy proper list' \
    '(list-copy (list 1 2 3))' '(1 2 3)'
  it 'list-copy is equal' \
    '(equal? (list-copy (list 1 2 3)) (list 1 2 3))' 't'
  it 'list-copy empty' \
    '(null? (list-copy ()))' 't'

describe 'member'
  it 'member finds element' \
    '(member 3 (list 1 2 3 4 5))' '(3 4 5)'
  it 'member not found' \
    '(null? (member 6 (list 1 2 3)))' 't'

describe 'memq'
  it 'memq finds symbol' \
    '(memq (quote b) (list (quote a) (quote b) (quote c)))' '(b c)'
  it 'memq not found' \
    '(null? (memq (quote z) (list (quote a) (quote b))))' 't'

describe 'assoc'
  it 'assoc finds key' \
    '(assoc (quote b) (list (list (quote a) 1) (list (quote b) 2) (list (quote c) 3)))' '(b 2)'
  it 'assoc not found' \
    '(null? (assoc (quote z) (list (list (quote a) 1))))' 't'

describe 'assq'
  it 'assq finds key' \
    '(assq (quote b) (list (list (quote a) 1) (list (quote b) 2)))' '(b 2)'
  it 'assq not found' \
    '(null? (assq (quote z) (list (list (quote a) 1))))' 't'
