
== error

-- error raises exception
(guard (e #t) (error "boom"))
---
t

-- error with string message
(guard (e e) (error "boom"))
---
"boom"

-- error with number
(guard (e e) (error 42))
---
42

-- error with symbol
(guard (e e) (error (quote oops)))
---
oops

== guard

-- guard catches error
(guard (e (list (quote caught) e)) (error "fail"))
---
(caught "fail")

-- guard returns body when no error
(guard (e (quote caught)) (+ 1 2))
---
3

-- guard with multiple body forms
(guard (e (quote caught)) 1 2 (+ 3 4))
---
7

-- guard handler uses error value
(guard (e (+ e 1)) (error 41))
---
42

-- guard handler builds list
(guard (e (list (quote err) e)) (error (list 1 2 3)))
---
(err (1 2 3))

== guard with computation

-- guard in let
(let ((x 10)) (guard (e (+ x 1)) (error "fail")))
---
11

-- guard in define
(define (safe-op) (guard (e 0) (error "fail"))) (safe-op)
---
0

-- guard passes through normal value
(guard (e (quote bad)) (list 1 2 3))
---
(1 2 3)

-- guard passes through arithmetic
(guard (e (quote bad)) (* 6 7))
---
42
