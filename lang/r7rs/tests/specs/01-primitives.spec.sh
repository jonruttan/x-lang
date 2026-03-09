# 01-primitives.spec.sh -- R7RS 4.1 Primitive expression types

describe 'quotation'
  it 'quote symbol' \
    '(quote a)' 'a'
  it 'quote list' \
    '(quote (+ 1 2))' '(+ 1 2)'
  it 'quote number is identity' \
    '(quote 42)' '42'
  it 'quote string is identity' \
    '(quote "hello")' '"hello"'

describe 'lambda'
  it 'lambda application' \
    '((lambda (x) (+ x x)) 4)' '8'
  it 'lambda with rest args' \
    '((lambda x x) 3 4 5 6)' '(3 4 5 6)'
  it 'lambda with required and rest' \
    '((lambda (x y . z) z) 3 4 5 6)' '(5 6)'
  it 'lambda no args' \
    '((lambda () 42))' '42'
  it 'lambda multiple body forms' \
    '((lambda (x) (+ x 1) (+ x 2)) 10)' '12'
  it 'nested lambda' \
    '(((lambda (x) (lambda (y) (+ x y))) 3) 4)' '7'

describe 'if'
  it 'if true branch' \
    '(if (> 3 2) (quote yes) (quote no))' 'yes'
  it 'if false branch' \
    '(if (> 2 3) (quote yes) (quote no))' 'no'
  it 'if no else returns nil' \
    '(null? (if #f 1))' 't'
  it 'if non-false is true' \
    '(if 0 (quote yes) (quote no))' 'yes'
  it 'if nil is false' \
    '(if () (quote yes) (quote no))' 'no'

describe 'define'
  it 'define variable' \
    '(define x 28) x' '28'
  it 'define function shorthand' \
    '(define (f x) (+ x 1)) (f 10)' '11'
  it 'define with expression body' \
    '(define x (* 3 4)) x' '12'
  it 'redefine variable' \
    '(define x 1) (define x 2) x' '2'

describe 'set!'
  it 'set! mutates binding' \
    '(define x 1) (set! x 2) x' '2'
  it 'set! in nested scope' \
    '(define x 10) (let ((y 0)) (set! x 20)) x' '20'
