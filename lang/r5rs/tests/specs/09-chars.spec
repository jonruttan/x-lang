
== character basics

-- char? on char
(char? #\a)
---
t

-- char? on string
(null? (char? "a"))
---
t

-- char? on number
(null? (char? 65))
---
t

-- char->integer uppercase
(char->integer #\A)
---
65

-- char->integer lowercase
(char->integer #\a)
---
97

-- char->integer digit
(char->integer #\0)
---
48

-- integer->char
(integer->char 65)
---
A

-- roundtrip char->int->char
(integer->char (char->integer #\z))
---
z

-- char->integer space
(char->integer #\space)
---
32

-- char->integer newline
(char->integer #\newline)
---
10

== character comparison

-- char=? equal
(char=? #\a #\a)
---
t

-- char=? not equal
(null? (char=? #\a #\b))
---
t

-- char<? less
(char<? #\a #\b)
---
t

-- char<? not less
(null? (char<? #\b #\a))
---
t

-- char>? greater
(char>? #\b #\a)
---
t

-- char<=? equal
(char<=? #\a #\a)
---
t

-- char<=? less
(char<=? #\a #\b)
---
t

-- char>=? equal
(char>=? #\a #\a)
---
t

-- char>=? greater
(char>=? #\b #\a)
---
t

-- char>=? not greater
(null? (char>=? #\a #\b))
---
t
