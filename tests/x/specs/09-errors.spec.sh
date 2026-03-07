# 09-errors.spec.sh -- Tests for guard and error

describe 'guard'
  it 'returns body result when no error' \
    '(guard (e (quote caught)) (+ 1 2))' '3'
  it 'catches explicit error' \
    '(guard (e e) (error "boom"))' '"boom"'
  it 'runs handler body on error' \
    '(guard (e (list (quote caught) e)) (error "oops"))' '(caught "oops")'
  it 'catches unbound symbol' \
    '(guard (e (quote handled)) no-such-var)' 'handled'
  it 'returns last body form' \
    '(guard (e e) 1 2 3)' '3'
  it 'handler sees error value' \
    '(guard (e (list (quote err) e)) (error 42))' '(err 42)'

describe 'error'
  it 'signals with string' \
    '(guard (e e) (error "test"))' '"test"'
  it 'signals with number' \
    '(guard (e e) (error 99))' '99'
  it 'signals from nested call' \
    '(do (def boom (fn () (error "inner"))) (guard (e e) (boom)))' '"inner"'

describe 'nested guard'
  it 'inner guard catches inner error' \
    '(guard (e (quote outer)) (guard (e (quote inner)) (error "x")))' 'inner'
  it 'outer guard catches when inner has no guard' \
    '(guard (e (list (quote outer) e)) (do (def f (fn () (error "deep"))) (f)))' '(outer "deep")'
  it 'inner guard does not catch outer body error' \
    '(guard (e (list (quote caught) e)) (+ 1 2) (error "after"))' '(caught "after")'

describe 'guard with env restore'
  it 'restores env after error in let' \
    '(do (def x 10) (guard (e x) (let ((x 20)) (error "err"))))' '10'
  it 'restores env after error in fn' \
    '(do (def x 5) (guard (e x) ((fn () (error "err")))))' '5'
