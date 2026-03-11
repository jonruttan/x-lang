
== boolean?

-- true for t
(boolean? t)
---
t

-- true for nil
(boolean? ())
---
t

-- false for number
(if (boolean? 42) "y" "n")
---
"n"

== default-to

-- returns value when non-nil
(default-to 0 42)
---
42

-- returns default when nil
(default-to 0 ())
---
0

== until

-- iterates until predicate holds
(until (fn (x) (> x 10)) inc 1)
---
11

== equal?

-- compares numbers
(equal? 5 5)
---
t

-- compares different numbers
(if (equal? 5 6) "y" "n")
---
"n"

-- compares strings
(equal? "hi" "hi")
---
t

-- compares nil
(equal? () ())
---
t
