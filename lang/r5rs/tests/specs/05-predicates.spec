
== type predicates

-- number?
(number? 42)
---
t

-- number? false
(null? (number? "hello"))
---
t

-- string?
(string? "hello")
---
t

-- string? false
(null? (string? 42))
---
t

-- symbol?
(symbol? (quote hello))
---
t

-- symbol? false
(null? (symbol? 42))
---
t

-- procedure? on lambda
(procedure? (lambda (x) x))
---
t

-- procedure? on builtin
(procedure? car)
---
t

-- procedure? false
(null? (procedure? 42))
---
t

-- pair?
(pair? (list 1 2))
---
t

-- null? on empty
(null? ())
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

-- char? on char
(char? #\a)
---
t

-- char? false
(null? (char? 42))
---
t

== equality

-- eq? same symbol
(eq? (quote a) (quote a))
---
t

-- eq? different symbols
(null? (eq? (quote a) (quote b)))
---
t

-- equal? on lists
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

-- eqv? on numbers
(eqv? 42 42)
---
t

-- eqv? different numbers
(null? (eqv? 1 2))
---
t

== list?

-- list? on proper list
(list? (list 1 2))
---
t

-- list? on empty
(list? ())
---
t

-- list? on dotted pair
(null? (list? (cons 1 2)))
---
t

-- list? on atom
(null? (list? 42))
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

-- zero? negative
(null? (zero? (- 0 1)))
---
t

-- positive?
(positive? 5)
---
t

-- positive? false
(null? (positive? 0))
---
t

-- negative?
(negative? (- 0 3))
---
t

-- negative? false
(null? (negative? 0))
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

-- even? zero
(even? 0)
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

-- abs zero
(abs 0)
---
0

-- min
(min 3 7)
---
3

-- max
(max 3 7)
---
7

-- modulo
(modulo 10 3)
---
1
