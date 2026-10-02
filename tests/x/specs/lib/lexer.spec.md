# @no-seam-collect
<!-- A child tokenizer base, like core/sandbox.spec.md: objects reachable only
     through it are invisible to the parent's mark, so this file runs with no
     seam collects. -->
# @weight 1

Lexer (`lib/x/reader/lexer.x`): a tokenizer base built from data rules.  Each
rule becomes one type on a `(Base make-tok)` child; every analyser state is a
form the assembler lane lowers when it is open, and the interpreted twin of
the same form otherwise.  These cases hold on both: the token stream is the
contract, the realization is not.

## words and blanks

### a run rule reads words and a skip rule drops the blanks between them

```x
(do
  (import x/reader/lexer)
  (def %lx-l (Lexer make (list
    (Lexer skip " \n")
    (Lexer run 'word (list (pair 97 122)) (list (pair 97 122))))))
  (write (%lx-l read-str "ab c\nd"))
  (newline))
```
---
    (('word "ab") ('word "c") ('word "d"))

### first and rest classes differ: an identifier may not start with a digit

```x
(do
  (import x/reader/lexer)
  (def %lx-l (Lexer make (list
    (Lexer skip " ")
    (Lexer run 'id (list (pair 97 122) 95) (list (pair 97 122) (pair 48 57) 95)))))
  (write (%lx-l read-str "a1 _x9 b"))
  (newline))
```
---
    (('id "a1") ('id "_x9") ('id "b"))

### a class takes strings and character literals as members

```x
(do
  (import x/reader/lexer)
  (def %lx-l (Lexer make (list
    (Lexer skip " ")
    (Lexer run 'w "xyz" (list #\x #\y #\z #\!)))))
  (write (%lx-l read-str "xy! zz"))
  (newline))
```
---
    (('w "xy!") ('w "zz"))

### a one-character token accepts through the same states

```x
(do
  (import x/reader/lexer)
  (def %lx-l (Lexer make (list
    (Lexer skip " ")
    (Lexer run 'w "abc" "abc"))))
  (write (%lx-l read-str "a b c"))
  (newline))
```
---
    (('w "a") ('w "b") ('w "c"))

## tables

### a table matches the longest literal present

```x
(do
  (import x/reader/lexer)
  (def %lx-l (Lexer make (list
    (Lexer skip " ")
    (Lexer table 'op ('list "<" "<<" "<<=" "<=" "=" "==")))))
  (write (%lx-l read-str "<<= < <= == = <<"))
  (newline))
```
---
    (('op "<<=") ('op "<") ('op "<=") ('op "==") ('op "=") ('op "<<"))

### a keyword table listed before the identifier run wins the tie, and a longer identifier wins over it

```x
(do
  (import x/reader/lexer)
  (def %lx-l (Lexer make (list
    (Lexer skip " ")
    (Lexer table 'kw ('list "if" "in" "int"))
    (Lexer run 'id "abcdefghijklmnopqrstuvwxyz" "abcdefghijklmnopqrstuvwxyz"))))
  (write (%lx-l read-str "if ifx in int i"))
  (newline))
```
---
    (('kw "if") ('id "ifx") ('kw "in") ('kw "int") ('id "i"))

### the identifier run listed first takes the keywords as identifiers

```x
(do
  (import x/reader/lexer)
  (def %lx-l (Lexer make (list
    (Lexer skip " ")
    (Lexer run 'id "abcdefghijklmnopqrstuvwxyz" "abcdefghijklmnopqrstuvwxyz")
    (Lexer table 'kw ('list "if" "in")))))
  (write (%lx-l read-str "if in"))
  (newline))
```
---
    (('id "if") ('id "in"))

## quoted literals

### a quoted rule reads the literal with its quotes, escapes left for the reader

```x
(do
  (import x/reader/lexer)
  (def %lx-l (Lexer make (list
    (Lexer skip " ")
    (Lexer quoted 'str 34 34 92))))
  (write (%lx-l read-str "\"a b\" \"c\\\"d\" \"\""))
  (newline))
```
---
    (('str "\"a b\"") ('str "\"c\\\"d\"") ('str "\"\""))

### a quoted rule with no escape byte ends at the first close

```x
(do
  (import x/reader/lexer)
  (def %lx-l (Lexer make (list
    (Lexer skip " ")
    (Lexer quoted 'sq 39 39 ()))))
  (write (%lx-l read-str "'a\\' 'b'"))
  (newline))
```
---
    (('sq "'a\\'") ('sq "'b'"))

### a literal left open is not a token

```x
(do
  (import x/reader/lexer)
  (def %lx-l (Lexer make (list
    (Lexer skip " ")
    (Lexer run 'w "abc" "abc")
    (Lexer quoted 'str 34 34 92))))
  (write (%lx-l read-str "a \"bc"))
  (newline))
```
---
    (('w "a"))

## spans

### an until rule with no tag drops a block comment, a two-byte close taken

```x
(do
  (import x/reader/lexer)
  (def %lx-l (Lexer make (list
    (Lexer skip " ")
    (Lexer until () "/*" "*/")
    (Lexer run 'w "abc" "abc"))))
  (write (%lx-l read-str "a /* b ** c */ b"))
  (newline))
```
---
    (('w "a") ('w "b"))

### a tagged until rule keeps a line comment, the newline left for the next token

```x
(do
  (import x/reader/lexer)
  (def %lx-l (Lexer make (list
    (Lexer skip " ")
    (Lexer table 'nl ('list "\n"))
    (Lexer until 'comment "//" "\n")
    (Lexer run 'w "abc" "abc"))))
  (write (%lx-l read-str "a // b c\nb"))
  (newline))
```
---
    (('w "a") ('comment "// b c") ('nl "\n") ('w "b"))

## numbers

### a number rule labels integers 1, fractions and exponents 2, hex 3

```x
(do
  (import x/reader/lexer)
  (def %lx-l (Lexer make (list
    (Lexer skip " ")
    (Lexer number 'num ()))))
  (write (%lx-l read-str "0 42 3.5 .5 1e9 2.5E-3 0x1F 007"))
  (newline))
```
---
    (('num "0" 1) ('num "42" 1) ('num "3.5" 2) ('num ".5" 2) ('num "1e9" 2) ('num "2.5E-3" 2) ('num "0x1F" 3) ('num "007" 1))

### suffix bytes are taken into the token and the label stands

```x
(do
  (import x/reader/lexer)
  (def %lx-l (Lexer make (list
    (Lexer skip " ")
    (Lexer number 'num "uUlLfF"))))
  (write (%lx-l read-str "10u 10UL 1.5f 0xffUL"))
  (newline))
```
---
    (('num "10u" 1) ('num "10UL" 1) ('num "1.5f" 2) ('num "0xffUL" 3))

### a dot with no digits after it still ends a fraction, as C and Python read it

A number is read forward only: an exponent marker with no digits after it
refuses the literal, as x-python's does, since the characters cannot be
given back.

```x
(do
  (import x/reader/lexer)
  (def %lx-l (Lexer make (list
    (Lexer skip " ")
    (Lexer number 'num ()))))
  (write (%lx-l read-str "1. 2e5 3"))
  (newline))
```
---
    (('num "1." 2) ('num "2e5" 2) ('num "3" 1))
## a small C-shaped lexer

### the rules compose: comments, keywords, identifiers, numbers, strings, operators

```x
(do
  (import x/reader/lexer)
  (def %lx-l (Lexer make (list
    (Lexer skip " \t\n")
    (Lexer until () "/*" "*/")
    (Lexer until () "//" "\n")
    (Lexer table 'kw ('list "int" "return" "if"))
    (Lexer run 'id (list (pair 97 122) (pair 65 90) 95) (list (pair 97 122) (pair 65 90) (pair 48 57) 95))
    (Lexer number 'num "uUlL")
    (Lexer quoted 'str 34 34 92)
    (Lexer table 'op ('list "(" ")" "{" "}" ";" "=" "==" "+" "+=" "<<" "<<=" ",")))))
  (write (%lx-l read-str "int f(int x) { /* two */ x += 2; return x == 0x10; } // done\n"))
  (newline))
```
---
    (('kw "int") ('id "f") ('op "(") ('kw "int") ('id "x") ('op ")") ('op "{") ('id "x") ('op "+=") ('num "2" 1) ('op ";") ('kw "return") ('id "x") ('op "==") ('num "0x10" 3) ('op ";") ('op "}"))

## the realization

### a lexer reports how many states the lane compiled, and the stream is the same either way

Zero when the lane is closed, every state but the rare interpreted ones when
it is open; the count is reported, the tokens are the contract.

```x
(do
  (import x/reader/lexer)
  (def %lx-l (Lexer make (list
    (Lexer skip " ")
    (Lexer run 'w "abc" "abc"))))
  (write (list (>= (%lx-l compiled) 0) (%lx-l read-str "a bc")))
  (newline))
```
---
    (#t (('w "a") ('w "bc")))

### remake! builds the base again from the rules, as the recache hook does after an image load

```x
(do
  (import x/reader/lexer)
  (def %lx-l (Lexer make (list
    (Lexer skip " ")
    (Lexer run 'w "abc" "abc"))))
  (%lx-l raw ())
  (write (%lx-l read-str "a bc"))
  (newline))
```
---
    (('w "a") ('w "bc"))

### an unknown rule kind is refused

```x
(do
  (import x/reader/lexer)
  (write (guard (e (lit refused)) (Lexer make (list (list (lit bogus) "B" (lit b))))))
  (newline))
```
---
    'refused
