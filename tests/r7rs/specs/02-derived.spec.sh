# 02-derived.spec.sh -- R7RS 4.2 Derived expression types

describe 'cond'
  it 'cond first true' \
    '(cond ((> 3 2) (quote greater)) ((< 3 2) (quote less)))' 'greater'
  it 'cond second clause' \
    '(cond ((> 3 3) (quote greater)) ((< 3 3) (quote less)) (#t (quote equal)))' 'equal'
  it 'cond no match returns nil' \
    '(null? (cond (#f 1)))' 't'

describe 'case'
  it 'case matches symbol' \
    '(case (quote b) ((a) 1) ((b) 2) ((c) 3))' '2'
  it 'case matches number' \
    '(case (+ 1 1) ((1) (quote one)) ((2) (quote two)) ((3) (quote three)))' 'two'
  it 'case else clause' \
    '(case 99 ((1) (quote one)) (else (quote other)))' 'other'
  it 'case no match returns nil' \
    '(null? (case 5 ((1) (quote one)) ((2) (quote two))))' 't'
  it 'case matches in datum list' \
    '(case (quote c) ((a b) 1) ((c d) 2))' '2'

describe 'and'
  it 'and all true returns last' \
    '(and 1 2 3)' '3'
  it 'and short-circuits on false' \
    '(null? (and 1 #f 3))' 't'
  it 'and no args returns true' \
    '(and)' 't'
  it 'and single true arg' \
    '(and 42)' '42'
  it 'and returns first false value' \
    '(null? (and #t #f))' 't'

describe 'or'
  it 'or returns first true' \
    '(or 1 2 3)' '1'
  it 'or skips false values' \
    '(or #f #f 3)' '3'
  it 'or no args returns false' \
    '(null? (or))' 't'
  it 'or single false' \
    '(null? (or #f))' 't'
  it 'or single true' \
    '(or 7)' '7'

describe 'when'
  it 'when true evaluates body' \
    '(when (= 1 1) (+ 10 20))' '30'
  it 'when false returns nil' \
    '(null? (when (= 1 2) 42))' 't'
  it 'when multiple body forms' \
    '(when #t 1 2 3)' '3'

describe 'unless'
  it 'unless false evaluates body' \
    '(unless (= 1 2) 99)' '99'
  it 'unless true returns nil' \
    '(null? (unless (= 1 1) 42))' 't'

describe 'let'
  it 'basic let' \
    '(let ((x 2) (y 3)) (* x y))' '6'
  it 'let with shadowing' \
    '(define x 1) (let ((x 10)) (+ x 1))' '11'
  it 'let bindings are parallel' \
    '(define x 10) (let ((x 1) (y x)) y)' '10'
  it 'let body returns last form' \
    '(let ((x 1)) (+ x 1) (+ x 2) (+ x 3))' '4'
  it 'nested let' \
    '(let ((x 1)) (let ((x 2) (y x)) (+ x y)))' '3'

describe 'let*'
  it 'let* sequential bindings' \
    '(let* ((x 1) (y (+ x 1))) (+ x y))' '3'
  it 'let* many bindings' \
    '(let* ((a 1) (b (+ a 1)) (c (+ b 1)) (d (+ c 1))) d)' '4'
  it 'let* shadows outer' \
    '(define x 100) (let* ((x 1) (y (+ x 1))) (+ x y))' '3'

describe 'letrec'
  it 'letrec recursive function' \
    '(letrec ((fact (lambda (n) (if (= n 0) 1 (* n (fact (- n 1))))))) (fact 5))' '120'
  it 'letrec mutual recursion even' \
    '(letrec ((e (lambda (n) (if (= n 0) #t (o (- n 1))))) (o (lambda (n) (if (= n 0) #f (e (- n 1)))))) (e 10))' 't'
  it 'letrec mutual recursion odd' \
    '(letrec ((e (lambda (n) (if (= n 0) #t (o (- n 1))))) (o (lambda (n) (if (= n 0) #f (e (- n 1)))))) (o 7))' 't'

describe 'named let'
  it 'named let loop' \
    '(let loop ((i 0) (sum 0)) (if (= i 5) sum (loop (+ i 1) (+ sum i))))' '10'
  it 'named let countdown' \
    '(let count ((n 5) (acc ())) (if (= n 0) acc (count (- n 1) (cons n acc))))' '(1 2 3 4 5)'
  it 'named let fibonacci' \
    '(let fib ((n 10) (a 0) (b 1)) (if (= n 0) a (fib (- n 1) b (+ a b))))' '55'

describe 'begin'
  it 'begin returns last' \
    '(begin 1 2 3)' '3'
  it 'begin with side effects' \
    '(define x 0) (begin (set! x 1) (set! x 2) x)' '2'

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
