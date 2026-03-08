# 02-conditionals.spec.sh -- Conditional forms

describe 'if'
  it 'true branch' \
    '(if #t 1 2)' '1'
  it 'false branch' \
    '(if #f 1 2)' '2'
  it 'no else returns nil' \
    '(null? (if #f 1))' 't'
  it 'non-boolean truthy' \
    '(if 42 1 2)' '1'
  it 'nested if' \
    '(if (> 3 2) (if (< 1 0) (quote a) (quote b)) (quote c))' 'b'
  it 'if with expression in test' \
    '(if (= (+ 1 1) 2) (quote yes) (quote no))' 'yes'

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
    '(cond ((= 1 2) 10) ((= 1 1) 20) (#t 30))' '20'
  it 'falls through to else' \
    '(cond ((= 1 2) 10) (#t 99))' '99'
  it 'returns nil when no match' \
    '(null? (cond (#f 1)))' 't'

describe 'and'
  it 'all true returns last' \
    '(and 1 2 3)' '3'
  it 'short-circuits on false' \
    '(null? (and 1 #f 3))' 't'
  it 'no args returns true' \
    '(and)' 't'
  it 'single true arg' \
    '(and 42)' '42'

describe 'or'
  it 'returns first true' \
    '(or 1 2 3)' '1'
  it 'skips false values' \
    '(or #f #f 3)' '3'
  it 'no args returns false' \
    '(null? (or))' 't'
  it 'single false arg' \
    '(null? (or #f))' 't'

describe 'not'
  it 'not true' \
    '(null? (not #t))' 't'
  it 'not false' \
    '(not #f)' 't'
  it 'not on non-boolean' \
    '(null? (not 42))' 't'
