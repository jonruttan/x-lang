# 08-io.spec.sh -- Tests for I/O primitives
# Spec: Section 8 - I/O

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

describe 'read-char'
  it 'reads a single character' \
    '(do (def c (read-char)) (char? c))' 't'
  it 'returns nil on end of input' \
    '(do (read-char) (null? (read-char)))' 't'

describe 'gc'
  it 'returns nil' '(null? (gc))' 't'
