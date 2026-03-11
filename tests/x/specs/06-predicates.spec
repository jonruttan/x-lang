
== eq?

-- returns t for equal symbols
(eq? (lit a) (lit a))
---
t

-- returns t for eq? on same binding
(do (def x 5) (eq? x x))
---
t

== =

-- returns t for equal integers
(= 3 3)
---
t

-- returns nil for unequal integers
(= 3 4)
---


== <

-- returns t for less than
(< 1 2)
---
t

-- returns nil for equal
(< 2 2)
---


-- returns nil for greater than
(< 3 2)
---


-- handles negative numbers
(< -5 0)
---
t

== >

-- returns t for greater than
(> 3 2)
---
t

-- returns nil for equal
(> 2 2)
---


-- returns nil for less than
(> 1 2)
---


-- handles negative numbers
(> 0 -5)
---
t

== <=

-- returns t for less than
(<= 1 2)
---
t

-- returns t for equal
(<= 2 2)
---
t

-- returns nil for greater than
(<= 3 2)
---


== >=

-- returns t for greater than
(>= 3 2)
---
t

-- returns t for equal
(>= 2 2)
---
t

-- returns nil for less than
(>= 1 2)
---


== null?

-- returns t for nil
(null? (lit ()))
---
t

-- returns nil for non-nil
(null? 1)
---


== pair?

-- returns t for a list
(pair? (list 1 2))
---
t

-- returns t for a pair
(pair? (pair 1 2))
---
t

-- returns nil for an atom
(pair? 42)
---


== atom?

-- returns t for an integer
(atom? 42)
---
t

-- returns t for a symbol
(atom? (lit a))
---
t

-- returns nil for a list
(atom? (list 1 2))
---


== number?

-- true for integer
(number? 42)
---
t

-- false for string
(null? (number? "hello"))
---
t

== string?

-- true for string
(string? "hello")
---
t

-- false for integer
(null? (string? 42))
---
t

== symbol?

-- true for symbol
(symbol? (lit hello))
---
t

-- false for integer
(null? (symbol? 42))
---
t

== procedure?

-- true for fn
(procedure? (fn (x) x))
---
t

-- true for builtin
(procedure? first)
---
t

-- false for integer
(null? (procedure? 42))
---
t

== char?

-- returns nil for number
(null? (char? 42))
---
t

-- returns nil for string
(null? (char? "hello"))
---
t

-- returns nil for symbol
(null? (char? (lit a)))
---
t

== char->integer

-- converts lowercase letter
(char->integer #\a)
---
97

-- converts uppercase letter
(char->integer #\A)
---
65

-- converts digit character
(char->integer #\0)
---
48

== integer->char

-- converts code point to character
(integer->char 65)
---
A

-- round-trips with char->integer
(= (char->integer (integer->char 97)) 97)
---
t
