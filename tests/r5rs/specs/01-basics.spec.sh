# 01-basics.spec.sh -- Basic Scheme compatibility tests

describe 'define'
  it 'defines a variable' \
    '(define x 42) x' '42'
  it 'defines a function' \
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

describe 'boolean constants'
  it '#t is truthy' \
    '(if #t 1 2)' '1'
  it '#f is falsy' \
    '(if #f 1 2)' '2'
