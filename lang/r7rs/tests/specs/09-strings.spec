
== string basics

-- string? on string
(string? "hello")
---
t

-- string? on non-string
(null? (string? 42))
---
t

-- string? on symbol
(null? (string? (quote hello)))
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

-- string-ref middle
(string-ref "abcde" 2)
---
c

== string operations

-- string-append two
(string-append "hello" " world")
---
"hello world"

-- string-append empty
(string-append "" "abc")
---
"abc"

-- string-append both empty
(string-append "" "")
---
""

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

-- substring full
(substring "hello" 0 5)
---
"hello"

-- string-copy
(string-copy "hello")
---
"hello"

-- string-copy is equal
(equal? (string-copy "test") "test")
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

== string case-insensitive comparison

-- string-ci=? equal same case
(string-ci=? "abc" "abc")
---
t

-- string-ci=? equal different case
(string-ci=? "Hello" "hello")
---
t

-- string-ci=? not equal
(null? (string-ci=? "abc" "abd"))
---
t

-- string-ci<? less
(string-ci<? "abc" "ABD")
---
t

-- string-ci>? greater
(string-ci>? "ABD" "abc")
---
t

-- string-ci<=? equal different case
(string-ci<=? "ABC" "abc")
---
t

-- string-ci>=? equal different case
(string-ci>=? "abc" "ABC")
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

-- string->number valid
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

-- string->list single
(string->list "x")
---
(x)

== list->string

-- list->string basic
(list->string (list #\a #\b #\c))
---
"abc"

-- list->string empty
(list->string ())
---
""

-- list->string single
(list->string (list #\z))
---
"z"

-- list->string roundtrip
(list->string (string->list "hello"))
---
"hello"

== make-string

-- make-string with fill
(make-string 3 #\a)
---
"aaa"

-- make-string length
(string-length (make-string 5 #\x))
---
5

-- make-string zero
(make-string 0 #\a)
---
""

== string constructor

-- string from chars
(string #\a #\b #\c)
---
"abc"

-- string single char
(string #\z)
---
"z"

-- string empty
(string)
---
""

== string case conversion

-- string-upcase
(string-upcase "hello")
---
"HELLO"

-- string-upcase mixed
(string-upcase "Hello World")
---
"HELLO WORLD"

-- string-upcase already upper
(string-upcase "ABC")
---
"ABC"

-- string-downcase
(string-downcase "HELLO")
---
"hello"

-- string-downcase mixed
(string-downcase "Hello World")
---
"hello world"

-- string-foldcase
(string-foldcase "Hello")
---
"hello"

-- string-foldcase upper
(string-foldcase "ABC")
---
"abc"

== string-map

-- string-map upcase
(string-map char-upcase "hello")
---
"HELLO"

-- string-map identity
(string-map (lambda (c) c) "abc")
---
"abc"

-- string-map empty
(string-map char-upcase "")
---
""

== string-for-each

-- string-for-each accumulates
(define acc 0) (string-for-each (lambda (c) (set! acc (+ acc 1))) "hello") acc
---
5
