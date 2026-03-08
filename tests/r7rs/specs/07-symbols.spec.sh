# 07-symbols.spec.sh -- R7RS 6.5 Symbols

describe 'symbol?'
  it 'symbol? on symbol' \
    '(symbol? (quote foo))' 't'
  it 'symbol? on string' \
    '(null? (symbol? "foo"))' 't'
  it 'symbol? on number' \
    '(null? (symbol? 42))' 't'
  it 'symbol? on list' \
    '(null? (symbol? (list 1 2)))' 't'
  it 'symbol? on boolean' \
    '(symbol? #t)' 't'

describe 'symbol=?'
  it 'symbol=? same symbols' \
    '(symbol=? (quote a) (quote a))' 't'
  it 'symbol=? different symbols' \
    '(null? (symbol=? (quote a) (quote b)))' 't'

describe 'symbol conversion'
  it 'symbol->string' \
    '(symbol->string (quote hello))' '"hello"'
  it 'string->symbol' \
    '(eq? (string->symbol "hello") (quote hello))' 't'
  it 'roundtrip symbol->string->symbol' \
    '(eq? (string->symbol (symbol->string (quote foo))) (quote foo))' 't'
