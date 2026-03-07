# 01-primitives.spec.sh -- Tests for built-in primitives

describe 'lit'
  it 'returns a symbol' '(lit a)' 'a'
  it 'returns a list' '(lit (a b c))' '(a b c)'
  it 'returns a nested list' '(lit (1 (2 3)))' '(1 (2 3))'

describe 'pair'
  it 'creates a dotted pair' '(pair 1 2)' '(1 . 2)'
  it 'creates a list when rest is nil' '(pair 1 (lit ()))' '(1)'
  it 'prepends to a list' '(pair 1 (lit (2 3)))' '(1 2 3)'

describe 'first'
  it 'returns first of a pair' '(first (pair 1 2))' '1'
  it 'returns first of a list' '(first (lit (a b c)))' 'a'

describe 'rest'
  it 'returns second of a pair' '(rest (pair 1 2))' '2'
  it 'returns rest of a list' '(rest (lit (a b c)))' '(b c)'

describe 'eq?'
  it 'returns the value for equal symbols' '(eq? (lit a) (lit a))' 'a'
  it 'returns a bound value for eq? on same binding' '(do (def x 5) (eq? x x))' '5'

describe 'arithmetic'
  it 'adds two numbers' '(+ 1 2)' '3'
  it 'subtracts two numbers' '(- 10 3)' '7'
  it 'multiplies two numbers' '(* 4 5)' '20'
  it 'nests arithmetic' '(+ 1 (* 2 3))' '7'
  it 'handles negative results' '(- 3 10)' '-7'

describe 'if'
  it 'takes then branch for non-nil' '(if (lit t) 1 2)' '1'
  it 'takes else branch for nil' '(if (lit ()) 1 2)' '2'
  it 'works with eq? true case' '(if (eq? (lit a) (lit a)) 10 20)' '10'

describe 'def'
  it 'binds a value' '(do (def x 42) x)' '42'
  it 'binds and uses in expression' '(do (def x 5) (+ x 1))' '6'

describe 'integers'
  it 'evaluates positive integers' '99' '99'
  it 'evaluates negative integers' '-99' '-99'

describe 'strings'
  it 'evaluates string literals' '"hello"' '"hello"'
  it 'evaluates empty strings' '""' '""'

describe 'list call'
  it 'indexes first element' '((list 1 2 3) 0)' '1'
  it 'indexes last element' '((list 1 2 3) 2)' '3'
  it 'indexes via binding' '(do (def l (list 10 20 30)) (l 1))' '20'
  it 'negative index from end' '((list 1 2 3) -1)' '3'
  it 'slices from middle' '((list 1 2 3 4 5) 1 3)' '(2 3 4)'
  it 'slices from start' '((list 1 2 3 4 5) 0 2)' '(1 2)'
