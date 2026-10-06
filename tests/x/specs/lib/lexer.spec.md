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

### a run with a follow class is a token only before a byte of it

```x
(do
  (import x/reader/lexer)
  (def %lx-l (Lexer make (list
    (Lexer skip " ")
    (Lexer run 'io (list (pair 48 57)) (list (pair 48 57)) "<>")
    (Lexer table 'op (list "<" ">" ">>"))
    (Lexer run 'w (list (pair 97 122) (pair 48 57)) (list (pair 97 122) (pair 48 57))))))
  (write (%lx-l read-str "13>a 22 b 2>>c 9"))
  (newline))
```
---
    (('io "13") ('op ">") ('w "a") ('w "22") ('w "b") ('io "2") ('op ">>") ('w "c") ('w "9"))

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

## words

A word rule is a nested span with no opening literal: its first byte is read
in its start context, and it ends before a stop byte met at depth 0.  These
are a POSIX shell's words: a backslash escapes, quotes and command
substitutions are spans inside the word, and blanks and operators end it.

### quotes, escapes and substitutions are inside one word, which a stop byte ends

```x
(do
  (import x/reader/lexer)
  (def %lxw-ctx
    (list (list 'w () 92 (list (pair "\"" 'dq) (pair "'" 'sq) (pair "$(" 'cmd)))
          (list 'dq 34 92 (list (pair "$(" 'cmd)))
          (list 'sq 39 () ())
          (list 'cmd 41 92 (list (pair "(" 'cmd) (pair "\"" 'dq) (pair "'" 'sq)))))
  (def %lxw-l (Lexer make (list
    (Lexer skip " ")
    (Lexer table 'op (list ";" "|" "&&"))
    (Lexer word 'word 'w %lxw-ctx " \n;|&"))))
  (write (list (%lxw-l read-str "a\\ b\"c d\"$(e f) g;h|i")
               (%lxw-l read-str "\"a;b\" $(x; y)'|' &&z")))
  (newline))
```
---
    ((('word "a\\ b\"c d\"$(e f)") ('word "g") ('op ";") ('word "h") ('op "|") ('word "i")) (('word "\"a;b\"") ('word "$(x; y)'|'") ('op "&&") ('word "z")))

### a read left inside an open span, and an opener past the stack's depth, leave the next word whole

```x
(do
  (import x/reader/lexer)
  (def %lxw-l (Lexer make (list
    (Lexer skip " ")
    (Lexer word 'word 'w (list (list 'w () () (list (pair "$(" 'cmd)))
                               (list 'cmd 41 () (list (pair "$(" 'cmd))))
                " ")
    (Lexer any 'bad))))
  (def %lxw-deep
    (fn (_ n)
      ((fn (self k pre post) (if (= k 0) (Str8 append pre "x" post) (self (- k 1) (Str8 append pre "$(") (Str8 append post ")"))))
       n "" "")))
  (write (list (%lxw-l read-str "a$(b")
               (%lxw-l read-str "c d")
               (List length (%lxw-l read-str (Str8 append (%lxw-deep 70) " y")))
               (List last (%lxw-l read-str (Str8 append (%lxw-deep 70) " y")))))
  (newline))
```
---
    ((('bad "a") ('bad "$") ('bad "(") ('bad "b")) (('word "c") ('word "d")) 15 ('word "y"))

### a word with no stop class, or a span with no close, is refused at make

```x
(do
  (import x/reader/lexer)
  (def %lxw-try
    (fn (_ rule)
      (guard (e 'refused) (Lexer make (list rule)) 'made)))
  (write (list (%lxw-try (Lexer word 'w 'a (list (list 'a () () ())) ()))
               (%lxw-try (Lexer word 'w 'a (list (list 'a () () (list (pair "(" 'b))) (list 'b () () ())) " "))
               (%lxw-try (Lexer word 'w 'a (list (list 'a () () (list (pair "(" 'b))) (list 'b 41 () ())) " "))))
  (newline))
```
---
    ('refused 'refused 'made)

## until: a close that is taken, a span that runs to the end

### take makes a one-byte close part of the token

```x
(do
  (import x/reader/lexer)
  (def %lx-l (Lexer make (list
    (Lexer skip " ")
    (Lexer until 'pat "/" "/" 'take)
    (Lexer run 'w "abcdefghijklmnopqrstuvwxyz" "abcdefghijklmnopqrstuvwxyz"))))
  (write (%lx-l read-str "/ab/ c /d/"))
  (newline))
```
---
    (('pat "/ab/") ('w "c") ('pat "/d/"))

### to-end takes a span no close ended, and the end text is not part of it

The end text is a space here, and a space inside the span stays: only the
bytes read-str appended are cut.

```x
(do
  (import x/reader/lexer)
  (def %lx-l (Lexer make (list
    (Lexer skip " ")
    (Lexer until 'pat "/" "/" 'take 'to-end)
    (Lexer run 'w "abcdefghijklmnopqrstuvwxyz" "abcdefghijklmnopqrstuvwxyz"))))
  (write (list (%lx-l read-str "s/a/b/g") (%lx-l read-str "/a b") (%lx-l read-str "/a/")))
  (newline))
```
---
    ((('w "s") ('pat "/a/") ('w "b") ('pat "/g")) (('pat "/a b")) (('pat "/a/")))

### without to-end a span no close ended is not a token

```x
(do
  (import x/reader/lexer)
  (def %lx-l (Lexer make (list
    (Lexer skip " ")
    (Lexer until 'pat "/" "/" 'take)
    (Lexer run 'w "abcdefghijklmnopqrstuvwxyz" "abcdefghijklmnopqrstuvwxyz")
    (Lexer any 'bad))))
  (write (%lx-l read-str "a /b"))
  (newline))
```
---
    (('w "a") ('bad "/") ('w "b"))

### to-end with a close left for the next token, and a close the input supplies

A line comment that the text's own newline ends is the comment up to it; one
the text ends without a newline is the comment to the end.  With a newline as
the end text and take, a close the input supplies stays in the token.

```x
(do
  (import x/reader/lexer)
  (def %lx-l (Lexer make (list
    (Lexer skip " ")
    (Lexer table 'nl (list "\n"))
    (Lexer until 'c "#" "\n" 'to-end)
    (Lexer run 'w "abcdefghijklmnopqrstuvwxyz" "abcdefghijklmnopqrstuvwxyz"))))
  (def %lx-t (Lexer make (list
    (Lexer until 'c "//" "\n" 'take 'to-end)
    (Lexer run 'w "abcdefghijklmnopqrstuvwxyz" "abcdefghijklmnopqrstuvwxyz"))
    "\n"))
  (write (list (%lx-l read-str "a # c") (%lx-l read-str "a # c\nb")
               (%lx-t read-str "// x") (%lx-t read-str "// x\n")))
  (newline))
```
---
    ((('w "a") ('c "# c")) (('w "a") ('c "# c") ('nl "\n") ('w "b")) (('c "// x")) (('c "// x\n")))

### an unknown flag is refused

```x
(do
  (import x/reader/lexer)
  (write (guard (e (lit refused)) (Lexer until 'c "#" "\n" 'greedy)))
  (newline))
```
---
    'refused

## nested and word: a span still open at the end

### to-end makes a word or a nested span left open at the end a token, the end text cut

The end text is a newline, and a blank inside the open span stays; spans that
close read as they do without the flag.

```x
(do
  (import x/reader/lexer)
  (def %lxe-ctx
    (list (list 'w () 92 (list (pair "\"" 'dq) (pair "'" 'sq) (pair "$(" 'cmd) (pair "${" 'brace)))
          (list 'dq 34 92 (list (pair "$(" 'cmd) (pair "${" 'brace)))
          (list 'sq 39 () ())
          (list 'cmd 41 92 (list (pair "(" 'cmd) (pair "\"" 'dq) (pair "'" 'sq)))
          (list 'brace 125 92 (list (pair "\"" 'dq) (pair "'" 'sq)))))
  (def %lxe-l (Lexer make (list
    (Lexer skip " ")
    (Lexer table 'nl (list "\n"))
    (Lexer nested 'dq "\"" 'dq (rest %lxe-ctx) 'to-end)
    (Lexer word 'word 'w %lxe-ctx " \n" 'to-end))
    "\n"))
  (write (list (%lxe-l read-str "a ${X") (%lxe-l read-str "'a'\"b") (%lxe-l read-str "x $(echo a")
               (%lxe-l read-str "\"a $(b") (%lxe-l read-str "\"a\" b${c}\n")))
  (newline))
```
---
    ((('word "a") ('word "${X")) (('word "'a'\"b")) (('word "x") ('word "$(echo a")) (('dq "\"a $(b")) (('dq "\"a\"") ('word "b${c}") ('nl "\n")))

### a nested or word flag other than to-end is refused

```x
(do
  (import x/reader/lexer)
  (def %lxe-c (list (list 'w () () ()) (list 'q 34 () ())))
  (write (list (guard (e (lit refused)) (Lexer nested 'q "\"" 'q %lxe-c 'take))
               (guard (e (lit refused)) (Lexer word 'w 'w %lxe-c " " 'greedy))))
  (newline))
```
---
    ('refused 'refused)

## record: a binary record that says its own length

### bytes and units steps: a fixed tail, and units until a marked one

```x
(do
  (import x/reader/lexer)
  (def %lxr-l (Lexer make (list
    (Lexer record 'rec (list (pair "ab" (lit ((bytes 1))))
                             (pair "z" (lit ((units 1 32))))
                             (pair "y" (lit ((units 2 32))))
                             (pair "." ()))))))
  (write (%lxr-l read-str "a1b2zDq.yABcd."))
  (newline))
```
---
    (('rec "a1" 2) ('rec "b2" 2) ('rec "zDq" 3) ('rec "." 1) ('rec "yABcd" 5) ('rec "." 1))

### a fields step: four 2-bit fields a byte, sizes by value, stop ends them

`U` is 01 01 01 01 -- four fields of one byte each -- and `?` is 00 11 11 11:
a field of two bytes, then stop.  With two field bytes the record is the
opcode, both field bytes, then six operand bytes; with one, `_` (01 01 11
11) owes two.

```x
(do
  (import x/reader/lexer)
  (def %lxr-f (Lexer make (list
    (Lexer record 'v (list (pair "w" (list (list (lit fields) 2 (lit (2 1 1 stop)))))
                           (pair "v" (list (list (lit fields) 1 (lit (2 1 1 stop))))))))))
  (write (%lxr-f read-str "wU?abcdefv_xyv?pq"))
  (newline))
```
---
    (('v "wU?abcdef" 9) ('v "v_xy" 4) ('v "v?pq" 4))

### a flag step: more bytes only when the mask's bits are clear; steps chain

`@` has bit 64 set, `!` does not.

```x
(do
  (import x/reader/lexer)
  (def %lxr-g (Lexer make (list
    (Lexer record 'br (list (pair "f" (lit ((flag 64 1))))
                            (pair "g" (lit ((bytes 1) (flag 64 1) (units 1 32)))))))))
  (write (%lxr-g read-str "f@f!xg1@Hig2!!q"))
  (newline))
```
---
    (('br "f@" 2) ('br "f!x" 3) ('br "g1@Hi" 5) ('br "g2!!q" 5))

### a first byte in no class ends the read

```x
(do
  (import x/reader/lexer)
  (def %lxr-h (Lexer make (list (Lexer record 'r (list (pair "a" (lit ((bytes 1)))))))))
  (write (%lxr-h read-str "a1a2#a3"))
  (newline))
```
---
    (('r "a1" 2) ('r "a2" 2))

### a step its states could not count is refused

```x
(do
  (import x/reader/lexer)
  (write (list (guard (e (lit refused)) (Lexer record 'r (list (pair "a" (lit ((bytes -1)))))))
               (guard (e (lit refused)) (Lexer record 'r (list (pair "a" (lit ((fields 1 (1 2))))))))
               (guard (e (lit refused)) (Lexer record 'r (list (pair "a" (lit ((flag 0 1)))))))
               (guard (e (lit refused)) (Lexer record 'r (list (pair "a" (lit ((units 0 128)))))))
               (guard (e (lit refused)) (Lexer record 'r (list (pair "a" (lit ((skip 2)))))))))
  (newline))
```
---
    ('refused 'refused 'refused 'refused 'refused)

## read-span: a span of bytes, NULs included

### records in a binary buffer, read from an offset, NULs and high bytes as bytes

The buffer is 00 03 41 00 C1 10 20 05 01 02 03 04 05 FF 7F: from offset 1, a
record led by
03 owes two bytes, one led by C1 a fields byte (10 = 00 01 00 00: two, one,
two, two) and seven operand bytes; FF starts a record the span ends before it
is whole, which is no token.  The tokens' text holds
the NUL bytes, so each is shown as its byte list, as long as the length the
token carries: a string's own length stops at its first NUL.

```x
(do
  (import x/reader/lexer)
  (def %lxs-mk (prim-ref (lit str) (lit make)))
  (def %lxs-p (prim-ref (lit str) (lit ->ptr)))
  (def %lxs-set (prim-ref (lit ptr) (lit set!)))
  (def %lxs-ref (prim-ref (lit str) (lit byte-ref)))
  (def %lxs-b (%lxs-mk 16))
  (def %lxs-bytes (list 0 3 65 0 193 16 32 5 1 2 3 4 5 255 127))
  ((fn (self bs i) (if (null? bs) () (do (%lxs-set (%lxs-p %lxs-b) i (first bs) 1) (self (rest bs) (+ i 1)))))
   %lxs-bytes 0)
  (def %lxs-l (Lexer make (list
    (Lexer record 'op (list (pair (list 3) (lit ((bytes 2))))
                            (pair (list (pair 192 255)) (list (list (lit fields) 1 (lit (2 1 2 stop))))))))))
  (def %lxs-codes
    (fn (_ t)
      (def s (first (rest t)))
      ((fn (self i acc) (if (< i 0) acc (self (- i 1) (pair (& ((prim-ref (lit char) (lit ->int)) (%lxs-ref s i)) 255) acc))))
       (- (first (rest (rest t))) 1) ())))
  (write (List map %lxs-codes (%lxs-l read-span %lxs-b 1 14)))
  (newline))
```
---
    ((3 65 0) (193 16 32 5 1 2 3 4 5))
