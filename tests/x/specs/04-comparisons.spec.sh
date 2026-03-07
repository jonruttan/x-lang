# 04-comparisons.spec.sh -- Tests for comparisons, booleans, cond, let

describe '<'
  it 'returns t for less than' '(< 1 2)' 't'
  it 'returns nil for equal' '(< 2 2)' ''
  it 'returns nil for greater than' '(< 3 2)' ''
  it 'handles negative numbers' '(< -5 0)' 't'

describe '>'
  it 'returns t for greater than' '(> 3 2)' 't'
  it 'returns nil for equal' '(> 2 2)' ''
  it 'returns nil for less than' '(> 1 2)' ''
  it 'handles negative numbers' '(> 0 -5)' 't'

describe '<='
  it 'returns t for less than' '(<= 1 2)' 't'
  it 'returns t for equal' '(<= 2 2)' 't'
  it 'returns nil for greater than' '(<= 3 2)' ''

describe '>='
  it 'returns t for greater than' '(>= 3 2)' 't'
  it 'returns t for equal' '(>= 2 2)' 't'
  it 'returns nil for less than' '(>= 1 2)' ''

describe 'and'
  it 'returns t for empty and' '(and)' 't'
  it 'returns value for single truthy' '(and 1)' '1'
  it 'returns nil for single falsy' '(and (quote ()))' ''
  it 'returns last value when all truthy' '(and 1 2 3)' '3'
  it 'returns nil on first falsy' '(and 1 (quote ()) 3)' ''
  it 'short-circuits evaluation' \
    '(do (def x 0) (and (quote ()) (set x 1)) x)' '0'

describe 'or'
  it 'returns nil for empty or' '(or)' ''
  it 'returns value for single truthy' '(or 1)' '1'
  it 'returns nil for single falsy' '(or (quote ()))' ''
  it 'returns first truthy value' '(or (quote ()) 2 3)' '2'
  it 'returns nil when all falsy' '(or (quote ()) (quote ()))' ''
  it 'short-circuits evaluation' \
    '(do (def x 0) (or 1 (set x 1)) x)' '0'

describe 'cond'
  it 'returns first matching branch' \
    '(cond ((= 1 1) 10) ((= 2 2) 20))' '10'
  it 'returns later matching branch' \
    '(cond ((= 1 2) 10) ((= 2 2) 20))' '20'
  it 'supports else with t' \
    '(cond ((= 1 2) 10) (t 30))' '30'
  it 'returns nil when no match' \
    '(cond ((= 1 2) 10) ((= 3 4) 20))' ''
  it 'works with comparisons' \
    '(do (def x 5) (cond ((< x 0) (quote neg)) ((= x 0) (quote zero)) (t (quote pos))))' 'pos'

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
