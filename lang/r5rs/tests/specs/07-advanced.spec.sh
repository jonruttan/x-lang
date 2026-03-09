# 07-advanced.spec.sh -- Tests for advanced Scheme forms

describe 'case'
  it 'matches symbol' \
    '(case (quote b) ((a) 1) ((b) 2) ((c) 3))' '2'
  it 'matches number' \
    '(case (+ 1 1) ((1) (quote one)) ((2) (quote two)) ((3) (quote three)))' 'two'
  it 'else clause' \
    '(case 99 ((1) (quote one)) (else (quote other)))' 'other'
  it 'no match returns nil' \
    '(null? (case 5 ((1) (quote one)) ((2) (quote two))))' 't'
  it 'matches in datum list' \
    '(case (quote c) ((a b) 1) ((c d) 2))' '2'

describe 'quasiquote'
  it 'basic quasiquote' \
    '(define x 42) (quasiquote (a (unquote x) c))' '(a 42 c)'
  it 'quasiquote with expression' \
    '(quasiquote (a (unquote (+ 1 2)) c))' '(a 3 c)'
  it 'unquote-splicing' \
    '(quasiquote (a (unquote-splicing (list 1 2 3)) b))' '(a 1 2 3 b)'
  it 'nested quasiquote structure' \
    '(quasiquote (a (b (unquote (+ 1 2)))))' '(a (b 3))'
  it 'quasiquote without unquote' \
    '(quasiquote (a b c))' '(a b c)'

describe 'eval'
  it 'eval simple expression' \
    '(eval (list (quote +) 1 2))' '3'
  it 'eval quoted list' \
    '(eval (quote (+ 3 4)))' '7'
  it 'eval with variable' \
    '(define x 10) (eval (list (quote +) x 5))' '15'

describe 'apply'
  it 'apply with list arg' \
    '(apply + (list 1 2 3))' '6'
  it 'apply with lambda' \
    '(apply (lambda (a b c) (+ a b c)) (list 1 2 3))' '6'

describe 'closures'
  it 'closure captures variable' \
    '(define (make-adder n) (lambda (x) (+ x n))) ((make-adder 5) 10)' '15'
  it 'closure mutation' \
    '(define (make-counter) (define n 0) (lambda () (set! n (+ n 1)) n)) (define c (make-counter)) (c) (c) (c)' '3'
  it 'closure over loop variable' \
    '(define (make-fns) (let loop ((i 0) (acc ())) (if (= i 3) (reverse acc) (loop (+ i 1) (cons (let ((j i)) (lambda () j)) acc))))) (map (lambda (f) (f)) (make-fns))' '(0 1 2)'
  it 'independent closures' \
    '(define (make-counter) (define n 0) (lambda () (set! n (+ n 1)) n)) (define a (make-counter)) (define b (make-counter)) (a) (a) (b) (list (a) (b))' '(3 2)'

describe 'higher-order patterns'
  it 'map with compose' \
    '(define (double x) (* x 2)) (define (inc x) (+ x 1)) (map (compose double inc) (list 1 2 3))' '(4 6 8)'
  it 'filter and map pipeline' \
    '(map (lambda (x) (* x x)) (filter (lambda (x) (> x 2)) (list 1 2 3 4 5)))' '(9 16 25)'
  it 'nested map' \
    '(map (lambda (lst) (map (lambda (x) (* x 2)) lst)) (list (list 1 2) (list 3 4)))' '((2 4) (6 8))'
  it 'fold to build list' \
    '(fold (lambda (acc x) (cons x acc)) () (list 1 2 3))' '(3 2 1)'
