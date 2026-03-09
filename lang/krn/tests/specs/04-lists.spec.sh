# 04-lists.spec.sh -- Kernel list operations

describe 'accessors'
  it 'cadr' \
    '(cadr (list 1 2 3))' '2'
  it 'caddr' \
    '(caddr (list 1 2 3))' '3'
  it 'caar' \
    '(caar (list (list 1 2) 3))' '1'
  it 'cdar' \
    '(cdar (list (list 1 2) 3))' '(2)'

describe 'length'
  it 'empty list' \
    '(length ())' '0'
  it 'non-empty list' \
    '(length (list 1 2 3))' '3'

describe 'append'
  it 'appends two lists' \
    '(append (list 1 2) (list 3 4))' '(1 2 3 4)'
  it 'append with empty' \
    '(append () (list 1 2))' '(1 2)'

describe 'reverse'
  it 'reverses a list' \
    '(reverse (list 1 2 3))' '(3 2 1)'
  it 'reverse empty' \
    '(null? (reverse ()))' 't'

describe 'list-ref'
  it 'gets element by index' \
    '(list-ref (list 10 20 30) 1)' '20'
  it 'first element' \
    '(list-ref (list 10 20 30) 0)' '10'

describe 'map'
  it 'maps function over list' \
    '($define! double ($lambda (x) (* x 2))) (map double (list 1 2 3))' '(2 4 6)'
  it 'maps lambda' \
    '(map ($lambda (x) (+ x 10)) (list 1 2 3))' '(11 12 13)'

describe 'filter'
  it 'filters elements' \
    '(filter ($lambda (x) (> x 2)) (list 1 2 3 4 5))' '(3 4 5)'
  it 'filter none match' \
    '(null? (filter ($lambda (x) (> x 10)) (list 1 2 3)))' 't'

describe 'for-each'
  it 'applies to each element' \
    '($define! sum 0) (for-each ($lambda (x) (set sum (+ sum x))) (list 1 2 3)) sum' '6'

describe 'member'
  it 'finds element' \
    '(member (quote b) (list (quote a) (quote b) (quote c)))' '(b c)'
  it 'returns false when not found' \
    '(null? (member (quote z) (list (quote a) (quote b))))' 't'

describe 'assoc'
  it 'finds association' \
    '(assoc (quote b) (list (list (quote a) 1) (list (quote b) 2)))' '(b 2)'
  it 'returns false when not found' \
    '(null? (assoc (quote z) (list (list (quote a) 1))))' 't'
