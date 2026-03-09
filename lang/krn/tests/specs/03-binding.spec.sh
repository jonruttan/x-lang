# 03-binding.spec.sh -- Kernel binding forms

describe '$let'
  it 'binds locally' \
    '($let ((x 10)) x)' '10'
  it 'multiple bindings' \
    '($let ((x 1) (y 2)) (+ x y))' '3'

describe '$let*'
  it 'sequential binding' \
    '($let* ((x 1) (y (+ x 1))) (+ x y))' '3'
  it 'nested reference' \
    '($let* ((a 2) (b (* a 3)) (c (+ a b))) c)' '8'
  it 'three-level chain' \
    '($let* ((x 1) (y (+ x 1)) (z (+ y 1))) z)' '3'
