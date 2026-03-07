# 13-vectors.spec.sh -- Tests for vector type and operations

describe 'vector'
  it 'creates a vector from arguments' \
    '(write (vector 1 2 3))' '#(1 2 3)'
  it 'creates a single-element vector' \
    '(write (vector 42))' '#(42)'
  it 'creates an empty vector' \
    '(write (vector))' '#()'

describe 'vector indexing'
  it 'indexes from the start' \
    '((vector 10 20 30) 1)' '20'
  it 'indexes first element' \
    '((vector 10 20 30) 0)' '10'
  it 'indexes last element' \
    '((vector 10 20 30) 2)' '30'
  it 'indexes from the end with negative' \
    '((vector 10 20 30) -1)' '30'

describe 'vector?'
  it 'returns t for a vector' \
    '(vector? (vector 1))' 't'
  it 'returns nil for a list' \
    '(if (vector? (list 1)) "yes" "no")' '"no"'
  it 'returns nil for an integer' \
    '(if (vector? 42) "yes" "no")' '"no"'

describe 'vector-ref'
  it 'retrieves element by index' \
    '(vector-ref (vector 10 20 30) 1)' '20'

describe 'vector-length'
  it 'returns the length of a vector' \
    '(vector-length (vector 1 2 3))' '3'
  it 'returns 0 for empty vector' \
    '(vector-length (vector))' '0'

describe 'vector->list'
  it 'converts a vector to a list' \
    '(vector->list (vector 1 2 3))' '(1 2 3)'

describe 'list->vector'
  it 'converts a list to a vector' \
    '(write (list->vector (list 4 5 6)))' '#(4 5 6)'

describe 'make-vector'
  it 'creates a vector of repeated values' \
    '(write (make-vector 3 0))' '#(0 0 0)'
  it 'creates a vector with custom fill' \
    '(write (make-vector 2 7))' '#(7 7)'

describe 'type-name'
  it 'returns VECTOR for a vector' \
    '(type-name (vector 1))' '"VECTOR"'
  it 'returns LIST for a list' \
    '(type-name (list 1 2))' '"LIST"'

describe 'make-type'
  it 'creates a custom type with call handler' \
    '(do (def %counter (make-type "COUNTER" (list (pair (lit call) (fn (self . args) (+ (first self) (first args))))))) (def c (make-instance %counter 10)) (c 5))' '15'
  it 'creates a custom type with write handler' \
    '(do (def %tag (make-type "TAG" (list (pair (lit write) (fn (self) (display "<") (display (first self)) (display ">")))))) (write (make-instance %tag "hello")))' '<hello>'
