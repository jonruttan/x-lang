# 01-primitives.spec.sh -- Tests for built-in primitives

describe 'quote'
  it 'returns a symbol' '(quote a)' 'a'
  it 'returns a list' '(quote (a b c))' '(a b c)'
  it 'returns a nested list' '(quote (1 (2 3)))' '(1 (2 3))'

describe 'cons'
  it 'creates a dotted pair' '(cons 1 2)' '(1 . 2)'
  it 'creates a list when cdr is nil' '(cons 1 (quote ()))' '(1)'
  it 'prepends to a list' '(cons 1 (quote (2 3)))' '(1 2 3)'

describe 'car'
  it 'returns first of a pair' '(car (cons 1 2))' '1'
  it 'returns first of a list' '(car (quote (a b c)))' 'a'

describe 'cdr'
  it 'returns second of a pair' '(cdr (cons 1 2))' '2'
  it 'returns rest of a list' '(cdr (quote (a b c)))' '(b c)'

describe 'eq?'
  it 'returns the value for equal symbols' '(eq? (quote a) (quote a))' 'a'
  it 'returns a bound value for eq? on same binding' '(do (def x 5) (eq? x x))' '5'

describe 'arithmetic'
  it 'adds two numbers' '(+ 1 2)' '3'
  it 'subtracts two numbers' '(- 10 3)' '7'
  it 'multiplies two numbers' '(* 4 5)' '20'
  it 'nests arithmetic' '(+ 1 (* 2 3))' '7'
  it 'handles negative results' '(- 3 10)' '-7'

describe 'if'
  it 'takes then branch for non-nil' '(if (quote t) 1 2)' '1'
  it 'takes else branch for nil' '(if (quote ()) 1 2)' '2'
  it 'works with eq? true case' '(if (eq? (quote a) (quote a)) 10 20)' '10'

describe 'def'
  it 'binds a value' '(do (def x 42) x)' '42'
  it 'binds and uses in expression' '(do (def x 5) (+ x 1))' '6'

describe 'integers'
  it 'evaluates positive integers' '99' '99'
  it 'evaluates negative integers' '-99' '-99'

describe 'strings'
  it 'evaluates string literals' '"hello"' '"hello"'
  it 'evaluates empty strings' '""' '""'
