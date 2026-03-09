# 03-binding.spec.sh -- Binding forms

describe 'let'
  it 'creates local bindings' \
    '(let ((x 10) (y 20)) (+ x y))' '30'
  it 'does not leak bindings' \
    '(define x 1) (let ((x 99)) x) x' '1'
  it 'shadowing outer variable' \
    '(define x 1) (let ((x 10)) (+ x 1))' '11'
  it 'body returns last form' \
    '(let ((x 1)) (+ x 1) (+ x 2) (+ x 3))' '4'
  it 'bindings are parallel' \
    '(define x 10) (let ((x 1) (y x)) y)' '10'
  it 'nested let' \
    '(let ((x 1)) (let ((x 2) (y x)) (+ x y)))' '3'

describe 'let*'
  it 'creates sequential bindings' \
    '(let* ((x 1) (y (+ x 1))) (+ x y))' '3'
  it 'later bindings see earlier ones' \
    '(let* ((a 10) (b (* a 2)) (c (+ b 5))) c)' '25'
  it 'does not leak bindings' \
    '(define x 1) (let* ((x 99) (y x)) y) x' '1'
  it 'many sequential bindings' \
    '(let* ((a 1) (b (+ a 1)) (c (+ b 1)) (d (+ c 1))) d)' '4'
  it 'shadows outer' \
    '(define x 100) (let* ((x 1) (y (+ x 1))) (+ x y))' '3'

describe 'letrec'
  it 'binds recursive function' \
    '(letrec ((fact (lambda (n) (if (= n 0) 1 (* n (fact (- n 1))))))) (fact 5))' '120'
  it 'mutual recursion even' \
    '(letrec ((e (lambda (n) (if (= n 0) #t (o (- n 1))))) (o (lambda (n) (if (= n 0) #f (e (- n 1)))))) (e 10))' 't'
  it 'mutual recursion odd' \
    '(letrec ((e (lambda (n) (if (= n 0) #t (o (- n 1))))) (o (lambda (n) (if (= n 0) #f (e (- n 1)))))) (o 7))' 't'
  it 'two independent bindings' \
    '(letrec ((x 1) (y 2)) (+ x y))' '3'

describe 'named let'
  it 'basic loop' \
    '(let loop ((i 0) (sum 0)) (if (= i 5) sum (loop (+ i 1) (+ sum i))))' '10'
  it 'countdown to list' \
    '(let count ((n 5) (acc ())) (if (= n 0) acc (count (- n 1) (cons n acc))))' '(1 2 3 4 5)'
  it 'fibonacci' \
    '(let fib ((n 10) (a 0) (b 1)) (if (= n 0) a (fib (- n 1) b (+ a b))))' '55'
  it 'regular let still works' \
    '(let ((x 1) (y 2)) (+ x y))' '3'
