
== string-length

-- returns length of string
(string-length "hello")
---
5

-- returns 0 for empty string
(string-length "")
---
0

== string-ref

-- returns character at index
(string-ref "hello" 0)
---
h

-- returns middle character
(string-ref "hello" 2)
---
l

== string-append

-- concatenates two strings
(string-append "hello" " world")
---
"hello world"

-- appends to empty string
(string-append "" "abc")
---
"abc"

== substring

-- extracts substring
(substring "hello world" 6 11)
---
"world"

-- extracts from start
(substring "hello" 0 3)
---
"hel"

-- single character
(substring "abc" 1 2)
---
"b"

== string=?

-- returns t for equal strings
(string=? "hello" "hello")
---
t

-- returns nil for different strings
(string=? "hello" "world")
---


== string->symbol

-- converts string to symbol
(string->symbol "hello")
---
hello

-- interned equality
(eq? (string->symbol "hello") (lit hello))
---
t

== symbol->string

-- converts symbol to string
(symbol->string (lit hello))
---
"hello"

-- round-trip string->symbol->string
(symbol->string (string->symbol "test"))
---
"test"

== number->string

-- converts positive number
(number->string 42)
---
"42"

-- converts zero
(number->string 0)
---
"0"

-- converts negative number
(number->string -7)
---
"-7"

== string->number

-- parses positive number
(string->number "42")
---
42

-- parses negative number
(string->number "-5")
---
-5

-- parses zero
(string->number "0")
---
0

== string escapes

-- escaped quote round-trips through write
(write "a\"b")
---
"a\"b"

-- escaped backslash round-trips through write
(write "a\\\\b")
---
"a\\\\b"

-- newline round-trips through write
(write "a\nb")
---
"a\nb"

-- tab round-trips through write
(write "a\tb")
---
"a\tb"

-- carriage return round-trips through write
(write "a\rb")
---
"a\rb"

-- hex escape produces correct byte
(= (char->integer (string-ref "\x41" 0)) 65)
---
t

-- display outputs raw characters
(display "a\tb")
---
a	b

== string composition

-- round-trips number->string->number
(string->number (number->string 99))
---
99

-- builds string from parts
(string-length (string-append "abc" "defgh"))
---
8
