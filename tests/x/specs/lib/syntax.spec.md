# Syntax: grammars, spans and renderers
# @weight 1

`x/tool/syntax` reads text with a grammar's Lexer and answers spans, each
`(offset length class)`; the renderers draw spans as ANSI, HTML or a row of
class cells.

## x-lang's grammar

### a line's spans, blanks left out

```x
(do (import x/tool/syntax)
    ((Syntax x) spans "(def x 42) ; hi"))
```
---
    ((0 1 'punct) (1 3 'keyword) (5 1 'name) (7 2 'number) (9 1 'punct) (11 4 'comment))

### atoms are classed by what the reader reads them as

```x
(do (import x/tool/syntax)
    (List map (fn (_ s) (Syntax classify s))
      (list "def" "42" "\"s\"" "#\\a" "#t" "foo" "%p" "Str8" "-")))
```
---
    ('keyword 'number 'string 'char 'constant 'name 'private 'class 'name)

### a paren in a string, a comment or a character literal is not punct

```x
(do (import x/tool/syntax)
    ((Syntax x) spans "\"(\" ; (\n#\\("))
```
---
    ((0 3 'string) (4 3 'comment) (8 3 'char))

### an unterminated string runs to the end

```x
(do (import x/tool/syntax)
    ((Syntax x) spans "(f \"open"))
```
---
    ((0 1 'punct) (1 1 'name) (3 5 'string))

## Ranges

### spans are clipped to the range asked for

```x
(do (import x/tool/syntax)
    ((Syntax x) spans "\"a b\" c" 3 4))
```
---
    ((3 2 'string) (6 1 'name))

### a string opened on an earlier line colours the range's start

The grammar reads from the line that opens the top-level form.

```x
(do (import x/tool/syntax)
    ((Syntax x) spans "(def a\n  \"multi\nline\")\n(foo)" 14 4))
```
---
    ((14 4 'string))

### nothing past the end given is read

```x
(do (import x/tool/syntax)
    ((Syntax x) spans "(f) junk\"" 0 3 3))
```
---
    ((0 1 'punct) (1 1 'name) (2 1 'punct))

## Renderers

### html writes Rouge token classes, every byte escaped

```x
(do (import x/tool/syntax)
    (let ((s "(< a \"&\")"))
      (Syntax html s ((Syntax x) spans s) 0 (Str8 length s))))
```
---
    "<span class=\"p\">(</span><span class=\"n\">&lt;</span> <span class=\"n\">a</span> <span class=\"s\">\"&amp;\"</span><span class=\"p\">)</span>"

### cells holds a class byte a text byte

```x
(do (import x/tool/syntax)
    (let ((s "(f 1) ; c"))
      (let ((c (Syntax cells ((Syntax x) spans s) 0 (Str8 length s))))
        (list c (Syntax cell-class (Str8 ref 0 c)) (Syntax cell-class 32)))))
```
---
    ("JI DJ AAA" 'punct ())

### sgr is the class's sequence whatever standard output is

```x
(do (import x/tool/syntax)
    (list (Syntax sgr 'string) (Syntax sgr 'punct) (Syntax code 'string)))
```
---
    ("\x1b[32m" "" "")

### ansi takes a span's sequence from code-of when it answers one

```x
(do (import x/tool/syntax)
    (let ((s "(f 1)"))
      (Syntax ansi s ((Syntax x) spans s) 1 3
        (fn (_ sp) (if (= (first sp) 1) "<F>" ())))))
```
---
    "<F>f\x1b[0m 1"

### the classes, their indexes and Rouge names

```x
(do (import x/tool/syntax)
    (list (List length (Syntax classes)) (Syntax index 'comment) (Syntax index 'nope)
          (Syntax rouge 'keyword) (Syntax rouge ())))
```
---
    (13 1 0 "k" ())

## Grammars

### a grammar of its own, registered and found by file name

```x
(do (import x/tool/syntax)
    (let ((g (Syntax make 'ini
               (list (Lexer until 'comment ";" "\n" 'to-end)
                     (Lexer run 'blank " \t\n" " \t\n")
                     (Lexer run 'key "abcdefghijklmnopqrstuvwxyz" "abcdefghijklmnopqrstuvwxyz")
                     (Lexer any 'other))
               (list (pair 'comment 'comment) (pair 'key 'keyword)))))
      (g files (list ".ini"))
      (Syntax register! g)
      (list ((Syntax for-file "my.ini") name) (eq? (Syntax named 'ini) g)
            (g spans "ab=1 ; c\n"))))
```
---
    ('ini #t ((0 2 'keyword) (5 3 'comment)))

### a class may be a function of the token's text

```x
(do (import x/tool/syntax)
    (let ((g (Syntax make 'w
               (list (Lexer run 'blank " " " ") (Lexer run 'word "abcz" "abcz"))
               (list (pair 'word (fn (_ t) (if (str=? t "zz") 'error ())))))))
      (g spans "ab zz c")))
```
---
    ((3 2 'error))

### x-lang's grammar is for .x files

```x
(do (import x/tool/syntax)
    (list ((Syntax for-file "lib/x/tool/syntax.x") name) (Syntax for-file "notes.txt")))
```
---
    ('x ())
