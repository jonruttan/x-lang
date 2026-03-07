# 02-conditionals.spec.sh -- Conditional forms

describe 'when'
  it 'evaluates body when true' \
    '(when (= 1 1) (+ 10 20))' '30'
  it 'returns nil when false' \
    '(null? (when (= 1 2) 42))' 't'
  it 'supports multiple body forms' \
    '(when #t 1 2 3)' '3'

describe 'unless'
  it 'evaluates body when false' \
    '(unless (= 1 2) 99)' '99'
  it 'returns nil when true' \
    '(null? (unless (= 1 1) 42))' 't'

describe 'cond'
  it 'evaluates matching clause' \
    '(cond ((= 1 2) 10) ((= 1 1) 20) (t 30))' '20'
  it 'falls through to else' \
    '(cond ((= 1 2) 10) (t 99))' '99'
