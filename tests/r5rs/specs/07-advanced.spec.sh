# 07-advanced.spec.sh -- Tests for advanced Scheme forms

describe 'letrec'
  it 'binds recursive function' \
    '(letrec ((fact (lambda (n) (if (= n 0) 1 (* n (fact (- n 1))))))) (fact 5))' '120'
  it 'mutual recursion' \
    '(letrec ((even? (lambda (n) (if (= n 0) #t (odd? (- n 1))))) (odd? (lambda (n) (if (= n 0) #f (even? (- n 1)))))) (even? 10))' 't'
  it 'mutual recursion odd' \
    '(letrec ((even? (lambda (n) (if (= n 0) #t (odd? (- n 1))))) (odd? (lambda (n) (if (= n 0) #f (even? (- n 1)))))) (odd? 7))' 't'

describe 'named let'
  it 'basic loop' \
    '(let loop ((i 0) (sum 0)) (if (= i 5) sum (loop (+ i 1) (+ sum i))))' '10'
  it 'countdown' \
    '(let count ((n 5) (acc ())) (if (= n 0) acc (count (- n 1) (cons n acc))))' '(1 2 3 4 5)'
  it 'regular let still works' \
    '(let ((x 1) (y 2)) (+ x y))' '3'

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
