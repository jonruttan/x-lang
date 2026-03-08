# 07-strings.spec.sh -- Tests for string operations
# Spec: Section 7 - Strings

describe 'string-length'
  it 'returns length of string' \
    '(string-length "hello")' '5'
  it 'returns 0 for empty string' \
    '(string-length "")' '0'

describe 'string-ref'
  it 'returns character at index' \
    '(string-ref "hello" 0)' 'h'
  it 'returns middle character' \
    '(string-ref "hello" 2)' 'l'

describe 'string-append'
  it 'concatenates two strings' \
    '(string-append "hello" " world")' '"hello world"'
  it 'appends to empty string' \
    '(string-append "" "abc")' '"abc"'

describe 'substring'
  it 'extracts substring' \
    '(substring "hello world" 6 11)' '"world"'
  it 'extracts from start' \
    '(substring "hello" 0 3)' '"hel"'
  it 'single character' \
    '(substring "abc" 1 2)' '"b"'

describe 'string=?'
  it 'returns t for equal strings' \
    '(string=? "hello" "hello")' 't'
  it 'returns nil for different strings' \
    '(string=? "hello" "world")' ''

describe 'string->symbol'
  it 'converts string to symbol' \
    '(string->symbol "hello")' 'hello'
  it 'interned equality' \
    '(eq? (string->symbol "hello") (lit hello))' 't'

describe 'symbol->string'
  it 'converts symbol to string' \
    '(symbol->string (lit hello))' '"hello"'
  it 'round-trip string->symbol->string' \
    '(symbol->string (string->symbol "test"))' '"test"'

describe 'number->string'
  it 'converts positive number' \
    '(number->string 42)' '"42"'
  it 'converts zero' \
    '(number->string 0)' '"0"'
  it 'converts negative number' \
    '(number->string -7)' '"-7"'

describe 'string->number'
  it 'parses positive number' \
    '(string->number "42")' '42'
  it 'parses negative number' \
    '(string->number "-5")' '-5'
  it 'parses zero' \
    '(string->number "0")' '0'

describe 'string composition'
  it 'round-trips number->string->number' \
    '(string->number (number->string 99))' '99'
  it 'builds string from parts' \
    '(string-length (string-append "abc" "defgh"))' '8'
