# 04-logic.spec.sh -- Tests for logic and control flow
# Spec: Section 4 - Logic & Control

describe 'and'
  it 'returns t for empty and' '(and)' 't'
  it 'returns value for single truthy' '(and 1)' '1'
  it 'returns nil for single falsy' '(and (lit ()))' ''
  it 'returns last value when all truthy' '(and 1 2 3)' '3'
  it 'returns nil on first falsy' '(and 1 (lit ()) 3)' ''
  it 'returns actual value not t' '(and 1 "yes")' '"yes"'
  it 'short-circuits evaluation' \
    '(do (def x 0) (and (lit ()) (set x 1)) x)' '0'
  it 'short-circuits before error' \
    '(and (lit ()) (error "boom"))' ''
  it 'def in last position persists' \
    '(do (and t (def x 99)) x)' '99'

describe 'or'
  it 'returns nil for empty or' '(or)' ''
  it 'returns value for single truthy' '(or 1)' '1'
  it 'returns nil for single falsy' '(or (lit ()))' ''
  it 'returns first truthy value' '(or (lit ()) 2 3)' '2'
  it 'returns nil when all falsy' '(or (lit ()) (lit ()))' ''
  it 'returns actual value not t' '(or (lit ()) "yes")' '"yes"'
  it 'short-circuits evaluation' \
    '(do (def x 0) (or 1 (set x 1)) x)' '0'
  it 'short-circuits before error' \
    '(or 1 (error "boom"))' '1'
  it 'def in last position persists' \
    '(do (or (lit ()) (def x 77)) x)' '77'

describe 'not'
  it 'returns t for nil' '(not (lit ()))' 't'
  it 'returns nil for non-nil' '(not 1)' ''

describe 'nested and/or'
  it 'nested and/or returns correct value' \
    '(and (or (lit ()) 1) (or (lit ()) 2))' '2'
  it 'or of ands returns correct value' \
    '(or (and (lit ()) 1) (and 1 2))' '2'
  it 'and of ors returns correct value' \
    '(and (or 1 2) (or 3 4))' '3'
  it 'deeply nested logic' \
    '(or (and (or (lit ()) (lit ())) 1) (and (or (lit ()) 5) 6))' '6'

describe 'guard'
  it 'returns body result when no error' \
    '(guard (e (lit caught)) (+ 1 2))' '3'
  it 'catches explicit error' \
    '(guard (e e) (error "boom"))' '"boom"'
  it 'runs handler body on error' \
    '(guard (e (list (lit caught) e)) (error "oops"))' '(caught "oops")'
  it 'catches unbound symbol' \
    '(guard (e (lit handled)) no-such-var)' 'handled'
  it 'returns last body form' \
    '(guard (e e) 1 2 3)' '3'
  it 'handler sees error value' \
    '(guard (e (list (lit err) e)) (error 42))' '(err 42)'

describe 'error'
  it 'signals with string' \
    '(guard (e e) (error "test"))' '"test"'
  it 'signals with number' \
    '(guard (e e) (error 99))' '99'
  it 'signals from nested call' \
    '(do (def boom (fn () (error "inner"))) (guard (e e) (boom)))' '"inner"'

describe 'nested guard'
  it 'inner guard catches inner error' \
    '(guard (e (lit outer)) (guard (e (lit inner)) (error "x")))' 'inner'
  it 'outer guard catches when inner has no guard' \
    '(guard (e (list (lit outer) e)) (do (def f (fn () (error "deep"))) (f)))' '(outer "deep")'
  it 'inner guard does not catch outer body error' \
    '(guard (e (list (lit caught) e)) (+ 1 2) (error "after"))' '(caught "after")'

describe 'guard with env restore'
  it 'restores env after error in let' \
    '(do (def x 10) (guard (e x) (let ((x 20)) (error "err"))))' '10'
  it 'restores env after error in fn' \
    '(do (def x 5) (guard (e x) ((fn () (error "err")))))' '5'
