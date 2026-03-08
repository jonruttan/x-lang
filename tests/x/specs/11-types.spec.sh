# 11-types.spec.sh -- Tests for type extension system
# Spec: Section 11 - Type Extension

describe 'make-type'
  it 'creates a custom type with call handler' \
    '(do (def %counter (make-type "COUNTER" (list (pair (lit call) (fn (self . args) (+ (first self) (first args))))))) (def c (make-instance %counter 10)) (c 5))' '15'
  it 'creates a custom type with write handler' \
    '(do (def %tag (make-type "TAG" (list (pair (lit write) (fn (self) (display "<") (display (first self)) (display ">")))))) (write (make-instance %tag "hello")))' '<hello>'

describe 'make-instance'
  it 'stores data accessible via first' \
    '(do (def my-t (make-type "MY-T" (list))) (def obj (make-instance my-t 42)) (first obj))' '42'
  it 'instance self-evaluates' \
    '(do (def my-t (make-type "MY-T" (list))) (def obj (make-instance my-t 42)) (eq? obj obj))' 't'

describe 'type?'
  it 'returns t for matching type' \
    '(do (def my-t (make-type "MY-T" (list))) (type? (make-instance my-t 42) my-t))' 't'
  it 'returns nil for wrong type' \
    '(do (def t1 (make-type "T1" (list))) (def t2 (make-type "T2" (list))) (if (type? (make-instance t1 1) t2) "y" "n"))' '"n"'
  it 'returns nil for non-instance' \
    '(do (def my-t (make-type "MY-T" (list))) (if (type? 42 my-t) "y" "n"))' '"n"'

describe 'type-name'
  it 'returns VECTOR for a vector' \
    '(type-name (vector 1))' '"VECTOR"'
  it 'returns LIST for a list' \
    '(type-name (list 1 2))' '"LIST"'
  it 'returns INTEGER for a number' \
    '(type-name 42)' '"INTEGER"'
  it 'returns STRING for a string' \
    '(type-name "hi")' '"STRING"'
  it 'returns custom type name' \
    '(do (def my-t (make-type "MY-T" (list))) (type-name (make-instance my-t 1)))' '"MY-T"'

describe 'score-match'
  it 'sets score length and reader'
