# 11-base.spec.sh -- Tests for base object manipulation

describe 'make-base'
  it 'creates a base object' \
    '(pair? (make-base))' ''
  it 'new base has arithmetic' \
    '(do (def b (make-base)) (base-eval b (quote (+ 1 2))))' '3'
  it 'new base has def' \
    '(do (def b (make-base)) (base-eval b (quote (def x 10))) (base-eval b (quote x)))' '10'

describe 'base isolation'
  it 'parent binding not visible in child' \
    '(do (def x 10) (def b (make-base)) (guard (e (quote isolated)) (base-eval b (quote x))))' 'isolated'
  it 'child binding not visible in parent' \
    '(do (def b (make-base)) (base-eval b (quote (def x 42))) (guard (e (quote isolated)) x))' 'isolated'
  it 'two bases are independent' \
    '(do (def a (make-base)) (def b (make-base)) (base-eval a (quote (def x 1))) (base-eval b (quote (def x 2))) (+ (base-eval a (quote x)) (base-eval b (quote x))))' '3'

describe 'base-eval'
  it 'evaluates arithmetic' \
    '(do (def b (make-base)) (base-eval b (quote (* 6 7))))' '42'
  it 'evaluates closures' \
    '(do (def b (make-base)) (base-eval b (quote (do (def f (fn (x) (* x x))) (f 5)))))' '25'
  it 'propagates errors to parent guard' \
    '(do (def b (make-base)) (guard (e (quote caught)) (base-eval b (quote (error "boom")))))' 'caught'

describe 'base-bind'
  it 'binds a value in target base' \
    '(do (def b (make-base)) (base-bind b (quote x) 42) (base-eval b (quote x)))' '42'
  it 'binds a list in target base' \
    '(do (def b (make-base)) (base-bind b (quote xs) (list 1 2 3)) (base-eval b (quote (car xs))))' '1'
  it 'does not affect parent' \
    '(do (def b (make-base)) (base-bind b (quote z) 99) (guard (e (quote ok)) z))' 'ok'
