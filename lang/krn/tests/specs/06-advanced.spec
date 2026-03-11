
== $letrec

-- binds recursive function
($letrec ((fact ($lambda (n) ($if (= n 0) 1 (* n (fact (- n 1))))))) (fact 5))
---
120

-- mutual recursion
($letrec ((even? ($lambda (n) ($if (= n 0) #t (odd? (- n 1))))) (odd? ($lambda (n) ($if (= n 0) #f (even? (- n 1)))))) (even? 10))
---
t

-- mutual recursion odd
($letrec ((even? ($lambda (n) ($if (= n 0) #t (odd? (- n 1))))) (odd? ($lambda (n) ($if (= n 0) #f (even? (- n 1)))))) (odd? 7))
---
t

== get-current-environment

-- captures bindings for eval
($define! gce-x 42) (eval (quote gce-x) (get-current-environment))
---
42

-- environment reflects current state
($define! gce-y 10) ($define! gce-z (+ gce-y 5)) (eval (quote gce-z) (get-current-environment))
---
15

== make-environment

-- creates empty environment
(null? (make-environment))
---
t
