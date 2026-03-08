# 02-core-forms.spec.sh -- Tests for core language forms
# Spec: Section 2 - Core Forms

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

describe 'list'
  it 'creates a list' '(list 1 2 3)' '(1 2 3)'
  it 'evaluates arguments' '(list (+ 1 2) (* 3 4))' '(3 12)'
  it 'returns nil for empty list' '(list)' ''

describe 'def'
  it 'binds a value' '(do (def x 42) x)' '42'
  it 'binds and uses in expression' '(do (def x 5) (+ x 1))' '6'

describe 'set'
  it 'mutates a binding' '(do (def x 1) (set x 2) x)' '2'
  it 'returns the new value' '(do (def x 1) (set x 42))' '42'

describe 'if'
  it 'takes then branch for non-nil' '(if (lit t) 1 2)' '1'
  it 'takes else branch for nil' '(if (lit ()) 1 2)' '2'
  it 'works with eq? true case' '(if (eq? (lit a) (lit a)) 10 20)' '10'
  it 'returns nil when false and no else' \
    '(if (= 1 2) 42)' ''
  it 'returns then when true and no else' \
    '(if (= 1 1) 42)' '42'

describe 'do'
  it 'returns last form' '(do 1 2 3)' '3'
  it 'evaluates all forms' '(do (def a 1) (def b 2) (+ a b))' '3'
  it 'returns nil for empty do' '(do)' ''

describe 'match'
  it 'returns first matching branch' \
    '(match ((= 1 1) 10) ((= 2 2) 20))' '10'
  it 'returns later matching branch' \
    '(match ((= 1 2) 10) ((= 2 2) 20))' '20'
  it 'supports else with t' \
    '(match ((= 1 2) 10) (t 30))' '30'
  it 'returns nil when no match' \
    '(match ((= 1 2) 10) ((= 3 4) 20))' ''
  it 'works with comparisons' \
    '(do (def x 5) (match ((< x 0) (lit neg)) ((= x 0) (lit zero)) (t (lit pos))))' 'pos'

describe 'let'
  it 'binds a single variable' \
    '(let ((x 42)) x)' '42'
  it 'binds multiple variables' \
    '(let ((x 3) (y 4)) (+ x y))' '7'
  it 'evaluates binding expressions' \
    '(let ((x (+ 1 2)) (y (* 3 4))) (+ x y))' '15'
  it 'does not pollute outer scope' \
    '(do (def x 1) (let ((x 2)) x) x)' '1'
  it 'supports multiple body forms' \
    '(let ((x 1)) (+ x 1) (+ x 2))' '3'
  it 'nests correctly' \
    '(let ((x 1)) (let ((y 2)) (+ x y)))' '3'

describe 'list call'
  it 'indexes first element' '((list 1 2 3) 0)' '1'
  it 'indexes last element' '((list 1 2 3) 2)' '3'
  it 'indexes via binding' '(do (def l (list 10 20 30)) (l 1))' '20'
  it 'negative index from end' '((list 1 2 3) -1)' '3'
  it 'slices from middle' '((list 1 2 3 4 5) 1 3)' '(2 3 4)'
  it 'slices from start' '((list 1 2 3 4 5) 0 2)' '(1 2)'
