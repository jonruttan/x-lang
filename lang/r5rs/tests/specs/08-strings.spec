
== string basics

-- string? on string
(string? "hello")
---
t

-- string? on non-string
(null? (string? 42))
---
t

-- string-length
(string-length "hello")
---
5

-- string-length empty
(string-length "")
---
0

-- string-ref first
(string-ref "hello" 0)
---
h

-- string-ref last
(string-ref "hello" 4)
---
o

== string operations

-- string-append two
(string-append "hello" " world")
---
"hello world"

-- string-append empty
(string-append "" "abc")
---
"abc"

-- substring
(substring "hello world" 6 11)
---
"world"

-- substring from start
(substring "hello" 0 3)
---
"hel"

-- substring empty
(substring "hello" 2 2)
---
""

-- string-copy
(string-copy "hello")
---
"hello"

-- string-copy is equal
(define s "hello") (equal? s (string-copy s))
---
t

== string comparison

-- string=? equal
(string=? "abc" "abc")
---
t

-- string=? not equal
(null? (string=? "abc" "abd"))
---
t

-- string<? less
(string<? "abc" "abd")
---
t

-- string<? not less
(null? (string<? "abd" "abc"))
---
t

-- string<? prefix is less
(string<? "abc" "abcd")
---
t

-- string>? greater
(string>? "abd" "abc")
---
t

-- string<=? equal
(string<=? "abc" "abc")
---
t

-- string<=? less
(string<=? "abc" "abd")
---
t

-- string>=? equal
(string>=? "abc" "abc")
---
t

-- string>=? greater
(string>=? "abd" "abc")
---
t

== string conversion

-- symbol->string
(symbol->string (quote hello))
---
"hello"

-- string->symbol
(eq? (string->symbol "hello") (quote hello))
---
t

-- number->string
(number->string 42)
---
"42"

-- string->number
(string->number "42")
---
42

-- string->list
(string->list "abc")
---
(a b c)

-- string->list empty
(null? (string->list ""))
---
t
