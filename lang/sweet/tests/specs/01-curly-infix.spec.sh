describe 'curly-infix empty'
  it 'empty braces produce nil' \
    '(null? {})' \
    't'

describe 'curly-infix single'
  it 'single element is identity' \
    '{42}' \
    '42'
  it 'single symbol' \
    $'(define x 10)\n{x}' \
    '10'

describe 'curly-infix simple'
  it 'addition' \
    '{1 + 2}' \
    '3'
  it 'multiplication' \
    '{3 * 4}' \
    '12'
  it 'comparison' \
    '{5 > 3}' \
    't'
  it 'subtraction' \
    '{10 - 3}' \
    '7'

describe 'curly-infix two-element'
  it 'unary minus' \
    '{- 5}' \
    '-5'
  it 'not returns nil' \
    '(null? {not #t})' \
    't'

describe 'curly-infix variadic'
  it 'same operator folds' \
    '{1 + 2 + 3}' \
    '6'
  it 'five operands' \
    '{1 + 2 + 3 + 4 + 5}' \
    '15'

describe 'curly-infix mixed'
  it 'mixed ops produce nfx form' \
    '(write {1 + 2 * 3})' \
    '($nfx$ 1 + 2 * 3)'

describe 'curly-infix nested'
  it 'nested curlies' \
    '{2 * {3 + 4}}' \
    '14'
  it 'deeply nested' \
    '{{1 + 2} * {3 + 4}}' \
    '21'

describe 'curly-infix with sexp'
  it 'curly inside sexp' \
    '(if {3 > 2} "yes" "no")' \
    '"yes"'
  it 'sexp inside curly' \
    '{(+ 1 2) + (+ 3 4)}' \
    '10'
