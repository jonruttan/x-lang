# 09-quasiquote.spec.sh -- Tests for quasiquote
# Spec: Section 9 - Quasiquote

describe 'quasi'
  it 'returns a literal list' \
    '(quasi (1 2 3))' '(1 2 3)'
  it 'returns a literal symbol' \
    '(quasi foo)' 'foo'
  it 'returns nil for empty list' \
    '(quasi ())' ''
  it 'returns a nested literal' \
    '(quasi (a (b c) d))' '(a (b c) d)'

describe 'unquote'
  it 'substitutes a variable' \
    '(do (def x 42) (quasi (a (unquote x) c)))' '(a 42 c)'
  it 'evaluates an expression' \
    '(quasi (result (unquote (+ 1 2))))' '(result 3)'
  it 'substitutes in first position' \
    '(do (def op (lit +)) (quasi ((unquote op) 1 2)))' '(+ 1 2)'
  it 'substitutes in last position' \
    '(do (def x 99) (quasi (a b (unquote x))))' '(a b 99)'
  it 'handles multiple unquotes' \
    '(do (def a 1) (def b 2) (quasi ((unquote a) (unquote b))))' '(1 2)'

describe 'unquote-splicing'
  it 'splices a list' \
    '(do (def xs (list 2 3)) (quasi (1 (unquote-splicing xs) 4)))' '(1 2 3 4)'
  it 'splices an empty list' \
    '(quasi (a (unquote-splicing (list)) b))' '(a b)'
  it 'splices at beginning' \
    '(do (def xs (list 1 2)) (quasi ((unquote-splicing xs) 3)))' '(1 2 3)'
  it 'splices at end' \
    '(do (def xs (list 3 4)) (quasi (1 2 (unquote-splicing xs))))' '(1 2 3 4)'
  it 'splices with unquote mixed' \
    '(do (def x 1) (def ys (list 2 3)) (quasi ((unquote x) (unquote-splicing ys) 4)))' '(1 2 3 4)'

describe 'quasi edge cases'
  it 'handles integer atom' \
    '(quasi 42)' '42'
  it 'handles string atom' \
    '(quasi "hello")' '"hello"'
  it 'handles dotted pair' \
    '(do (def x 2) (quasi (1 (unquote x))))' '(1 2)'
