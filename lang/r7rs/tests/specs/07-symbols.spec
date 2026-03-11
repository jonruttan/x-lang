
== symbol?

-- symbol? on symbol
(symbol? (quote foo))
---
t

-- symbol? on string
(null? (symbol? "foo"))
---
t

-- symbol? on number
(null? (symbol? 42))
---
t

-- symbol? on list
(null? (symbol? (list 1 2)))
---
t

-- symbol? on boolean
(symbol? #t)
---
t

== symbol=?

-- symbol=? same symbols
(symbol=? (quote a) (quote a))
---
t

-- symbol=? different symbols
(null? (symbol=? (quote a) (quote b)))
---
t

== symbol conversion

-- symbol->string
(symbol->string (quote hello))
---
"hello"

-- string->symbol
(eq? (string->symbol "hello") (quote hello))
---
t

-- roundtrip symbol->string->symbol
(eq? (string->symbol (symbol->string (quote foo))) (quote foo))
---
t
