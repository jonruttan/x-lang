# 10-reader.spec.sh -- Tests for reader syntax
# Spec: Section 10 - Reader Syntax

describe 'integer reader'
  it 'reads positive integers' '99' '99'
  it 'reads negative integers' '-99' '-99'
  it 'reads zero' '0' '0'

describe 'string reader'
  it 'reads simple string' '"hello"' '"hello"'
  it 'reads empty string' '""' '""'
  it 'reads string with escaped quote' '"a\"b"' '"a\"b"'
  it 'reads string with escaped backslash' '"a\\\\b"' '"a\\\\b"'
  it 'reads string with newline escape' '(string-length "a\nb")' '3'
  it 'reads string with tab escape' '(string-length "a\tb")' '3'
  it 'reads string with carriage return escape' '(string-length "a\rb")' '3'
  it 'reads string with hex escape' '(= (char->integer (string-ref "\x41" 0)) 65)' 't'
  it 'preserves unknown escape sequences' '(string-length "\q")' '2'

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
  it 'reads named character space' \
    '(char->integer #\space)' '32'
  it 'reads named character newline' \
    '(char->integer #\newline)' '10'
  it 'reads named character tab' \
    '(char->integer #\tab)' '9'

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
