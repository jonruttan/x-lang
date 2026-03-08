# 14-promises.spec.sh -- R7RS 4.2.5 Delayed evaluation

describe 'promise basics'
  it 'delay creates promise' \
    '(promise? (delay 42))' 't'
  it 'promise? on non-promise' \
    '(null? (promise? 42))' 't'
  it 'promise? on list' \
    '(null? (promise? (list 1 2)))' 't'

describe 'force'
  it 'force simple value' \
    '(force (delay 42))' '42'
  it 'force expression' \
    '(force (delay (+ 1 2)))' '3'
  it 'force non-promise' \
    '(force 42)' '42'
  it 'force twice same result' \
    '(define p (delay (* 6 7))) (list (force p) (force p))' '(42 42)'

describe 'promise memoization'
  it 'delay memoizes result' \
    '(define count 0) (define p (delay (begin (set! count (+ count 1)) count))) (force p) (force p) count' '1'
  it 'side effect runs once' \
    '(define n 0) (define p (delay (begin (set! n (+ n 10)) n))) (force p) (force p) (force p) n' '10'

describe 'make-promise'
  it 'make-promise wraps value' \
    '(force (make-promise 42))' '42'
  it 'make-promise is idempotent on promise' \
    '(define p (delay 99)) (eq? (make-promise p) p)' 't'
  it 'make-promise result forceable' \
    '(force (make-promise (+ 10 20)))' '30'
