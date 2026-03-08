# 13-iteration.spec.sh -- R7RS 4.2.4 Iteration

describe 'do basic'
  it 'do loop counting' \
    '(do ((i 0 (+ i 1)))
         ((= i 5) i))' '5'
  it 'do loop sum' \
    '(do ((i 0 (+ i 1))
          (sum 0 (+ sum i)))
         ((= i 5) sum))' '10'
  it 'do with no result expr' \
    '(define x 0) (do ((i 0 (+ i 1))) ((= i 3)) (set! x (+ x i))) x' '3'
  it 'do building list' \
    '(do ((i 0 (+ i 1))
          (acc () (cons i acc)))
         ((= i 5) (reverse acc)))' '(0 1 2 3 4)'

describe 'do multiple variables'
  it 'do two counters' \
    '(do ((i 0 (+ i 1))
          (j 10 (- j 1)))
         ((= i 5) (list i j)))' '(5 5)'
  it 'do no-step variable' \
    '(do ((n 42)
          (i 0 (+ i 1)))
         ((= i 3) n))' '42'

describe 'do body'
  it 'do body side effects' \
    '(define result ())
     (do ((i 0 (+ i 1)))
         ((= i 4))
       (set! result (cons (* i i) result)))
     (reverse result)' '(0 1 4 9)'
  it 'do body multiple forms' \
    '(define a 0)
     (define b 0)
     (do ((i 0 (+ i 1)))
         ((= i 3))
       (set! a (+ a 1))
       (set! b (+ b 2)))
     (list a b)' '(3 6)'

describe 'do patterns'
  it 'do factorial' \
    '(do ((i 1 (+ i 1))
          (fact 1 (* fact i)))
         ((> i 10) fact))' '3628800'
  it 'do fibonacci' \
    '(do ((i 0 (+ i 1))
          (a 0 b)
          (b 1 (+ a b)))
         ((= i 10) a))' '55'
  it 'do countdown' \
    '(do ((i 5 (- i 1))
          (acc () (cons i acc)))
         ((= i 0) acc))' '(1 2 3 4 5)'
  it 'do immediate exit' \
    '(do ((i 0 (+ i 1)))
         ((= i 0) (quote done)))' 'done'
  it 'do with string building' \
    '(do ((i 0 (+ i 1))
          (s "" (string-append s "x")))
         ((= i 3) s))' '"xxx"'
