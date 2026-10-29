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
    (Theme use! (Theme default))
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

## Themes

### the default theme draws every class as the table before themes did

```x
(do (import x/tool/syntax)
    (List map (fn (_ c) ((Theme default) sgr c)) (Syntax classes)))
```
---
    ("\x1b[2m" "\x1b[32m" "\x1b[35m" "\x1b[33m" "\x1b[1;35m" "\x1b[1;31m" "\x1b[1;36m" "\x1b[2m" "\x1b[34m" "" "" "\x1b[35m" "\x1b[1;31m")

### with puts rows over a theme: the classes they name change, the rest stay

```x
(do (import x/tool/syntax)
    (let ((t ((Theme default) with '((number (bold underline) 3 ()) (string () () 4)))))
      (list (t name) (t sgr 'number) (t sgr 'string) (t sgr 'keyword)
            (((Theme default) with '() 'copy) name))))
```
---
    ('default "\x1b[1;4;33m" "\x1b[44m" "\x1b[1;35m" 'copy)

### make draws only the classes it is given; an unknown class or attribute is refused

```x
(do (import x/tool/syntax)
    (let ((t (Theme make 'mono '((keyword (bold) () ()) (number () 196 ())))))
      (list (t sgr 'keyword) (t sgr 'number) (t sgr 'string) (t style 'string)
            (guard (e (Err label e)) (Theme make 'bad '((nope () 1 ()))))
            (guard (e (Err label e)) (Theme make 'bad '((name (shiny) () ())))))))
```
---
    ("\x1b[1m" "\x1b[38;5;196m" "" 0 'value 'value)

### the theme in use is what sgr and ansi draw with

```x
(do (import x/tool/syntax)
    (let ((was (Theme current))
          (t (Theme make 'k '((keyword (reverse) () ())))))
      (Theme use! t)
      (def seen (list (Syntax sgr 'keyword) (Syntax sgr 'name)
                      (Syntax ansi "(def x)" ((Syntax x) spans "(def x)") 1 3
                        (fn (_ sp) (if (eq? (first (rest (rest sp))) 'keyword) (Syntax sgr 'keyword) ())))))
      (Theme use! was)
      (list seen (eq? (Theme current) was))))
```
---
    (("\x1b[7m" "" "\x1b[7mdef\x1b[0m") #t)

### registered themes are named; default is always there

```x
(do (import x/tool/syntax)
    (Theme register! (Theme make 'spec-dark '((comment (italic) 8 ()))))
    (list ((Theme named 'spec-dark) sgr 'comment) (Theme named 'spec-none)
          (eq? (Theme named 'default) (Theme default))
          (List includes? 'spec-dark (Theme names)) (List last (Theme names))))
```
---
    ("\x1b[3;90m" () #t #t 'default)

### a theme file's themes lie over the ones known, and its use is the theme in use

```x
(do (import x/sys/posix) (import x/sys/file) (import x/tool/syntax)
  (def tmp (File temp "/tmp/x-spec-theme-"))
  (File close (first tmp))
  (def p (rest tmp))
  (File write-all p
    "; mine\n(theme default (comment (italic) () ()))\n(theme warm (keyword (bold) 1 ()))\n(use warm)\n")
  (def was (Theme current))
  (def themes (Theme load! p))
  (def seen
    (list (List map (fn (_ t) (t name)) themes)
          ((Theme current) name)
          ((Theme current) sgr 'keyword)
          ((Theme current) sgr 'number)
          ((Theme named 'default) sgr 'comment)
          ((Theme named 'default) sgr 'number)
          ((Theme default) sgr 'comment)))
  (File unlink p)
  (Theme forget!)
  (Theme use! was)
  seen)
```
---
    (('default 'warm) 'warm "\x1b[1;31m" "\x1b[33m" "\x1b[3m" "\x1b[33m" "\x1b[2m")

### a theme file that does not read changes nothing

```x
(do (import x/sys/posix) (import x/sys/file) (import x/tool/syntax)
  (def tmp (File temp "/tmp/x-spec-theme-"))
  (File close (first tmp))
  (def p (rest tmp))
  (def was (Theme current))
  (File write-all p "(theme warm (keyword (bold) 1 ()))\n(use cold)\n")
  (def a (guard (e (Err label e)) (Theme load! p)))
  (File write-all p "(colour keyword red)\n")
  (def b (guard (e (Err label e)) (Theme load! p)))
  (File unlink p)
  (list a b (Theme named 'warm) (eq? (Theme current) was)))
```
---
    ('value 'value () #t)

### the theme file is X_THEME, and an empty X_THEME reads none

```x
(do (import x/sys/posix) (import x/tool/syntax)
  (def was (Sys getenv "X_THEME"))
  (Sys setenv "X_THEME" "/tmp/x-spec-theme-file")
  (def a (Theme file))
  (Sys setenv "X_THEME" "")
  (def b (Theme file))
  (Sys setenv "X_THEME" (if (null? was) "" was))
  (list a b))
```
---
    ("/tmp/x-spec-theme-file" ())

### the user's theme file is read on first use; one that does not read leaves the default

```x
(do (import x/sys/posix) (import x/sys/file) (import x/tool/syntax)
  (def tmp (File temp "/tmp/x-spec-theme-"))
  (File close (first tmp))
  (def p (rest tmp))
  (def was (Sys getenv "X_THEME"))
  (Sys setenv "X_THEME" p)
  (File write-all p "(theme warm (keyword (bold) 1 ()))\n(use warm)\n")
  (Theme forget!)
  (def a ((Theme current) name))
  (File write-all p "(theme warm (keyword (shiny) 1 ()))\n(use warm)\n")
  (Theme forget!)
  (def b ((Theme current) name))
  (File unlink p)
  (Theme forget!)
  (Sys setenv "X_THEME" (if (null? was) "" was))
  (list a b (Theme named 'warm)))
```
---
    ('warm 'default ())

## The catalogue

Each case makes a langs directory holding one bundle, `fx`, whose lang.xon
declares a grammar and whose `fx/syntax.x` registers it, and points
`X_LANG_DIR` at it.

### a bundle's grammar is in the catalogue, its module loaded when named

```x
(do (import x/sys/posix) (import x/sys/file) (import x/tool/syntax)
  (def tmp (File temp "/tmp/x-spec-langs-"))
  (File close (first tmp))
  (def d (rest tmp))
  (File unlink d)
  (List for-each (fn (_ s) (File mkdir (Str8 append d s))) (list "" "/fx" "/fx/fx"))
  (File write-all (Str8 append d "/fx/lang.xon")
    "(lang \"fx\")\n(grammar fx (module fx/syntax) (files \".fx\") (names \"Fxfile\") (interpreters \"fx\"))\n")
  (File write-all (Str8 append d "/fx/fx/syntax.x")
    "(import x/tool/syntax)\n(Syntax register! (Syntax make 'fx (list (Lexer run 'word \"abc\" \"abc\") (Lexer any 'other)) (list (pair 'word 'keyword))))\n")
  (def was (Sys getenv "X_LANG_DIR"))
  (Sys setenv "X_LANG_DIR" d)
  (Syntax forget!)
  (def row (fn (_) (List find (fn (_ r) (eq? (first r) 'fx)) (Syntax catalogue))))
  (def before (List ref 1 (row)))
  (def g (Syntax named 'fx))
  (def seen (list before (g name) (List ref 1 (row)) (g files) (g interpreters) (g spans "ab c")))
  (List for-each (fn (_ s) (File unlink (Str8 append d s))) (list "/fx/fx/syntax.x" "/fx/lang.xon"))
  (List for-each (fn (_ s) (File rmdir (Str8 append d s))) (list "/fx/fx" "/fx" ""))
  (Sys setenv "X_LANG_DIR" (if (null? was) "" was))
  (Syntax forget!)
  seen)
```
---
    ('fx/syntax 'fx () (".fx") ("fx") ((0 2 'keyword)))

### a file's grammar: modeline, then #! interpreter, then suffix or name

```x
(do (import x/sys/posix) (import x/sys/file) (import x/tool/syntax)
  (def tmp (File temp "/tmp/x-spec-langs-"))
  (File close (first tmp))
  (def d (rest tmp))
  (File unlink d)
  (List for-each (fn (_ s) (File mkdir (Str8 append d s))) (list "" "/fx" "/fx/fx"))
  (File write-all (Str8 append d "/fx/lang.xon")
    "(lang \"fx\")\n(grammar fx (module fx/syntax) (files \".fx\") (names \"Fxfile\") (interpreters \"fx\"))\n")
  (File write-all (Str8 append d "/fx/fx/syntax.x")
    "(import x/tool/syntax)\n(Syntax register! (Syntax make 'fx (list (Lexer any 'other)) ()))\n")
  (def was (Sys getenv "X_LANG_DIR"))
  (Sys setenv "X_LANG_DIR" d)
  (Syntax forget!)
  (def name (fn (_ path . text)
    (let ((g (apply Syntax (pair 'for-file (pair path text))))) (if (null? g) () (g name)))))
  (def seen
    (list (name "a.fx") (name "src/Fxfile") (name "Fxfile.bak")
          (name "run" "#!/usr/bin/env -S fx2.1 -q\nabc\n")
          (name "run" "#! /opt/bin/fx\n")
          (name "a.x" "; vi: set ts=4 ft=fx:\n(x)\n")
          (name "a.fx" "1\n2\n3\n4\n5\n6\n7\n; vim: syntax=x\n")
          (name "a.fx" "#!/bin/x\n")
          (name "run" "#!/bin/sh\n")))
  (List for-each (fn (_ s) (File unlink (Str8 append d s))) (list "/fx/fx/syntax.x" "/fx/lang.xon"))
  (List for-each (fn (_ s) (File rmdir (Str8 append d s))) (list "/fx/fx" "/fx" ""))
  (Sys setenv "X_LANG_DIR" (if (null? was) "" was))
  (Syntax forget!)
  seen)
```
---
    ('fx 'fx () 'fx 'fx 'fx 'x 'x ())

### a lang.xon that does not read, or a module that registers nothing, is no grammar

A bundle row is one with a module; the registered grammars have none.

```x
(do (import x/sys/posix) (import x/sys/file) (import x/tool/syntax)
  (def tmp (File temp "/tmp/x-spec-langs-"))
  (File close (first tmp))
  (def d (rest tmp))
  (File unlink d)
  (List for-each (fn (_ s) (File mkdir (Str8 append d s))) (list "" "/fy" "/fy/fy" "/bad"))
  (File write-all (Str8 append d "/fy/lang.xon")
    "(lang \"fy\")\n(grammar fy (module fy/syntax) (files \".fy\"))\n")
  (File write-all (Str8 append d "/fy/fy/syntax.x") "(def fy-loaded #t)\n")
  (File write-all (Str8 append d "/bad/lang.xon") "(lang \"bad\")\n(grammar (module bad/syntax))\n")
  (def was (Sys getenv "X_LANG_DIR"))
  (Sys setenv "X_LANG_DIR" d)
  (Syntax forget!)
  (def names (fn (_) (List map first (List filter (fn (_ r) (not (null? (List ref 1 r)))) (Syntax catalogue)))))
  (def seen (list (names) (Syntax named 'fy) (Syntax for-file "a.fy") (names)))
  (List for-each (fn (_ s) (File unlink (Str8 append d s)))
    (list "/fy/fy/syntax.x" "/fy/lang.xon" "/bad/lang.xon"))
  (List for-each (fn (_ s) (File rmdir (Str8 append d s))) (list "/fy/fy" "/fy" "/bad" ""))
  (Sys setenv "X_LANG_DIR" (if (null? was) "" was))
  (Syntax forget!)
  seen)
```
---
    (('fy) () () ())
