# 04-lists.spec.sh -- List operations

describe 'cons / car / cdr'
  it 'cons creates dotted pair' \
    '(cons 1 2)' '(1 . 2)'
  it 'cons with list' \
    '(cons 1 (list 2 3))' '(1 2 3)'
  it 'car of cons' \
    '(car (cons 1 2))' '1'
  it 'cdr of cons' \
    '(cdr (cons 1 2))' '2'
  it 'car of list' \
    '(car (list 10 20 30))' '10'
  it 'cdr of list' \
    '(cdr (list 10 20 30))' '(20 30)'

describe 'accessors'
  it 'cadr' \
    '(cadr (list 1 2 3))' '2'
  it 'caddr' \
    '(caddr (list 1 2 3))' '3'
  it 'caar' \
    '(caar (list (list 1 2) 3))' '1'
  it 'cdar' \
    '(cdar (list (list 1 2) 3))' '(2)'
  it 'cddr' \
    '(cddr (list 1 2 3 4))' '(3 4)'

describe 'list constructor'
  it 'list creates list' \
    '(list 1 2 3)' '(1 2 3)'
  it 'list with single element' \
    '(list 42)' '(42)'
  it 'empty list' \
    '(null? (list))' 't'

describe 'pair? / null?'
  it 'pair? on list' \
    '(pair? (list 1 2))' 't'
  it 'pair? on cons' \
    '(pair? (cons 1 2))' 't'
  it 'pair? on number' \
    '(null? (pair? 42))' 't'
  it 'pair? on nil' \
    '(null? (pair? ()))' 't'
  it 'null? on empty' \
    '(null? ())' 't'
  it 'null? on non-empty' \
    '(null? (null? (list 1)))' 't'

describe 'list?'
  it 'proper list' \
    '(list? (list 1 2 3))' 't'
  it 'empty list' \
    '(list? ())' 't'
  it 'dotted pair' \
    '(null? (list? (cons 1 2)))' 't'
  it 'non-list' \
    '(null? (list? 42))' 't'

describe 'length'
  it 'empty list' \
    '(length ())' '0'
  it 'non-empty list' \
    '(length (list 1 2 3))' '3'
  it 'single element' \
    '(length (list 42))' '1'

describe 'append'
  it 'appends two lists' \
    '(append (list 1 2) (list 3 4))' '(1 2 3 4)'
  it 'append with empty' \
    '(append () (list 1 2))' '(1 2)'
  it 'append empty to empty' \
    '(null? (append () ()))' 't'

describe 'reverse'
  it 'reverses a list' \
    '(reverse (list 1 2 3))' '(3 2 1)'
  it 'reverse empty' \
    '(null? (reverse ()))' 't'
  it 'reverse single' \
    '(reverse (list 42))' '(42)'

describe 'list-ref'
  it 'gets element by index' \
    '(list-ref (list 10 20 30) 1)' '20'
  it 'first element' \
    '(list-ref (list 10 20 30) 0)' '10'
  it 'last element' \
    '(list-ref (list 10 20 30) 2)' '30'

describe 'list-tail'
  it 'gets tail from index' \
    '(list-tail (list 1 2 3 4) 2)' '(3 4)'
  it 'tail from zero' \
    '(list-tail (list 1 2 3) 0)' '(1 2 3)'

describe 'map'
  it 'maps function over list' \
    '(define (double x) (* x 2)) (map double (list 1 2 3))' '(2 4 6)'
  it 'maps lambda' \
    '(map (lambda (x) (+ x 10)) (list 1 2 3))' '(11 12 13)'
  it 'map over empty list' \
    '(null? (map (lambda (x) x) ()))' 't'

describe 'filter'
  it 'filters elements' \
    '(filter (lambda (x) (> x 2)) (list 1 2 3 4 5))' '(3 4 5)'
  it 'filter none match' \
    '(null? (filter (lambda (x) (> x 10)) (list 1 2 3)))' 't'
  it 'filter all match' \
    '(filter (lambda (x) (> x 0)) (list 1 2 3))' '(1 2 3)'

describe 'for-each'
  it 'applies to each element' \
    '(define sum 0) (for-each (lambda (x) (set! sum (+ sum x))) (list 1 2 3)) sum' '6'

describe 'member'
  it 'finds symbol' \
    '(member (quote b) (list (quote a) (quote b) (quote c)))' '(b c)'
  it 'finds number' \
    '(member 3 (list 1 2 3 4 5))' '(3 4 5)'
  it 'returns false when not found' \
    '(null? (member (quote z) (list (quote a) (quote b))))' 't'

describe 'memq'
  it 'finds symbol' \
    '(memq (quote b) (list (quote a) (quote b) (quote c)))' '(b c)'
  it 'not found' \
    '(null? (memq (quote z) (list (quote a) (quote b))))' 't'

describe 'assoc'
  it 'finds association' \
    '(assoc (quote b) (list (list (quote a) 1) (list (quote b) 2)))' '(b 2)'
  it 'returns false when not found' \
    '(null? (assoc (quote z) (list (list (quote a) 1))))' 't'

describe 'assq'
  it 'finds by symbol' \
    '(assq (quote b) (list (list (quote a) 1) (list (quote b) 2)))' '(b 2)'
  it 'not found' \
    '(null? (assq (quote z) (list (list (quote a) 1))))' 't'

describe 'apply'
  it 'apply with built-in' \
    '(apply + (list 1 2 3))' '6'
  it 'apply with lambda' \
    '(apply (lambda (x y) (* x y)) (list 3 4))' '12'
