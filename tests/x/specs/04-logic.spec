
== and

-- returns t for empty and
(and)
---
t

-- returns value for single truthy
(and 1)
---
1

-- returns nil for single falsy
(and (lit ()))
---


-- returns last value when all truthy
(and 1 2 3)
---
3

-- returns nil on first falsy
(and 1 (lit ()) 3)
---


-- returns actual value not t
(and 1 "yes")
---
"yes"

-- short-circuits evaluation
(do (def x 0) (and (lit ()) (set x 1)) x)
---
0

-- short-circuits before error
(and (lit ()) (error "boom"))
---


-- def in last position persists
(do (and t (def x 99)) x)
---
99

== or

-- returns nil for empty or
(or)
---


-- returns value for single truthy
(or 1)
---
1

-- returns nil for single falsy
(or (lit ()))
---


-- returns first truthy value
(or (lit ()) 2 3)
---
2

-- returns nil when all falsy
(or (lit ()) (lit ()))
---


-- returns actual value not t
(or (lit ()) "yes")
---
"yes"

-- short-circuits evaluation
(do (def x 0) (or 1 (set x 1)) x)
---
0

-- short-circuits before error
(or 1 (error "boom"))
---
1

-- def in last position persists
(do (or (lit ()) (def x 77)) x)
---
77

== not

-- returns t for nil
(not (lit ()))
---
t

-- returns nil for non-nil
(not 1)
---


== nested and/or

-- nested and/or returns correct value
(and (or (lit ()) 1) (or (lit ()) 2))
---
2

-- or of ands returns correct value
(or (and (lit ()) 1) (and 1 2))
---
2

-- and of ors returns correct value
(and (or 1 2) (or 3 4))
---
3

-- deeply nested logic
(or (and (or (lit ()) (lit ())) 1) (and (or (lit ()) 5) 6))
---
6

== guard

-- returns body result when no error
(guard (e (lit caught)) (+ 1 2))
---
3

-- catches explicit error
(guard (e e) (error "boom"))
---
"boom"

-- runs handler body on error
(guard (e (list (lit caught) e)) (error "oops"))
---
(caught "oops")

-- catches unbound symbol
(guard (e (lit handled)) no-such-var)
---
handled

-- returns last body form
(guard (e e) 1 2 3)
---
3

-- handler sees error value
(guard (e (list (lit err) e)) (error 42))
---
(err 42)

== error

-- signals with string
(guard (e e) (error "test"))
---
"test"

-- signals with number
(guard (e e) (error 99))
---
99

-- signals from nested call
(do (def boom (fn () (error "inner"))) (guard (e e) (boom)))
---
"inner"

== nested guard

-- inner guard catches inner error
(guard (e (lit outer)) (guard (e (lit inner)) (error "x")))
---
inner

-- outer guard catches when inner has no guard
(guard (e (list (lit outer) e)) (do (def f (fn () (error "deep"))) (f)))
---
(outer "deep")

-- inner guard does not catch outer body error
(guard (e (list (lit caught) e)) (+ 1 2) (error "after"))
---
(caught "after")

== guard with env restore

-- restores env after error in let
(do (def x 10) (guard (e x) (let ((x 20)) (error "err"))))
---
10

-- restores env after error in fn
(do (def x 5) (guard (e x) ((fn () (error "err")))))
---
5
