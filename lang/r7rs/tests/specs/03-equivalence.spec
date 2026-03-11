
== eqv?

-- eqv? same boolean true
(eqv? #t #t)
---
t

-- eqv? same boolean false
(eqv? #f #f)
---
t

-- eqv? same symbol
(eqv? (quote a) (quote a))
---
t

-- eqv? different symbols
(null? (eqv? (quote a) (quote b)))
---
t

-- eqv? same number
(eqv? 42 42)
---
t

-- eqv? different numbers
(null? (eqv? 1 2))
---
t

-- eqv? same char
(eqv? #\a #\a)
---
t

-- eqv? different chars
(null? (eqv? #\a #\b))
---
t

-- eqv? empty lists
(eqv? () ())
---
t

-- eqv? string to symbol
(null? (eqv? "a" (quote a)))
---
t

-- eqv? number to char
(null? (eqv? 65 #\A))
---
t

== eq?

-- eq? same symbol
(eq? (quote a) (quote a))
---
t

-- eq? different symbols
(null? (eq? (quote a) (quote b)))
---
t

-- eq? empty lists
(eq? () ())
---
t

-- eq? booleans
(eq? #t #t)
---
t

== equal?

-- equal? same lists
(equal? (list 1 2 3) (list 1 2 3))
---
t

-- equal? different lists
(null? (equal? (list 1 2) (list 1 3)))
---
t

-- equal? nested lists
(equal? (list 1 (list 2 3)) (list 1 (list 2 3)))
---
t

-- equal? strings
(equal? "abc" "abc")
---
t

-- equal? different strings
(null? (equal? "abc" "abd"))
---
t

-- equal? numbers
(equal? 42 42)
---
t

-- equal? mixed types
(null? (equal? 1 "1"))
---
t

-- equal? dotted pairs
(equal? (cons 1 2) (cons 1 2))
---
t

-- equal? deep nested
(equal? (list (list 1 (list 2)) (list 3)) (list (list 1 (list 2)) (list 3)))
---
t

-- equal? chars
(equal? #\a #\a)
---
t
