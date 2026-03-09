# 11-control.spec.sh -- R7RS 6.10 Control features

describe 'procedure?'
  it 'procedure? on lambda' \
    '(procedure? (lambda (x) x))' 't'
  it 'procedure? on builtin' \
    '(procedure? +)' 't'
  it 'procedure? on number' \
    '(null? (procedure? 42))' 't'
  it 'procedure? on list' \
    '(null? (procedure? (list 1 2)))' 't'
  it 'procedure? on symbol' \
    '(null? (procedure? (quote foo)))' 't'

describe 'apply'
  it 'apply with list arg' \
    '(apply + (list 1 2 3))' '6'
  it 'apply with lambda' \
    '(apply (lambda (a b c) (+ a b c)) (list 1 2 3))' '6'
  it 'apply with builtin' \
    '(apply * (list 2 3 4))' '24'
  it 'apply cons' \
    '(apply cons (list 1 2))' '(1 . 2)'

describe 'map'
  it 'map single list' \
    '(map (lambda (x) (* x x)) (list 1 2 3 4))' '(1 4 9 16)'
  it 'map with car' \
    '(map car (list (cons 1 2) (cons 3 4) (cons 5 6)))' '(1 3 5)'
  it 'map with lambda' \
    '(map (lambda (x) (+ x 1)) (list 10 20 30))' '(11 21 31)'
  it 'map on empty' \
    '(null? (map (lambda (x) x) ()))' 't'
  it 'map preserves order' \
    '(map car (list (list 1 2) (list 3 4) (list 5 6)))' '(1 3 5)'

describe 'for-each'
  it 'for-each visits all elements' \
    '(define sum 0) (for-each (lambda (x) (set! sum (+ sum x))) (list 1 2 3 4)) sum' '10'
  it 'for-each order' \
    '(define acc ()) (for-each (lambda (x) (set! acc (cons x acc))) (list 1 2 3)) (reverse acc)' '(1 2 3)'

describe 'higher-order patterns'
  it 'compose' \
    '(define (double x) (* x 2)) (define (inc x) (+ x 1)) (map (compose double inc) (list 1 2 3))' '(4 6 8)'
  it 'filter and map pipeline' \
    '(map (lambda (x) (* x x)) (filter (lambda (x) (> x 2)) (list 1 2 3 4 5)))' '(9 16 25)'
  it 'closure captures variable' \
    '(define (make-adder n) (lambda (x) (+ x n))) ((make-adder 5) 10)' '15'
  it 'closure mutation counter' \
    '(define (make-counter) (define n 0) (lambda () (set! n (+ n 1)) n)) (define c (make-counter)) (c) (c) (c)' '3'
  it 'independent closures' \
    '(define (make-counter) (define n 0) (lambda () (set! n (+ n 1)) n)) (define a (make-counter)) (define b (make-counter)) (a) (a) (b) (list (a) (b))' '(3 2)'

describe 'tail recursion'
  it 'tail-recursive factorial' \
    '(define (fact n acc) (if (= n 0) acc (fact (- n 1) (* n acc)))) (fact 10 1)' '3628800'
  it 'deep tail recursion' \
    '(define (loop n) (if (= n 0) (quote done) (loop (- n 1)))) (loop 50000)' 'done'

describe 'values'
  it 'single value passthrough' \
    '(call-with-values (lambda () (values 42)) (lambda (x) x))' '42'
  it 'two values' \
    '(call-with-values (lambda () (values 1 2)) +)' '3'
  it 'three values' \
    '(call-with-values (lambda () (values 1 2 3)) +)' '6'
  it 'values with computation' \
    '(call-with-values (lambda () (values (* 2 3) (* 4 5))) +)' '26'
  it 'single value optimization' \
    '(values 42)' '42'
  it 'call-with-values non-values producer' \
    '(call-with-values (lambda () 42) (lambda (x) (* x 2)))' '84'
  it 'values with list consumer' \
    '(call-with-values (lambda () (values 1 2 3)) list)' '(1 2 3)'
  it 'values in let binding' \
    '(call-with-values (lambda () (values 10 20)) (lambda (a b) (- a b)))' '-10'
