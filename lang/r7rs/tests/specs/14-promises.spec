
== promise basics

-- delay creates promise
(promise? (delay 42))
---
t

-- promise? on non-promise
(null? (promise? 42))
---
t

-- promise? on list
(null? (promise? (list 1 2)))
---
t

== force

-- force simple value
(force (delay 42))
---
42

-- force expression
(force (delay (+ 1 2)))
---
3

-- force non-promise
(force 42)
---
42

-- force twice same result
(define p (delay (* 6 7))) (list (force p) (force p))
---
(42 42)

== promise memoization

-- delay memoizes result
(define count 0) (define p (delay (begin (set! count (+ count 1)) count))) (force p) (force p) count
---
1

-- side effect runs once
(define n 0) (define p (delay (begin (set! n (+ n 10)) n))) (force p) (force p) (force p) n
---
10

== make-promise

-- make-promise wraps value
(force (make-promise 42))
---
42

-- make-promise is idempotent on promise
(define p (delay 99)) (eq? (make-promise p) p)
---
t

-- make-promise result forceable
(force (make-promise (+ 10 20)))
---
30
