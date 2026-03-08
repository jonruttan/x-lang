# 11-vectors.spec.sh -- Vector operations

describe 'vector basics'
  it 'vector constructor' \
    '(vector 1 2 3)' '#(1 2 3)'
  it 'vector? on vector' \
    '(vector? (vector 1 2))' 't'
  it 'vector? on list' \
    '(null? (vector? (list 1 2)))' 't'
  it 'vector? on non-vector' \
    '(null? (vector? 42))' 't'

describe 'vector access'
  it 'vector-ref first' \
    '(vector-ref (vector 10 20 30) 0)' '10'
  it 'vector-ref middle' \
    '(vector-ref (vector 10 20 30) 1)' '20'
  it 'vector-ref last' \
    '(vector-ref (vector 10 20 30) 2)' '30'
  it 'vector-length' \
    '(vector-length (vector 1 2 3))' '3'
  it 'vector-length empty' \
    '(vector-length (vector))' '0'

describe 'vector conversion'
  it 'vector->list' \
    '(vector->list (vector 1 2 3))' '(1 2 3)'
  it 'vector->list empty' \
    '(null? (vector->list (vector)))' 't'
  it 'list->vector' \
    '(list->vector (list 1 2 3))' '#(1 2 3)'

describe 'make-vector'
  it 'make-vector with fill' \
    '(vector->list (make-vector 3 0))' '(0 0 0)'
  it 'make-vector with value' \
    '(vector-ref (make-vector 5 42) 3)' '42'
