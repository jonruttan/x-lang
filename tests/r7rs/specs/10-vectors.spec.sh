# 10-vectors.spec.sh -- R7RS 6.8 Vectors

describe 'vector basics'
  it 'vector constructor' \
    '(vector 1 2 3)' '#(1 2 3)'
  it 'vector? on vector' \
    '(vector? (vector 1 2))' 't'
  it 'vector? on list' \
    '(null? (vector? (list 1 2)))' 't'
  it 'vector? on number' \
    '(null? (vector? 42))' 't'
  it 'vector empty' \
    '(vector)' '#()'

describe 'vector access'
  it 'vector-ref first' \
    '(vector-ref (vector 10 20 30) 0)' '10'
  it 'vector-ref middle' \
    '(vector-ref (vector 10 20 30) 1)' '20'
  it 'vector-ref last' \
    '(vector-ref (vector 10 20 30) 2)' '30'
  it 'vector-length three' \
    '(vector-length (vector 1 2 3))' '3'
  it 'vector-length empty' \
    '(vector-length (vector))' '0'
  it 'vector-length one' \
    '(vector-length (vector 42))' '1'

describe 'make-vector'
  it 'make-vector with fill' \
    '(vector->list (make-vector 3 0))' '(0 0 0)'
  it 'make-vector with value' \
    '(vector-ref (make-vector 5 42) 3)' '42'
  it 'make-vector length' \
    '(vector-length (make-vector 4 0))' '4'

describe 'vector conversion'
  it 'vector->list' \
    '(vector->list (vector 1 2 3))' '(1 2 3)'
  it 'vector->list empty' \
    '(null? (vector->list (vector)))' 't'
  it 'list->vector' \
    '(list->vector (list 1 2 3))' '#(1 2 3)'
  it 'list->vector empty' \
    '(list->vector ())' '#()'
  it 'roundtrip list->vector->list' \
    '(vector->list (list->vector (list 4 5 6)))' '(4 5 6)'

describe 'vector-copy'
  it 'vector-copy basic' \
    '(vector-copy (vector 1 2 3))' '#(1 2 3)'
  it 'vector-copy is equal' \
    '(equal? (vector->list (vector-copy (vector 1 2))) (list 1 2))' 't'

describe 'vector-append'
  it 'vector-append two' \
    '(vector-append (vector 1 2) (vector 3 4))' '#(1 2 3 4)'
  it 'vector-append empty' \
    '(vector-append (vector) (vector 1 2))' '#(1 2)'
  it 'vector-append nested' \
    '(vector-append (vector 1) (vector-append (vector 2) (vector 3)))' '#(1 2 3)'

describe 'vector-map'
  it 'vector-map double' \
    '(vector-map (lambda (x) (* x 2)) (vector 1 2 3))' '#(2 4 6)'
  it 'vector-map increment' \
    '(vector-map (lambda (x) (+ x 10)) (vector 1 2 3))' '#(11 12 13)'

describe 'vector-for-each'
  it 'vector-for-each accumulates' \
    '(define sum 0) (vector-for-each (lambda (x) (set! sum (+ sum x))) (vector 1 2 3)) sum' '6'
