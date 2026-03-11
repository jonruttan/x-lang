
== if

-- true branch
(if #t 1 2)
---
1

-- false branch
(if #f 1 2)
---
2

-- no else returns nil
(null? (if #f 1))
---
t

-- non-boolean truthy
(if 42 1 2)
---
1

-- nested if
(if (> 3 2) (if (< 1 0) (quote a) (quote b)) (quote c))
---
b

-- if with expression in test
(if (= (+ 1 1) 2) (quote yes) (quote no))
---
yes

== when

-- evaluates body when true
(when (= 1 1) (+ 10 20))
---
30

-- returns nil when false
(null? (when (= 1 2) 42))
---
t

-- supports multiple body forms
(when #t 1 2 3)
---
3

== unless

-- evaluates body when false
(unless (= 1 2) 99)
---
99

-- returns nil when true
(null? (unless (= 1 1) 42))
---
t

== cond

-- evaluates matching clause
(cond ((= 1 2) 10) ((= 1 1) 20) (#t 30))
---
20

-- falls through to else
(cond ((= 1 2) 10) (#t 99))
---
99

-- returns nil when no match
(null? (cond (#f 1)))
---
t

== and

-- all true returns last
(and 1 2 3)
---
3

-- short-circuits on false
(null? (and 1 #f 3))
---
t

-- no args returns true
(and)
---
t

-- single true arg
(and 42)
---
42

== or

-- returns first true
(or 1 2 3)
---
1

-- skips false values
(or #f #f 3)
---
3

-- no args returns false
(null? (or))
---
t

-- single false arg
(null? (or #f))
---
t

== not

-- not true
(null? (not #t))
---
t

-- not false
(not #f)
---
t

-- not on non-boolean
(null? (not 42))
---
t
