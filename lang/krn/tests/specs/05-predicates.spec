
== Kernel predicates

-- operative?
(operative? ($vau (x) e x))
---
t

-- operative? false on applicative
(null? (operative? ($lambda (x) x)))
---
t

-- applicative?
(applicative? ($lambda (x) x))
---
t

-- applicative? false on number
(null? (applicative? 42))
---
t

-- boolean? on #t
(boolean? #t)
---
t

-- boolean? on #f
(boolean? #f)
---
t

-- boolean? false
(null? (boolean? 42))
---
t

-- inert? on #inert
(inert? #inert)
---
t

== number predicates

-- zero?
(zero? 0)
---
t

-- zero? false
(null? (zero? 1))
---
t

-- positive?
(positive? 5)
---
t

-- negative?
(negative? (- 0 3))
---
t

-- even?
(even? 4)
---
t

-- even? false
(null? (even? 3))
---
t

-- odd?
(odd? 3)
---
t

-- odd? false
(null? (odd? 4))
---
t

== numeric operations

-- abs positive
(abs 5)
---
5

-- abs negative
(abs (- 0 5))
---
5

-- min
(min 3 7)
---
3

-- max
(max 3 7)
---
7
