# @lib x.x

== integer reader

-- reads positive integers
99
---
99

-- reads negative integers
-99
---
-99

-- reads zero
0
---
0

== string reader

-- reads simple string
"hello"
---
"hello"

-- reads empty string
""
---
""

-- reads string with escaped quote
"a\"b"
---
"a\"b"

-- reads string with escaped backslash
"a\\\\b"
---
"a\\\\b"

-- reads string with newline escape
(string-length "a\nb")
---
3

-- reads string with tab escape
(string-length "a\tb")
---
3

-- reads string with carriage return escape
(string-length "a\rb")
---
3

-- reads string with hex escape
(= (char->integer (string-ref "\x41" 0)) 65)
---
t

-- preserves unknown escape sequences
(string-length "\q")
---
2

== symbol reader

-- reads simple symbol
(lit abc)
---
abc

-- reads symbol with punctuation
(lit my-var?)
---
my-var?

-- reads operator symbols
(lit +)
---
+

== character reader

-- reads character literal
(char? #\x)
---
t

-- reads specific character
(char->integer #\a)
---
97

-- reads uppercase character
(char->integer #\Z)
---
90

-- reads named character space
(char->integer #\space)
---
32

-- reads named character newline
(char->integer #\newline)
---
10

-- reads named character tab
(char->integer #\tab)
---
9

== list reader

-- reads proper list
(lit (1 2 3))
---
(1 2 3)

-- reads nested list
(lit (1 (2 3)))
---
(1 (2 3))

-- reads empty list
()
---


== dotted pair reader

-- reads dotted pair first
(first (lit (1 . 2)))
---
1

-- reads dotted pair rest
(rest (lit (1 . 2)))
---
2

-- reads list with dotted tail
(rest (lit (1 2 . 3)))
---
(2 . 3)

== quote shorthand

-- single-quote expands to lit
(lit a)
---
a

== comment handling

-- ignores line comments

== vector literal reader

-- reads vector literal
(write #(1 2 3))
---
#(1 2 3)

-- reads empty vector literal
(write #())
---
#()

== regex literal reader

-- reads regex literal
(write #/abc/)
---
#/abc/
