# 12-exceptions.spec.sh -- R7RS 6.11 Exceptions

describe 'error'
  it 'error raises exception' \
    '(guard (e #t) (error "boom"))' 't'
  it 'error with string message' \
    '(guard (e e) (error "boom"))' '"boom"'
  it 'error with number' \
    '(guard (e e) (error 42))' '42'
  it 'error with symbol' \
    '(guard (e e) (error (quote oops)))' 'oops'

describe 'guard'
  it 'guard catches error' \
    '(guard (e (list (quote caught) e)) (error "fail"))' '(caught "fail")'
  it 'guard returns body when no error' \
    '(guard (e (quote caught)) (+ 1 2))' '3'
  it 'guard with multiple body forms' \
    '(guard (e (quote caught)) 1 2 (+ 3 4))' '7'
  it 'guard handler uses error value' \
    '(guard (e (+ e 1)) (error 41))' '42'
  it 'guard handler builds list' \
    '(guard (e (list (quote err) e)) (error (list 1 2 3)))' '(err (1 2 3))'

describe 'guard with computation'
  it 'guard in let' \
    '(let ((x 10)) (guard (e (+ x 1)) (error "fail")))' '11'
  it 'guard in define' \
    '(define (safe-op) (guard (e 0) (error "fail"))) (safe-op)' '0'
  it 'guard passes through normal value' \
    '(guard (e (quote bad)) (list 1 2 3))' '(1 2 3)'
  it 'guard passes through arithmetic' \
    '(guard (e (quote bad)) (* 6 7))' '42'
