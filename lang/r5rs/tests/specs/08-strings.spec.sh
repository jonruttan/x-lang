# 08-strings.spec.sh -- String operations

describe 'string basics'
  it 'string? on string' \
    '(string? "hello")' 't'
  it 'string? on non-string' \
    '(null? (string? 42))' 't'
  it 'string-length' \
    '(string-length "hello")' '5'
  it 'string-length empty' \
    '(string-length "")' '0'
  it 'string-ref first' \
    '(string-ref "hello" 0)' 'h'
  it 'string-ref last' \
    '(string-ref "hello" 4)' 'o'

describe 'string operations'
  it 'string-append two' \
    '(string-append "hello" " world")' '"hello world"'
  it 'string-append empty' \
    '(string-append "" "abc")' '"abc"'
  it 'substring' \
    '(substring "hello world" 6 11)' '"world"'
  it 'substring from start' \
    '(substring "hello" 0 3)' '"hel"'
  it 'substring empty' \
    '(substring "hello" 2 2)' '""'
  it 'string-copy' \
    '(string-copy "hello")' '"hello"'
  it 'string-copy is equal' \
    '(define s "hello") (equal? s (string-copy s))' 't'

describe 'string comparison'
  it 'string=? equal' \
    '(string=? "abc" "abc")' 't'
  it 'string=? not equal' \
    '(null? (string=? "abc" "abd"))' 't'
  it 'string<? less' \
    '(string<? "abc" "abd")' 't'
  it 'string<? not less' \
    '(null? (string<? "abd" "abc"))' 't'
  it 'string<? prefix is less' \
    '(string<? "abc" "abcd")' 't'
  it 'string>? greater' \
    '(string>? "abd" "abc")' 't'
  it 'string<=? equal' \
    '(string<=? "abc" "abc")' 't'
  it 'string<=? less' \
    '(string<=? "abc" "abd")' 't'
  it 'string>=? equal' \
    '(string>=? "abc" "abc")' 't'
  it 'string>=? greater' \
    '(string>=? "abd" "abc")' 't'

describe 'string conversion'
  it 'symbol->string' \
    '(symbol->string (quote hello))' '"hello"'
  it 'string->symbol' \
    '(eq? (string->symbol "hello") (quote hello))' 't'
  it 'number->string' \
    '(number->string 42)' '"42"'
  it 'string->number' \
    '(string->number "42")' '42'
  it 'string->list' \
    '(string->list "abc")' '(a b c)'
  it 'string->list empty' \
    '(null? (string->list ""))' 't'
