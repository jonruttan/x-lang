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
  it 'redefines top-level variable' \
    '(define x 1) (define x 2) x' '2'
  it 'defines with expression body' \
    '(define x (+ 1 2)) x' '3'
  it 'interior define in lambda body' \
    '((lambda () (define x 42) x))' '42'
  it 'interior define does not leak' \
    '(define x 1) ((lambda () (define x 99) x)) x' '1'

describe 'lambda'
  it 'creates anonymous function' \
    '((lambda (x) (* x x)) 4)' '16'
  it 'lambda is fn alias' \
    '(define f (lambda (x y) (+ x y))) (f 3 4)' '7'
  it 'lambda with multiple body forms' \
    '((lambda (x) (+ x 1) (+ x 2)) 10)' '12'
  it 'lambda with no args' \
    '((lambda () 42))' '42'
  it 'nested lambda (currying)' \
    '(((lambda (x) (lambda (y) (+ x y))) 3) 4)' '7'
  it 'lambda as value in list' \
    '(define fs (list (lambda (x) (+ x 1)) (lambda (x) (* x 2)))) ((car fs) 5)' '6'

describe 'begin'
  it 'sequences expressions' \
    '(begin 1 2 3)' '3'
  it 'begin is do alias' \
    '(begin (define x 10) (+ x 5))' '15'
  it 'begin with side effects' \
    '(define x 0) (begin (set! x 1) (set! x 2) x)' '2'

describe 'set!'
  it 'mutates binding' \
    '(define x 10) (set! x 20) x' '20'
  it 'set! in nested scope' \
    '(define x 10) (let ((y 0)) (set! x 20)) x' '20'

describe 'boolean constants'
  it '#t is truthy' \
    '(if #t 1 2)' '1'
  it '#f is falsy' \
    '(if #f 1 2)' '2'

describe 'quote shorthand'
  it 'quote symbol' \
    "(write 'a)" \
    'a'
  it 'quote list' \
    "(write '(1 2 3))" \
    '(1 2 3)'
  it 'quote nil' \
    "(null? '())" \
    't'
  it 'nested quote' \
    "(write ''a)" \
    '(lit a)'
  it 'quote in list context' \
    "(write (list 'a 'b))" \
    '(a b)'

describe 'tail recursion'
  it 'tail-recursive factorial' \
    '(define (fact n acc) (if (= n 0) acc (fact (- n 1) (* n acc)))) (fact 10 1)' '3628800'
  it 'tail recursion does not overflow' \
    '(define (loop n) (if (= n 0) (quote done) (loop (- n 1)))) (loop 50000)' 'done'
