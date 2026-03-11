
== make-type

-- creates a custom type with call handler
(do (def %counter (make-type "COUNTER" (list (pair (lit call) (fn (self . args) (+ (first self) (first args))))))) (def c (make-instance %counter 10)) (c 5))
---
15

-- creates a custom type with write handler
(do (def %tag (make-type "TAG" (list (pair (lit write) (fn (self) (display "<") (display (first self)) (display ">")))))) (write (make-instance %tag "hello")))
---
<hello>

== make-instance

-- stores data accessible via first
(do (def my-t (make-type "MY-T" (list))) (def obj (make-instance my-t 42)) (first obj))
---
42

-- instance self-evaluates
(do (def my-t (make-type "MY-T" (list))) (def obj (make-instance my-t 42)) (eq? obj obj))
---
t

== type?

-- returns t for matching type
(do (def my-t (make-type "MY-T" (list))) (type? (make-instance my-t 42) my-t))
---
t

-- returns nil for wrong type
(do (def t1 (make-type "T1" (list))) (def t2 (make-type "T2" (list))) (if (type? (make-instance t1 1) t2) "y" "n"))
---
"n"

-- returns nil for non-instance
(do (def my-t (make-type "MY-T" (list))) (if (type? 42 my-t) "y" "n"))
---
"n"

== type-name

-- returns VECTOR for a vector
(type-name (vector 1))
---
"VECTOR"

-- returns LIST for a list
(type-name (list 1 2))
---
"LIST"

-- returns INTEGER for a number
(type-name 42)
---
"INTEGER"

-- returns STRING for a string
(type-name "hi")
---
"STRING"

-- returns custom type name
(do (def my-t (make-type "MY-T" (list))) (type-name (make-instance my-t 1)))
---
"MY-T"

== score-match

-- sets score length and reader
