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

## what a read handler makes stays out of the child

A read handler runs inside the tokenizer base, and an object made there
registers its built-in type on that base, with the type's s-expression
analyser.  The Lexer makes every token in the base that made it, so a
number's integer label does not teach the child to read `+1` as an integer.

### a number label does not make the child read a signed integer

```x
(do
  (import x/reader/lexer)
  (def %lx-l (Lexer make (list
    (Lexer skip " ")
    (Lexer number 'num ())
    (Lexer table 'op (list "+" "-")))))
  (write (%lx-l read-str "2+1 2-1 2 +1"))
  (newline))
```
---
    (('num "2" 1) ('op "+") ('num "1" 1) ('num "2" 1) ('op "-") ('num "1" 1) ('num "2" 1) ('op "+") ('num "1" 1))

## a dropped span outranks the operator that opens it

### a block comment is dropped although `/` and `*` are operators

```x
(do
  (import x/reader/lexer)
  (def %lx-l (Lexer make (list
    (Lexer skip " ")
    (Lexer until () "/*" "*/")
    (Lexer until () "//" "\n")
    (Lexer run 'id "abx" "abx")
    (Lexer table 'op (list "/" "*" "/=")))))
  (write (%lx-l read-str "a /* x */ b / x // c\n"))
  (newline))
```
---
    (('id "a") ('id "b") ('op "/") ('id "x"))

## a table of any size

### C's punctuators in one table

```x
(do
  (import x/reader/lexer)
  (def %lx-l (Lexer make (list
    (Lexer skip " ")
    (Lexer table 'op (list "[" "]" "(" ")" "{" "}" "." "->" "++" "--" "&" "*" "+" "-" "~" "!" "/" "%" "<<" ">>" "<" ">" "<=" ">=" "==" "!=" "^" "|" "&&" "||" "?" ":" ";" "..." "=" "*=" "/=" "%=" "+=" "-=" "<<=" ">>=" "&=" "^=" "|=" "," "#" "##" "@" "$" "`")))))
  (write (%lx-l read-str "-> ... <<= ## || [ ]"))
  (newline))
```
---
    (('op "->") ('op "...") ('op "<<=") ('op "##") ('op "||") ('op "[") ('op "]"))

## a byte no rule reads

### without a fallback the read stops at the first stray byte, silently

```x
(do
  (import x/reader/lexer)
  (def %lx-l (Lexer make (list
    (Lexer skip " ")
    (Lexer run 'w "abc" "abc"))))
  (write (%lx-l read-str "a @ b"))
  (newline))
```
---
    (('w "a"))

### an any rule listed last takes the stray byte as a token of its own

```x
(do
  (import x/reader/lexer)
  (def %lx-l (Lexer make (list
    (Lexer skip " ")
    (Lexer run 'w "abc" "abc")
    (Lexer table 'op (list "@@"))
    (Lexer any 'bad))))
  (write (%lx-l read-str "a @ b @@ c"))
  (newline))
```
---
    (('w "a") ('bad "@") ('w "b") ('op "@@") ('w "c"))

### an any rule leaves the end text alone

The end text is appended so the last token meets a delimiter; at the
buffer's end only a state that accepts on its own byte can win, so the any
rule refuses the end text's bytes as it refuses a skip rule's.

```x
(do
  (import x/reader/lexer)
  (def %lx-l (Lexer make (list
    (Lexer run 'sp " \t" " \t")
    (Lexer table 'nl (list "\n"))
    (Lexer run 'id "abc" "abc")
    (Lexer any 'bad)) "\n"))
  (write (%lx-l read-str "a\nb @"))
  (newline))
```
---
    (('id "a") ('nl "\n") ('id "b") ('sp " ") ('bad "@"))

### a dropped span registers nothing in the child either

A positive match is read by the engine, and with no handler its default
read would make an object in the child and register that object's type
there.  The dropped span's handler answers a marker instead, so a second
read after a comment still reads `-1` as an operator and a number.

```x
(do
  (import x/reader/lexer)
  (def %lx-l (Lexer make (list
    (Lexer skip " ")
    (Lexer until () "/*" "*/")
    (Lexer run 'id "abx" "abx")
    (Lexer number 'num ())
    (Lexer table 'op (list "(" ")" "*" "/" "-")))))
  (write (list (%lx-l read-str "a /* x */ b") (%lx-l read-str "(-1)")))
  (newline))
```
---
    ((('id "a") ('id "b")) (('op "(") ('op "-") ('num "1" 1) ('op ")")))

### the states' handoff cells survive a collect

A quoted literal's escape and a two-byte closer hand to the body through a
cell the compiled code reaches by address; the lexer holds the cell, so a
collect between reads does not free it under the states.

```x
(do
  (import x/reader/lexer)
  (def %lx-l (Lexer make (list
    (Lexer skip " ")
    (Lexer until () "/*" "*/")
    (Lexer quoted 'str 34 34 92)
    (Lexer run 'id "ab" "ab"))))
  (def %lx-before (%lx-l read-str "a \"x\\ny\" /* c */ b"))
  (Heap collect)
  (write (list %lx-before (%lx-l read-str "a \"x\\ny\" /* c */ b")))
  (newline))
```
---
    ((('id "a") ('str "\"x\\ny\"") ('id "b")) (('id "a") ('str "\"x\\ny\"") ('id "b")))

## nested spans

A nested rule reads a span whose body holds spans of its own, each context
closing back to the one it was entered from; an escape rule reads a byte and
the one after it.  The contexts below are a POSIX shell's: a double-quoted
string, a command substitution, a parameter expansion, backquotes and single
quotes.

### quotes inside a command substitution inside a string do not end either

```x
(do
  (import x/reader/lexer)
  (def %lxn-ctx
    (list (list 'dq 34 92 (list (pair "$(" 'cmd) (pair "${" 'brace) (pair "`" 'bq)))
          (list 'cmd 41 92 (list (pair "(" 'cmd) (pair "\"" 'dq) (pair "'" 'sq) (pair "${" 'brace)))
          (list 'brace 125 92 (list (pair "\"" 'dq) (pair "${" 'brace)))
          (list 'bq 96 92 (list (pair "'" 'sq) (pair "\"" 'dq)))
          (list 'sq 39 () ())))
  (def %lxn-l (Lexer make (list
    (Lexer skip " ")
    (Lexer escape 'esc 92)
    (Lexer nested 'dq "\"" 'dq %lxn-ctx)
    (Lexer nested 'cmd "$(" 'cmd %lxn-ctx)
    (Lexer run 'word "abcdefghijklmnopqrstuvwxyz$=" "abcdefghijklmnopqrstuvwxyz$=")
    (Lexer any 'bad))))
  (write (list (%lxn-l read-str "\"a $(echo \"b)\" ) c\" x")
               (%lxn-l read-str "$(a (b) 'c)' \"$(d)\") e")
               (%lxn-l read-str "\\) \"x\\\"y\" \"${v:-\"q\"}\" \"`e '`'`\"")))
  (newline))
```
---
    ((('dq "\"a $(echo \"b)\" ) c\"") ('word "x")) (('cmd "$(a (b) 'c)' \"$(d)\")") ('word "e")) (('esc "\\)") ('dq "\"x\\\"y\"") ('dq "\"${v:-\"q\"}\"") ('dq "\"`e '`'`\"")))

### a span left open is not a token, and the next read starts at depth 0

```x
(do
  (import x/reader/lexer)
  (def %lxn-ctx
    (list (list 'cmd 41 () (list (pair "(" 'cmd)))))
  (def %lxn-l (Lexer make (list
    (Lexer skip " ")
    (Lexer nested 'cmd "$(" 'cmd %lxn-ctx)
    (Lexer run 'word "abc$" "abc$")
    (Lexer any 'bad))))
  (write (list (%lxn-l read-str "$(a (b")
               (%lxn-l read-str "$(a) $(b)")))
  (newline))
```
---
    ((('word "$") ('bad "(") ('word "a") ('bad "(") ('word "b")) (('cmd "$(a)") ('cmd "$(b)")))

### contexts nest 63 deep, and an opener past that ends the match

```x
(do
  (import x/reader/lexer)
  (def %lxn-l (Lexer make (list
    (Lexer nested 'cmd "$(" 'cmd (list (list 'cmd 41 () (list (pair "$(" 'cmd)))))
    (Lexer run 'word "x$" "x$")
    (Lexer any 'bad))))
  (def %lxn-deep
    (fn (_ n)
      ((fn (self k pre post) (if (= k 0) (Str8 append pre "x" post) (self (- k 1) (Str8 append pre "$(") (Str8 append post ")"))))
       n "" "")))
  (write (list (first (first (%lxn-l read-str (%lxn-deep 63))))
               (first (first (%lxn-l read-str (%lxn-deep 70))))
               (first (first (%lxn-l read-str (%lxn-deep 2))))))
  (newline))
```
---
    ('cmd 'word 'cmd)

### a rule its states could not read is refused at make

```x
(do
  (import x/reader/lexer)
  (def %lxn-try
    (fn (_ ctx)
      (guard (e 'refused)
        (Lexer make (list (Lexer nested 'n "(" 'a ctx)))
        'made)))
  (write (list (%lxn-try (list (list 'a 41 () (list (pair "(" 'b)))))
               (%lxn-try (list (list 'a 41 () (list (pair "$" 'a) (pair "$(" 'a)))))
               (%lxn-try (list (list 'a 41 () (list (pair ")" 'a)))))
               (%lxn-try (list (list 'a 41 () (list (pair "(" 'a)))))))
  (newline))
```
---
    ('refused 'refused 'refused 'made)
