
== char basics

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

== char comparison

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

== char classification

-- char-alphabetic? lowercase
(char-alphabetic? #\a)
---
t

-- char-alphabetic? uppercase
(char-alphabetic? #\Z)
---
t

-- char-alphabetic? digit
(null? (char-alphabetic? #\0))
---
t

-- char-alphabetic? space
(null? (char-alphabetic? #\space))
---
t

-- char-numeric? digit
(char-numeric? #\5)
---
t

-- char-numeric? letter
(null? (char-numeric? #\a))
---
t

-- char-whitespace? space
(char-whitespace? #\space)
---
t

-- char-whitespace? newline
(char-whitespace? #\newline)
---
t

-- char-whitespace? letter
(null? (char-whitespace? #\a))
---
t

-- char-upper-case? uppercase
(char-upper-case? #\A)
---
t

-- char-upper-case? lowercase
(null? (char-upper-case? #\a))
---
t

-- char-lower-case? lowercase
(char-lower-case? #\a)
---
t

-- char-lower-case? uppercase
(null? (char-lower-case? #\A))
---
t

== char case conversion

-- char-upcase lowercase
(char-upcase #\a)
---
A

-- char-upcase already upper
(char-upcase #\A)
---
A

-- char-upcase digit unchanged
(char-upcase #\5)
---
5

-- char-downcase uppercase
(char-downcase #\A)
---
a

-- char-downcase already lower
(char-downcase #\a)
---
a

-- char-foldcase uppercase
(char-foldcase #\A)
---
a

-- char-foldcase lowercase
(char-foldcase #\a)
---
a

== char case-insensitive comparison

-- char-ci=? same case
(char-ci=? #\a #\a)
---
t

-- char-ci=? different case
(char-ci=? #\a #\A)
---
t

-- char-ci=? not equal
(null? (char-ci=? #\a #\b))
---
t

-- char-ci<? less
(char-ci<? #\a #\B)
---
t

-- char-ci>? greater
(char-ci>? #\B #\a)
---
t
