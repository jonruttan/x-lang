# 01-basics.spec.sh -- Core Kernel forms

describe '$define! simple'
  it 'binds a value' \
    '($define! x 42) x' '42'
  it 'binds a string' \
    '($define! greeting "hello") greeting' '"hello"'
  it 'binds an expression result' \
    '($define! sum (+ 1 2)) sum' '3'

describe '$define! function sugar'
  it 'defines and calls operative-style function' \
    '($define! (square x) (* x x)) (square 5)' '25'
  it 'multi-body function' \
    '($define! (f x) ($define! y (+ x 1)) (* x y)) (f 3)' '12'

describe '$vau'
  it 'is an alias for op' \
    '(def my-op ($vau (x) e (+ 1 (eval x e)))) (my-op (+ 2 3))' '6'

describe '$lambda'
  it 'creates an applicative' \
    '($define! double ($lambda (x) (* x 2))) (double 5)' '10'
  it 'applicative evaluates args' \
    '($define! add1 ($lambda (x) (+ x 1))) (add1 (+ 2 3))' '6'

describe '$sequence'
  it 'evaluates in order' \
    '($sequence ($define! a 1) ($define! b 2) (+ a b))' '3'

describe 'boolean constants'
  it '#t is t' \
    '#t' 't'
  it '#f is nil' \
    '(null? #f)' 't'
