# 03-recursion.spec.sh -- Tests for recursive definitions

describe 'factorial'
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
