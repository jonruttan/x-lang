# 05-predicates.spec.sh -- Type and number predicates

describe 'type predicates'
  it 'number?' \
    '(number? 42)' 't'
  it 'number? false' \
    '(null? (number? "hello"))' 't'
  it 'string?' \
    '(string? "hello")' 't'
  it 'string? false' \
    '(null? (string? 42))' 't'
  it 'symbol?' \
    '(symbol? (quote hello))' 't'
  it 'symbol? false' \
    '(null? (symbol? 42))' 't'
  it 'procedure? on lambda' \
    '(procedure? (lambda (x) x))' 't'
  it 'procedure? on builtin' \
    '(procedure? car)' 't'
  it 'procedure? false' \
    '(null? (procedure? 42))' 't'
  it 'pair?' \
    '(pair? (list 1 2))' 't'
  it 'null? on empty' \
    '(null? ())' 't'
  it 'boolean? on #t' \
    '(boolean? #t)' 't'
  it 'boolean? on #f' \
    '(boolean? #f)' 't'
  it 'boolean? false' \
    '(null? (boolean? 42))' 't'
  it 'char? on char' \
    '(char? #\a)' 't'
  it 'char? false' \
    '(null? (char? 42))' 't'

describe 'equality'
  it 'eq? same symbol' \
    '(eq? (quote a) (quote a))' 't'
  it 'eq? different symbols' \
    '(null? (eq? (quote a) (quote b)))' 't'
  it 'equal? on lists' \
    '(equal? (list 1 2 3) (list 1 2 3))' 't'
  it 'equal? different lists' \
    '(null? (equal? (list 1 2) (list 1 3)))' 't'
  it 'equal? nested lists' \
    '(equal? (list 1 (list 2 3)) (list 1 (list 2 3)))' 't'
  it 'eqv? on numbers' \
    '(eqv? 42 42)' 't'
  it 'eqv? different numbers' \
    '(null? (eqv? 1 2))' 't'

describe 'list?'
  it 'list? on proper list' \
    '(list? (list 1 2))' 't'
  it 'list? on empty' \
    '(list? ())' 't'
  it 'list? on dotted pair' \
    '(null? (list? (cons 1 2)))' 't'
  it 'list? on atom' \
    '(null? (list? 42))' 't'

describe 'number predicates'
  it 'zero?' \
    '(zero? 0)' 't'
  it 'zero? false' \
    '(null? (zero? 1))' 't'
  it 'zero? negative' \
    '(null? (zero? (- 0 1)))' 't'
  it 'positive?' \
    '(positive? 5)' 't'
  it 'positive? false' \
    '(null? (positive? 0))' 't'
  it 'negative?' \
    '(negative? (- 0 3))' 't'
  it 'negative? false' \
    '(null? (negative? 0))' 't'
  it 'even?' \
    '(even? 4)' 't'
  it 'even? false' \
    '(null? (even? 3))' 't'
  it 'even? zero' \
    '(even? 0)' 't'
  it 'odd?' \
    '(odd? 3)' 't'
  it 'odd? false' \
    '(null? (odd? 4))' 't'

describe 'numeric operations'
  it 'abs positive' \
    '(abs 5)' '5'
  it 'abs negative' \
    '(abs (- 0 5))' '5'
  it 'abs zero' \
    '(abs 0)' '0'
  it 'min' \
    '(min 3 7)' '3'
  it 'max' \
    '(max 3 7)' '7'
  it 'modulo' \
    '(modulo 10 3)' '1'
