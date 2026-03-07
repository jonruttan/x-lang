# 07-io.spec.sh -- Tests for I/O primitives and type conversion

describe 'write'
  it 'writes an integer' \
    '(write 42)' '42'
  it 'writes a string with quotes' \
    '(write "hello")' '"hello"'
  it 'writes a symbol' \
    '(write (lit hello))' 'hello'
  it 'writes a list' \
    '(write (lit (1 2 3)))' '(1 2 3)'
  it 'writes a nested list' \
    '(write (lit (1 (2 3))))' '(1 (2 3))'
  it 'returns nil' \
    '(do (def r (write 42)) (newline) (null? r))' 't'

describe 'display'
  it 'displays an integer' \
    '(display 42)' '42'
  it 'displays a string without quotes' \
    '(display "hello")' 'hello'
  it 'displays a symbol' \
    '(display (lit hello))' 'hello'
  it 'displays a list' \
    '(display (lit (1 2 3)))' '(1 2 3)'
  it 'returns nil' \
    '(do (def r (display 42)) (newline) (null? r))' 't'

describe 'newline'
  it 'returns nil' \
    '(null? (newline))' 't'

describe 'read'
  it 'reads an integer' \
    '(do (def x (read)) x) 42' '42'
  it 'reads a symbol' \
    '(do (def x (read)) x) hello' 'hello'
  it 'reads a list' \
    '(do (def x (read)) x) (1 2 3)' '(1 2 3)'
  it 'reads a string' \
    '(do (def x (read)) x) "world"' '"world"'

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

describe 'number?'
  it 'true for integer' \
    '(number? 42)' 't'
  it 'false for string' \
    '(null? (number? "hello"))' 't'

describe 'string?'
  it 'true for string' \
    '(string? "hello")' 't'
  it 'false for integer' \
    '(null? (string? 42))' 't'

describe 'symbol?'
  it 'true for symbol' \
    '(symbol? (lit hello))' 't'
  it 'false for integer' \
    '(null? (symbol? 42))' 't'

describe 'procedure?'
  it 'true for fn' \
    '(procedure? (fn (x) x))' 't'
  it 'true for builtin' \
    '(procedure? first)' 't'
  it 'false for integer' \
    '(null? (procedure? 42))' 't'
