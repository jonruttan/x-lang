describe 'indentation single-line'
  it 'tokens on one line form a list' \
    'define x 42' \
    '42'
  it 'function call on one line' \
    '+ 1 2' \
    '3'

describe 'indentation basic grouping'
  it 'indented body becomes child' \
    $'define x\n  42\nx' \
    '42'
  it 'indented function call' \
    $'define x\n  + 1 2\nx' \
    '3'
  it 'multiple head tokens with child' \
    $'if #t\n  42' \
    '42'

describe 'indentation if expression'
  it 'if with two branches' \
    $'if {3 > 2}\n  "yes"\n  "no"' \
    '"yes"'
  it 'if false branch' \
    $'if {3 < 2}\n  "yes"\n  "no"' \
    '"no"'

describe 'indentation nested'
  it 'two levels of nesting' \
    $'define x\n  +\n    1\n    2\nx' \
    '3'
  it 'define with lambda' \
    $'define double\n  lambda (n)\n    * n 2\ndouble 7' \
    '14'

describe 'indentation factorial'
  it 'recursive factorial' \
    $'define factorial\n  lambda (n)\n    if {n <= 1}\n      1\n      {n * (factorial {n - 1})}\nfactorial 5' \
    '120'

describe 'indentation with parens'
  it 'parens override indentation' \
    $'(define x\n  42)\nx' \
    '42'
  it 'sexp inside sweet' \
    $'define x (+ 1 2)\nx' \
    '3'

describe 'indentation with curlies'
  it 'curly infix in indented position' \
    $'define x\n  {3 + 4}\nx' \
    '7'

describe 'indentation blank lines'
  it 'blank lines between expressions' \
    $'define x 10\n\nx' \
    '10'

describe 'indentation comments'
  it 'comment line is transparent' \
    $'define x\n  ; this is a comment\n  42\nx' \
    '42'
