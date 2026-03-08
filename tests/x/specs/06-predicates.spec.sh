# 06-predicates.spec.sh -- Tests for predicates and comparisons
# Spec: Section 6 - Predicates

describe 'eq?'
  it 'returns t for equal symbols' '(eq? (lit a) (lit a))' 't'
  it 'returns t for eq? on same binding' '(do (def x 5) (eq? x x))' 't'

describe '='
  it 'returns t for equal integers' '(= 3 3)' 't'
  it 'returns nil for unequal integers' '(= 3 4)' ''

describe '<'
  it 'returns t for less than' '(< 1 2)' 't'
  it 'returns nil for equal' '(< 2 2)' ''
  it 'returns nil for greater than' '(< 3 2)' ''
  it 'handles negative numbers' '(< -5 0)' 't'

describe '>'
  it 'returns t for greater than' '(> 3 2)' 't'
  it 'returns nil for equal' '(> 2 2)' ''
  it 'returns nil for less than' '(> 1 2)' ''
  it 'handles negative numbers' '(> 0 -5)' 't'

describe '<='
  it 'returns t for less than' '(<= 1 2)' 't'
  it 'returns t for equal' '(<= 2 2)' 't'
  it 'returns nil for greater than' '(<= 3 2)' ''

describe '>='
  it 'returns t for greater than' '(>= 3 2)' 't'
  it 'returns t for equal' '(>= 2 2)' 't'
  it 'returns nil for less than' '(>= 1 2)' ''

describe 'null?'
  it 'returns t for nil' '(null? (lit ()))' 't'
  it 'returns nil for non-nil' '(null? 1)' ''

describe 'pair?'
  it 'returns t for a list' '(pair? (list 1 2))' 't'
  it 'returns t for a pair' '(pair? (pair 1 2))' 't'
  it 'returns nil for an atom' '(pair? 42)' ''

describe 'atom?'
  it 'returns t for an integer' '(atom? 42)' 't'
  it 'returns t for a symbol' '(atom? (lit a))' 't'
  it 'returns nil for a list' '(atom? (list 1 2))' ''

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

describe 'char?'
  it 'returns nil for number' '(null? (char? 42))' 't'
  it 'returns nil for string' '(null? (char? "hello"))' 't'
  it 'returns nil for symbol' '(null? (char? (lit a)))' 't'

describe 'char->integer'
  it 'converts lowercase letter' \
    '(char->integer #\a)' '97'
  it 'converts uppercase letter' \
    '(char->integer #\A)' '65'
  it 'converts digit character' \
    '(char->integer #\0)' '48'

describe 'integer->char'
  it 'converts code point to character' \
    '(integer->char 65)' 'A'
  it 'round-trips with char->integer' \
    '(= (char->integer (integer->char 97)) 97)' 't'
