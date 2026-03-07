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
    '(do (def len (fn (xs) (if (null? xs) 0 (+ 1 (len (cdr xs)))))) (len (list 1 2 3 4 5)))' '5'
  it 'computes length of empty list' \
    '(do (def len (fn (xs) (if (null? xs) 0 (+ 1 (len (cdr xs)))))) (len (list)))' '0'
  it 'maps over a list' \
    '(do (def map (fn (f xs) (if (null? xs) xs (cons (f (car xs)) (map f (cdr xs)))))) (map (fn (x) (* x x)) (list 1 2 3)))' '(1 4 9)'
  it 'appends two lists' \
    '(do (def append (fn (a b) (if (null? a) b (cons (car a) (append (cdr a) b))))) (append (list 1 2) (list 3 4)))' '(1 2 3 4)'

describe 'higher-order recursion'
  it 'folds a list' \
    '(do (def fold (fn (f acc xs) (if (null? xs) acc (fold f (f acc (car xs)) (cdr xs))))) (fold (fn (a b) (+ a b)) 0 (list 1 2 3 4 5)))' '15'
  it 'filters a list' \
    '(do (def filter (fn (p xs) (if (null? xs) xs (if (p (car xs)) (cons (car xs) (filter p (cdr xs))) (filter p (cdr xs)))))) (filter (fn (x) (= x 3)) (list 1 2 3 4 3)))' '(3 3)'
