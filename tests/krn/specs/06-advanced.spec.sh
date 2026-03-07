# 06-advanced.spec.sh -- Tests for advanced Kernel forms

describe '$letrec'
  it 'binds recursive function' \
    '($letrec ((fact ($lambda (n) ($if (= n 0) 1 (* n (fact (- n 1))))))) (fact 5))' '120'
  it 'mutual recursion' \
    '($letrec ((even? ($lambda (n) ($if (= n 0) #t (odd? (- n 1))))) (odd? ($lambda (n) ($if (= n 0) #f (even? (- n 1)))))) (even? 10))' 't'
  it 'mutual recursion odd' \
    '($letrec ((even? ($lambda (n) ($if (= n 0) #t (odd? (- n 1))))) (odd? ($lambda (n) ($if (= n 0) #f (even? (- n 1)))))) (odd? 7))' 't'

describe 'get-current-environment'
  it 'captures bindings for eval' \
    '($define! gce-x 42) (eval (quote gce-x) (get-current-environment))' '42'
  it 'environment reflects current state' \
    '($define! gce-y 10) ($define! gce-z (+ gce-y 5)) (eval (quote gce-z) (get-current-environment))' '15'

describe 'make-environment'
  it 'creates empty environment' \
    '(null? (make-environment))' 't'
