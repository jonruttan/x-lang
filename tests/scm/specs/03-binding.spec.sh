# 03-binding.spec.sh -- Binding forms

describe 'let'
  it 'creates local bindings' \
    '(let ((x 10) (y 20)) (+ x y))' '30'
  it 'does not leak bindings' \
    '(define x 1) (let ((x 99)) x) x' '1'

describe 'let*'
  it 'creates sequential bindings' \
    '(let* ((x 1) (y (+ x 1))) (+ x y))' '3'
  it 'later bindings see earlier ones' \
    '(let* ((a 10) (b (* a 2)) (c (+ b 5))) c)' '25'
  it 'does not leak bindings' \
    '(define x 1) (let* ((x 99) (y x)) y) x' '1'
