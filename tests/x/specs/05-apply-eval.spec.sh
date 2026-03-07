# 05-apply-eval.spec.sh -- Tests for /, %, apply, and eval

describe '/'
  it 'divides two numbers' '(/ 10 3)' '3'
  it 'divides evenly' '(/ 12 4)' '3'
  it 'handles negative dividend' '(/ -10 3)' '-3'

describe '%'
  it 'computes modulo' '(% 10 3)' '1'
  it 'returns zero for even division' '(% 12 4)' '0'
  it 'handles negative dividend' '(% -10 3)' '-1'

describe 'apply'
  it 'applies a function to a list of args' \
    '(apply (fn (x y) (+ x y)) (list 3 4))' '7'
  it 'applies with empty args' \
    '(apply (fn () 42) (list))' '42'
  it 'applies a named function' \
    '(do (def add (fn (a b) (+ a b))) (apply add (list 10 20)))' '30'
  it 'applies with computed arg list' \
    '(do (def f (fn (x) (* x x))) (apply f (list (+ 2 3))))' '25'
  it 'applies a recursive function' \
    '(do (def fact (fn (n) (if (= n 0) 1 (* n (fact (- n 1)))))) (apply fact (list 5)))' '120'

describe 'eval'
  it 'evaluates a quoted expression' \
    '(eval (quote (+ 1 2)))' '3'
  it 'evaluates a self-evaluating form' \
    '(eval 42)' '42'
  it 'evaluates in current environment' \
    '(do (def x 10) (eval (quote (+ x 1))))' '11'
  it 'evaluates a constructed expression' \
    '(eval (cons (quote +) (list 3 4)))' '7'
  it 'evaluates nested eval' \
    '(eval (quote (eval (quote 99))))' '99'
