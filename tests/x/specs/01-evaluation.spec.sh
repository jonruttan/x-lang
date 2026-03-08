# 01-evaluation.spec.sh -- Tests for evaluation model
# Spec: Section 1 - Evaluation Model

describe 'self-evaluation'
  it 'evaluates positive integers' '99' '99'
  it 'evaluates negative integers' '-99' '-99'
  it 'evaluates string literals' '"hello"' '"hello"'
  it 'evaluates empty strings' '""' '""'
  it 'evaluates nil' '()' ''
  it 'evaluates character literals' '#\a' 'a'
  it 'evaluates t' 't' 't'

describe 'symbol lookup'
  it 'binds and looks up a value' '(do (def x 42) x)' '42'
  it 'looks up in expression' '(do (def x 5) (+ x 1))' '6'
  it 'unbound symbol signals error' \
    '(guard (e (lit caught)) no-such-var)' 'caught'

describe 'recursive definitions'
  it 'computes fact(0)' \
    '(do (def fact (fn (n) (if (= n 0) 1 (* n (fact (- n 1)))))) (fact 0))' '1'
  it 'computes fact(5)' \
    '(do (def fact (fn (n) (if (= n 0) 1 (* n (fact (- n 1)))))) (fact 5))' '120'
  it 'computes fact(10)' \
    '(do (def fact (fn (n) (if (= n 0) 1 (* n (fact (- n 1)))))) (fact 10))' '3628800'

describe 'recursive list operations'
  it 'computes length of a list' \
    '(do (def len (fn (xs) (if (null? xs) 0 (+ 1 (len (rest xs)))))) (len (list 1 2 3 4 5)))' '5'
  it 'computes length of empty list' \
    '(do (def len (fn (xs) (if (null? xs) 0 (+ 1 (len (rest xs)))))) (len (list)))' '0'
  it 'maps over a list' \
    '(do (def map (fn (f xs) (if (null? xs) xs (pair (f (first xs)) (map f (rest xs)))))) (map (fn (x) (* x x)) (list 1 2 3)))' '(1 4 9)'
  it 'appends two lists' \
    '(do (def append (fn (a b) (if (null? a) b (pair (first a) (append (rest a) b))))) (append (list 1 2) (list 3 4)))' '(1 2 3 4)'

describe 'higher-order recursion'
  it 'folds a list' \
    '(do (def fold (fn (f acc xs) (if (null? xs) acc (fold f (f acc (first xs)) (rest xs))))) (fold (fn (a b) (+ a b)) 0 (list 1 2 3 4 5)))' '15'
  it 'filters a list' \
    '(do (def filter (fn (p xs) (if (null? xs) xs (if (p (first xs)) (pair (first xs) (filter p (rest xs))) (filter p (rest xs)))))) (filter (fn (x) (= x 3)) (list 1 2 3 4 3)))' '(3 3)'

describe 'tail call in if'
  it 'tail-recursive countdown' \
    '(do (def loop (fn (n) (if (= n 0) (lit done) (loop (- n 1))))) (loop 100000))' 'done'
  it 'tail-recursive accumulator' \
    '(do (def sum (fn (n acc) (if (= n 0) acc (sum (- n 1) (+ acc n))))) (sum 10000 0))' '50005000'

describe 'tail call in match'
  it 'tail-recursive with match' \
    '(do (def f (fn (n) (match ((= n 0) (lit zero)) (t (f (- n 1)))))) (f 50000))' 'zero'

describe 'tail call in do'
  it 'last form of do is tail' \
    '(do (def f (fn (n) (do 1 2 (if (= n 0) (lit ok) (f (- n 1)))))) (f 50000))' 'ok'

describe 'tail call in let'
  it 'last form of let is tail' \
    '(do (def f (fn (n) (let ((m (- n 1))) (if (= m 0) (lit done) (f m))))) (f 50000))' 'done'

describe 'mutual tail recursion'
  it 'even?/odd? mutual recursion via set' \
    '(do (def odd? ()) (def even? (fn (n) (if (= n 0) t (odd? (- n 1))))) (set odd? (fn (n) (if (= n 0) () (even? (- n 1))))) (even? 10000))' 't'

describe 'tail call in apply'
  it 'apply with deep recursion' \
    '(do (def f (fn (n) (if (= n 0) (lit done) (apply f (list (- n 1)))))) (f 50000))' 'done'

describe 'and/or in non-tail position'
  it 'and with fn call in if condition' \
    '(do (def h (fn (n) (> n 0))) (def f (fn (n) (if (and (h n) t) n "no"))) (f 5))' '5'
  it 'or with fn call in if condition' \
    '(do (def h (fn (n) (= n 0))) (def f (fn (n) (if (or () (h n)) "yes" "no"))) (f 0))' '"yes"'
  it 'or in recursive function condition' \
    '(do (def f (fn (n) (if (or () (= n 0)) (lit done) (f (- n 1))))) (f 10))' 'done'
  it 'and in recursive function condition' \
    '(do (def f (fn (n) (if (and t (> n 0)) (f (- n 1)) (lit done)))) (f 10))' 'done'

describe 'non-tail recursion still works'
  it 'factorial via non-tail recursion' \
    '(do (def fact (fn (n) (if (= n 0) 1 (* n (fact (- n 1)))))) (fact 10))' '3628800'
  it 'map with higher-order function' \
    '(do (def map (fn (f xs) (if (null? xs) xs (pair (f (first xs)) (map f (rest xs)))))) (map (fn (x) (* x x)) (list 1 2 3)))' '(1 4 9)'
