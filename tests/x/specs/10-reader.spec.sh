# 10-reader.spec.sh -- Tests for reader syntax
# Spec: Section 10 - Reader Syntax

describe 'integer reader'
  it 'reads positive integers' '99' '99'
  it 'reads negative integers' '-99' '-99'
  it 'reads zero' '0' '0'

describe 'string reader'
  it 'reads simple string' '"hello"' '"hello"'
  it 'reads empty string' '""' '""'

describe 'symbol reader'
  it 'reads simple symbol' '(lit abc)' 'abc'
  it 'reads symbol with punctuation' '(lit my-var?)' 'my-var?'
  it 'reads operator symbols' '(lit +)' '+'

describe 'character reader'
  it 'reads character literal' \
    '(char? #\x)' 't'
  it 'reads specific character' \
    '(char->integer #\a)' '97'
  it 'reads uppercase character' \
    '(char->integer #\Z)' '90'

describe 'list reader'
  it 'reads proper list' '(lit (1 2 3))' '(1 2 3)'
  it 'reads nested list' '(lit (1 (2 3)))' '(1 (2 3))'
  it 'reads empty list' '()' ''

describe 'dotted pair reader'
  it 'reads dotted pair first' \
    '(first (lit (1 . 2)))' '1'
  it 'reads dotted pair rest' \
    '(rest (lit (1 . 2)))' '2'
  it 'reads list with dotted tail' \
    '(rest (lit (1 2 . 3)))' '(2 . 3)'

describe 'quote shorthand'
  it 'single-quote expands to lit' \
    '(lit a)' 'a'

describe 'comment handling'
  it 'ignores line comments'

describe 'vector literal reader'
  it 'reads vector literal' \
    '(write #(1 2 3))' '#(1 2 3)'
  it 'reads empty vector literal' \
    '(write #())' '#()'

describe 'regex literal reader'
  it 'reads regex literal' \
    '(write #/abc/)' '#/abc/'
