# 09-strings.spec.sh -- R7RS 6.7 Strings

describe 'string basics'
  it 'string? on string' \
    '(string? "hello")' 't'
  it 'string? on non-string' \
    '(null? (string? 42))' 't'
  it 'string? on symbol' \
    '(null? (string? (quote hello)))' 't'
  it 'string-length' \
    '(string-length "hello")' '5'
  it 'string-length empty' \
    '(string-length "")' '0'
  it 'string-ref first' \
    '(string-ref "hello" 0)' 'h'
  it 'string-ref last' \
    '(string-ref "hello" 4)' 'o'
  it 'string-ref middle' \
    '(string-ref "abcde" 2)' 'c'

describe 'string operations'
  it 'string-append two' \
    '(string-append "hello" " world")' '"hello world"'
  it 'string-append empty' \
    '(string-append "" "abc")' '"abc"'
  it 'string-append both empty' \
    '(string-append "" "")' '""'
  it 'substring' \
    '(substring "hello world" 6 11)' '"world"'
  it 'substring from start' \
    '(substring "hello" 0 3)' '"hel"'
  it 'substring empty' \
    '(substring "hello" 2 2)' '""'
  it 'substring full' \
    '(substring "hello" 0 5)' '"hello"'
  it 'string-copy' \
    '(string-copy "hello")' '"hello"'
  it 'string-copy is equal' \
    '(equal? (string-copy "test") "test")' 't'

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

describe 'string case-insensitive comparison'
  it 'string-ci=? equal same case' \
    '(string-ci=? "abc" "abc")' 't'
  it 'string-ci=? equal different case' \
    '(string-ci=? "Hello" "hello")' 't'
  it 'string-ci=? not equal' \
    '(null? (string-ci=? "abc" "abd"))' 't'
  it 'string-ci<? less' \
    '(string-ci<? "abc" "ABD")' 't'
  it 'string-ci>? greater' \
    '(string-ci>? "ABD" "abc")' 't'
  it 'string-ci<=? equal different case' \
    '(string-ci<=? "ABC" "abc")' 't'
  it 'string-ci>=? equal different case' \
    '(string-ci>=? "abc" "ABC")' 't'

describe 'string conversion'
  it 'symbol->string' \
    '(symbol->string (quote hello))' '"hello"'
  it 'string->symbol' \
    '(eq? (string->symbol "hello") (quote hello))' 't'
  it 'number->string' \
    '(number->string 42)' '"42"'
  it 'string->number valid' \
    '(string->number "42")' '42'
  it 'string->list' \
    '(string->list "abc")' '(a b c)'
  it 'string->list empty' \
    '(null? (string->list ""))' 't'
  it 'string->list single' \
    '(string->list "x")' '(x)'

describe 'string-for-each'
  it 'string-for-each accumulates' \
    '(define acc 0) (string-for-each (lambda (c) (set! acc (+ acc 1))) "hello") acc' '5'
