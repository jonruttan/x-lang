# 05-apply-eval.spec.sh -- Tests for variadic arithmetic, apply, and eval

describe 'variadic +'
  it 'adds two numbers' '(+ 1 2)' '3'
  it 'adds three numbers' '(+ 1 2 3)' '6'
  it 'adds many numbers' '(+ 1 2 3 4 5)' '15'
  it 'identity is 0' '(+)' '0'
  it 'single arg returns it' '(+ 5)' '5'

describe 'variadic -'
  it 'subtracts two numbers' '(- 10 3)' '7'
  it 'subtracts three numbers' '(- 10 3 2)' '5'
  it 'unary negates' '(- 5)' '-5'
  it 'no args returns 0' '(-)' '0'

describe 'variadic *'
  it 'multiplies two numbers' '(* 4 5)' '20'
  it 'multiplies three numbers' '(* 2 3 4)' '24'
  it 'identity is 1' '(*)' '1'
  it 'single arg returns it' '(* 7)' '7'

describe 'variadic /'
  it 'divides two numbers' '(/ 10 3)' '3'
  it 'divides evenly' '(/ 12 4)' '3'
  it 'handles negative dividend' '(/ -10 3)' '-3'
  it 'chains division' '(/ 100 5 2)' '10'

describe 'variadic %'
  it 'computes modulo' '(% 10 3)' '1'
  it 'returns zero for even division' '(% 12 4)' '0'
  it 'handles negative dividend' '(% -10 3)' '-1'
  it 'chains modulo' '(% 100 7 3)' '2'

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
    '(eval (lit (+ 1 2)))' '3'
  it 'evaluates a self-evaluating form' \
    '(eval 42)' '42'
  it 'evaluates in current environment' \
    '(do (def x 10) (eval (lit (+ x 1))))' '11'
  it 'evaluates a constructed expression' \
    '(eval (pair (lit +) (list 3 4)))' '7'
  it 'evaluates nested eval' \
    '(eval (lit (eval (lit 99))))' '99'
