
== boolean?

-- boolean? on true
(boolean? #t)
---
t

-- boolean? on false
(boolean? #f)
---
t

-- boolean? on number
(null? (boolean? 0))
---
t

-- boolean? on string
(null? (boolean? ""))
---
t

-- boolean? on nil
(boolean? ())
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

-- not 3
(null? (not 3))
---
t

-- not nil
(not ())
---
t

== boolean=?

-- boolean=? both true
(boolean=? #t #t)
---
t

-- boolean=? both false
(boolean=? #f #f)
---
t

-- boolean=? true false
(null? (boolean=? #t #f))
---
t

-- boolean=? false true
(null? (boolean=? #f #t))
---
t
