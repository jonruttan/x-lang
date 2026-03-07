# 06-stdlib.spec.sh -- Tests for x.x standard library (via Scheme runner)

describe 'identity'
  it 'returns its argument' \
    '(identity 42)' '42'
  it 'returns a list' \
    '(identity (list 1 2))' '(1 2)'

describe 'const'
  it 'returns a function that ignores its argument' \
    '((const 5) 99)' '5'
  it 'works with symbols' \
    '((const (quote hello)) 0)' 'hello'

describe 'compose'
  it 'composes two functions' \
    '(define (double x) (* x 2)) (define (inc x) (+ x 1)) ((compose double inc) 3)' '8'
  it 'applies right function first' \
    '((compose (lambda (x) (+ x 10)) (lambda (x) (* x 2))) 5)' '20'

describe 'curry'
  it 'partially applies a function' \
    '(define (add a b) (+ a b)) (define add5 (curry add 5)) (add5 3)' '8'
  it 'works with built-in operators' \
    '(define mul (curry * 10)) (mul 7)' '70'

describe 'fold'
  it 'left-folds a list' \
    '(fold + 0 (list 1 2 3 4))' '10'
  it 'accumulates from the left' \
    '(fold - 10 (list 1 2 3))' '4'
  it 'returns init for empty list' \
    '(fold + 0 ())' '0'

describe 'reduce'
  it 'reduces a list with no init' \
    '(reduce + (list 1 2 3 4))' '10'
  it 'works with subtraction' \
    '(reduce - (list 10 3 2))' '5'

describe 'range'
  it 'generates a range' \
    '(range 0 5)' '(0 1 2 3 4)'
  it 'returns empty for start >= end' \
    '(null? (range 5 5))' 't'
  it 'works with non-zero start' \
    '(range 3 6)' '(3 4 5)'

describe 'zip'
  it 'pairs elements from two lists' \
    '(zip (list 1 2 3) (list 4 5 6))' '((1 4) (2 5) (3 6))'
  it 'stops at shorter list' \
    '(zip (list 1 2) (list 3))' '((1 3))'
  it 'returns empty for empty input' \
    '(null? (zip () (list 1)))' 't'

describe 'any?'
  it 'returns t when predicate matches' \
    '(any? (lambda (x) (> x 3)) (list 1 2 3 4 5))' 't'
  it 'returns nil when none match' \
    '(null? (any? (lambda (x) (> x 10)) (list 1 2 3)))' 't'
  it 'returns nil for empty list' \
    '(null? (any? (lambda (x) t) ()))' 't'

describe 'every?'
  it 'returns t when all match' \
    '(every? (lambda (x) (> x 0)) (list 1 2 3))' 't'
  it 'returns nil when one fails' \
    '(null? (every? (lambda (x) (> x 2)) (list 1 2 3)))' 't'
  it 'returns t for empty list' \
    '(every? (lambda (x) (> x 0)) ())' 't'
