# 08-quasiquote.spec.sh -- Tests for quasiquote, unquote, unquote-splicing

describe 'quasiquote'
  it 'returns a literal list' \
    '(quasiquote (1 2 3))' '(1 2 3)'
  it 'returns a literal symbol' \
    '(quasiquote foo)' 'foo'
  it 'returns nil for empty list' \
    '(quasiquote ())' ''
  it 'returns a nested literal' \
    '(quasiquote (a (b c) d))' '(a (b c) d)'

describe 'unquote'
  it 'substitutes a variable' \
    '(do (def x 42) (quasiquote (a (unquote x) c)))' '(a 42 c)'
  it 'evaluates an expression' \
    '(quasiquote (result (unquote (+ 1 2))))' '(result 3)'
  it 'substitutes in first position' \
    '(do (def op (quote +)) (quasiquote ((unquote op) 1 2)))' '(+ 1 2)'
  it 'substitutes in last position' \
    '(do (def x 99) (quasiquote (a b (unquote x))))' '(a b 99)'
  it 'handles multiple unquotes' \
    '(do (def a 1) (def b 2) (quasiquote ((unquote a) (unquote b))))' '(1 2)'

describe 'unquote-splicing'
  it 'splices a list' \
    '(do (def xs (list 2 3)) (quasiquote (1 (unquote-splicing xs) 4)))' '(1 2 3 4)'
  it 'splices an empty list' \
    '(quasiquote (a (unquote-splicing (list)) b))' '(a b)'
  it 'splices at beginning' \
    '(do (def xs (list 1 2)) (quasiquote ((unquote-splicing xs) 3)))' '(1 2 3)'
  it 'splices at end' \
    '(do (def xs (list 3 4)) (quasiquote (1 2 (unquote-splicing xs))))' '(1 2 3 4)'
  it 'splices with unquote mixed' \
    '(do (def x 1) (def ys (list 2 3)) (quasiquote ((unquote x) (unquote-splicing ys) 4)))' '(1 2 3 4)'

describe 'quasiquote edge cases'
  it 'handles integer atom' \
    '(quasiquote 42)' '42'
  it 'handles string atom' \
    '(quasiquote "hello")' '"hello"'
  it 'handles dotted pair' \
    '(do (def x 2) (quasiquote (1 (unquote x))))' '(1 2)'
