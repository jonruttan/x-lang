# 02-closures.spec.sh -- Tests for fn, do, set, and closures

describe 'fn'
  it 'creates a procedure' '(fn (x) x)' '#<fn>'
  it 'creates a procedure with empty params' '(fn () 42)' '#<fn>'
  it 'applies identity' '((fn (x) x) 7)' '7'
  it 'applies with two params' '((fn (x y) (+ x y)) 3 4)' '7'
  it 'applies with empty params' '((fn () 42))' '42'
  it 'supports multiple body forms' '((fn (x) (+ x 1) (+ x 2)) 10)' '12'

describe 'closures'
  it 'captures enclosing environment' \
    '(do (def make-adder (fn (x) (fn (y) (+ x y)))) ((make-adder 5) 3))' '8'
  it 'captures and returns value' \
    '(do (def f (do (def a 10) (fn () a))) (f))' '10'

describe 'do'
  it 'returns last form' '(do 1 2 3)' '3'
  it 'evaluates all forms' '(do (def a 1) (def b 2) (+ a b))' '3'
  it 'returns nil for empty do' '(do)'

describe 'set'
  it 'mutates a binding' '(do (def x 1) (set x 2) x)' '2'
  it 'returns the new value' '(do (def x 1) (set x 42))' '42'

describe 'counter (closure + mutation)'
  it 'increments on each call' \
    '(do (def counter (do (def n 0) (fn () (do (set n (+ n 1)) n)))) (do (counter) (counter) (counter)))' '3'

describe '='
  it 'returns t for equal integers' '(= 3 3)' 't'
  it 'returns nil for unequal integers' '(= 3 4)'

describe 'null?'
  it 'returns t for nil' '(null? (quote ()))' 't'
  it 'returns nil for non-nil' '(null? 1)'

describe 'pair?'
  it 'returns t for a list' '(pair? (list 1 2))' 't'
  it 'returns t for a cons pair' '(pair? (cons 1 2))' 't'
  it 'returns nil for an atom' '(pair? 42)'

describe 'atom?'
  it 'returns t for an integer' '(atom? 42)' 't'
  it 'returns t for a symbol' '(atom? (quote a))' 't'
  it 'returns nil for a list' '(atom? (list 1 2))'

describe 'not'
  it 'returns t for nil' '(not (quote ()))' 't'
  it 'returns nil for non-nil' '(not 1)'

describe 'list'
  it 'creates a list' '(list 1 2 3)' '(1 2 3)'
  it 'evaluates arguments' '(list (+ 1 2) (* 3 4))' '(3 12)'
  it 'returns nil for empty list' '(list)'
