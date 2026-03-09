# 01-aliases.spec.sh -- Scheme-compatible alias tests

describe 'define'
  it 'defines a variable' \
    '(define x 42) x' '42'
  it 'defines a function with sugar' \
    '(define (square x) (* x x)) (square 5)' '25'
  it 'defines multi-body function' \
    '(define (f x) (+ x 1) (+ x 2)) (f 10)' '12'
  it 'defines recursive function' \
    '(define (fact n) (if (= n 0) 1 (* n (fact (- n 1))))) (fact 5)' '120'

describe 'lambda'
  it 'creates anonymous function' \
    '((lambda (x) (* x x)) 4)' '16'
  it 'lambda is fn alias' \
    '(define f (lambda (x y) (+ x y))) (f 3 4)' '7'

describe 'begin'
  it 'sequences expressions' \
    '(begin 1 2 3)' '3'
  it 'begin is do alias' \
    '(begin (define x 10) (+ x 5))' '15'

describe 'set!'
  it 'mutates binding' \
    '(define x 10) (set! x 20) x' '20'

describe 'cons/car/cdr'
  it 'cons builds a pair' \
    '(cons 1 2)' '(1 . 2)'
  it 'car returns first element' \
    '(car (cons 1 2))' '1'
  it 'cdr returns rest element' \
    '(cdr (cons 1 2))' '2'
  it 'cons builds a list' \
    '(cons 1 (cons 2 (cons 3 ())))' '(1 2 3)'
  it 'car of list' \
    '(car (list 1 2 3))' '1'
  it 'cdr of list' \
    '(cdr (list 1 2 3))' '(2 3)'

describe 'boolean constants'
  it '#t is truthy' \
    '(if #t 1 2)' '1'
  it '#f is falsy' \
    '(if #f 1 2)' '2'

describe 'composition accessors'
  it 'caar' \
    '(caar (list (list 1 2) (list 3 4)))' '1'
  it 'cadr' \
    '(cadr (list 1 2 3))' '2'
  it 'cdar' \
    '(cdar (list (list 1 2) 3))' '(2)'
  it 'cddr' \
    '(cddr (list 1 2 3))' '(3)'
  it 'caddr' \
    '(caddr (list 1 2 3))' '3'

describe 'convenience aliases'
  it 'first returns car' \
    '(first (list 10 20 30))' '10'
  it 'second returns cadr' \
    '(second (list 10 20 30))' '20'
  it 'third returns caddr' \
    '(third (list 10 20 30))' '30'
  it 'rest returns cdr' \
    '(rest (list 10 20 30))' '(20 30)'
  it 'modulo alias' \
    '(modulo 10 3)' '1'

describe 'I/O constants'
  it 'stdin is 0' \
    'stdin' '0'
  it 'stdout is 1' \
    'stdout' '1'
  it 'stderr is 2' \
    'stderr' '2'
