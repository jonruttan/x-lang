# 10-tailcalls.spec.sh -- Tests for proper tail calls

describe 'tail call in if'
  it 'tail-recursive countdown' \
    '(do (def loop (fn (n) (if (= n 0) (quote done) (loop (- n 1))))) (loop 100000))' 'done'
  it 'tail-recursive accumulator' \
    '(do (def sum (fn (n acc) (if (= n 0) acc (sum (- n 1) (+ acc n))))) (sum 10000 0))' '50005000'

describe 'tail call in cond'
  it 'tail-recursive with cond' \
    '(do (def f (fn (n) (cond ((= n 0) (quote zero)) (t (f (- n 1)))))) (f 50000))' 'zero'

describe 'tail call in do'
  it 'last form of do is tail' \
    '(do (def f (fn (n) (do 1 2 (if (= n 0) (quote ok) (f (- n 1)))))) (f 50000))' 'ok'

describe 'tail call in let'
  it 'last form of let is tail' \
    '(do (def f (fn (n) (let ((m (- n 1))) (if (= m 0) (quote done) (f m))))) (f 50000))' 'done'

describe 'mutual tail recursion'
  it 'even?/odd? mutual recursion via set' \
    '(do (def odd? ()) (def even? (fn (n) (if (= n 0) t (odd? (- n 1))))) (set odd? (fn (n) (if (= n 0) () (even? (- n 1))))) (even? 10000))' 't'

describe 'tail call in apply'
  it 'apply with deep recursion' \
    '(do (def f (fn (n) (if (= n 0) (quote done) (apply f (list (- n 1)))))) (f 50000))' 'done'

describe 'non-tail recursion still works'
  it 'factorial via non-tail recursion' \
    '(do (def fact (fn (n) (if (= n 0) 1 (* n (fact (- n 1)))))) (fact 10))' '3628800'
  it 'map with higher-order function' \
    '(do (def map (fn (f xs) (if (null? xs) xs (cons (f (car xs)) (map f (cdr xs)))))) (map (fn (x) (* x x)) (list 1 2 3)))' '(1 4 9)'
