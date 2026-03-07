# 06-op.spec.sh -- Tests for op (user-level operatives)

describe 'op'
  it 'creates an operative' \
    '(def my-op (op (x) e x)) my-op' '#<op>'
  it 'receives unevaluated args' \
    '(do (def my-op (op (x) e x)) (def a 42) (my-op a))' 'a'
  it 'can eval args explicitly' \
    '(do (def my-op (op (x) e (eval x))) (def a 42) (my-op a))' '42'
  it 'binds env-param to caller env' \
    '(do (def my-op (op (x) e (eval x e))) (def a 42) (my-op a))' '42'
  it 'supports variadic args' \
    '(do (def my-op (op args e (car args))) (my-op 1 2 3))' '1'
  it 'supports dotted formals' \
    '(do (def my-op (op (x . rest) e (list x rest))) (my-op 1 2 3))' '(1 (2 3))'

describe 'op special forms'
  it 'implements when' \
    '(do (def when (op (test . body) e (if (eval test e) (eval (cons (quote do) body) e)))) (when (= 1 1) (+ 10 20)))' '30'
  it 'when returns nil on false' \
    '(do (def when (op (test . body) e (if (eval test e) (eval (cons (quote do) body) e)))) (when (= 1 2) (+ 10 20)))'
  it 'implements define sugar' \
    '(do (def define (op (name-or-form . body) e (if (pair? name-or-form) (eval (list (quote def) (car name-or-form) (cons (quote fn) (cons (cdr name-or-form) body)))) (eval (list (quote def) name-or-form (car body)))))) (define (square x) (* x x)) (square 5))' '25'
  it 'define sugar with simple binding' \
    '(do (def define (op (name-or-form . body) e (if (pair? name-or-form) (eval (list (quote def) (car name-or-form) (cons (quote fn) (cons (cdr name-or-form) body)))) (eval (list (quote def) name-or-form (car body)))))) (define pi 314) pi)' '314'

describe 'eval with env'
  it 'evaluates in given environment' \
    '(do (def x 10) (let ((x 20)) (eval (quote x))))' '20'
  it 'eval without env uses current env' \
    '(eval (quote (+ 1 2)))' '3'

describe 'if without else'
  it 'returns nil when false and no else' \
    '(if (= 1 2) 42)'
  it 'returns then when true and no else' \
    '(if (= 1 1) 42)' '42'
