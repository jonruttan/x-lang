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

### a class function may answer the token's pieces

Each piece is (offset length class) inside the token, in order; a piece of
class nil is left plain, and pieces are clipped to the range like any span.

```x
(do (import x/tool/syntax)
    (let ((g (Syntax make 'kv
               (list (Lexer run 'blank " " " ") (Lexer run 'pair "abc=" "abc="))
               (list (pair 'pair
                       (fn (_ t)
                         (let ((i (Str8 index-of "=" t)))
                           (if (null? i) 'name
                             (list (list 0 i 'name) (list i 1 ()) (list (+ i 1) (- (Str8 length t) (+ i 1)) 'string))))))))))
      (list (g spans "ab=c a") (g spans "ab=c a" 1 3))))
```
---
    (((0 2 'name) (3 1 'string) (5 1 'name)) ((1 1 'name) (3 1 'string)))

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

Each case makes a bundles directory holding one bundle, `fx`, whose bundle.xon
declares a grammar and whose `fx/syntax.x` registers it, and points
`X_BUNDLE_DIR` at it.

### a bundle's grammar is in the catalogue, its module loaded when named

```x
(do (import x/sys/posix) (import x/sys/file) (import x/tool/syntax)
  (def tmp (File temp "/tmp/x-spec-langs-"))
  (File close (first tmp))
  (def d (rest tmp))
  (File unlink d)
  (List for-each (fn (_ s) (File mkdir (Str8 append d s))) (list "" "/fx" "/fx/lib" "/fx/lib/fx"))
  (File write-all (Str8 append d "/fx/bundle.xon")
    "(name \"fx\")\n(grammar fx (module fx/syntax) (files \".fx\") (names \"Fxfile\") (interpreters \"fx\"))\n")
  (File write-all (Str8 append d "/fx/lib/fx/syntax.x")
    "(import x/tool/syntax)\n(Syntax register! (Syntax make 'fx (list (Lexer run 'word \"abc\" \"abc\") (Lexer any 'other)) (list (pair 'word 'keyword))))\n")
  (def was (Sys getenv "X_BUNDLE_DIR"))
  (Sys setenv "X_BUNDLE_DIR" d)
  (Syntax forget!)
  (def row (fn (_) (List find (fn (_ r) (eq? (first r) 'fx)) (Syntax catalogue))))
  (def before (List ref 1 (row)))
  (def g (Syntax named 'fx))
  (def seen (list before (g name) (List ref 1 (row)) (g files) (g interpreters) (g spans "ab c")))
  (List for-each (fn (_ s) (File unlink (Str8 append d s))) (list "/fx/lib/fx/syntax.x" "/fx/bundle.xon"))
  (List for-each (fn (_ s) (File rmdir (Str8 append d s))) (list "/fx/lib/fx" "/fx/lib" "/fx" ""))
  (Sys setenv "X_BUNDLE_DIR" (if (null? was) "" was))
  (Syntax forget!)
  seen)
```
---
    ('fx/syntax 'fx () (".fx") ("fx") ((0 2 'keyword) (3 1 'keyword)))

### a file's grammar: modeline, then #! interpreter, then suffix or name

```x
(do (import x/sys/posix) (import x/sys/file) (import x/tool/syntax)
  (def tmp (File temp "/tmp/x-spec-langs-"))
  (File close (first tmp))
  (def d (rest tmp))
  (File unlink d)
  (List for-each (fn (_ s) (File mkdir (Str8 append d s))) (list "" "/fx" "/fx/lib" "/fx/lib/fx"))
  (File write-all (Str8 append d "/fx/bundle.xon")
    "(name \"fx\")\n(grammar fx (module fx/syntax) (files \".fx\") (names \"Fxfile\") (interpreters \"fx\"))\n")
  (File write-all (Str8 append d "/fx/lib/fx/syntax.x")
    "(import x/tool/syntax)\n(Syntax register! (Syntax make 'fx (list (Lexer any 'other)) ()))\n")
  (def was (Sys getenv "X_BUNDLE_DIR"))
  (Sys setenv "X_BUNDLE_DIR" d)
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
  (List for-each (fn (_ s) (File unlink (Str8 append d s))) (list "/fx/lib/fx/syntax.x" "/fx/bundle.xon"))
  (List for-each (fn (_ s) (File rmdir (Str8 append d s))) (list "/fx/lib/fx" "/fx/lib" "/fx" ""))
  (Sys setenv "X_BUNDLE_DIR" (if (null? was) "" was))
  (Syntax forget!)
  seen)
```
---
    ('fx 'fx () 'fx 'fx 'fx 'x 'x ())

### the user's syntax file gives a file its grammar, after a modeline and before the grammars' own

The rule makes .x files, a Build file and a #! line running zz read as fx; a
modeline still names x, and a name no rule holds keeps its grammar.  A file
that does not read is no rules.

```x
(do (import x/sys/posix) (import x/sys/file) (import x/tool/syntax)
  (def tmp (File temp "/tmp/x-spec-langs-"))
  (File close (first tmp))
  (def d (rest tmp))
  (File unlink d)
  (List for-each (fn (_ s) (File mkdir (Str8 append d s))) (list "" "/fx" "/fx/lib" "/fx/lib/fx"))
  (File write-all (Str8 append d "/fx/bundle.xon")
    "(name \"fx\")\n(grammar fx (module fx/syntax) (files \".fx\"))\n")
  (File write-all (Str8 append d "/fx/lib/fx/syntax.x")
    "(import x/tool/syntax)\n(Syntax register! (Syntax make 'fx (list (Lexer any 'other)) ()))\n")
  (def rules (Str8 append d "/syntax.x"))
  (File write-all rules "(grammar fx (files \".x\") (names \"Build\") (interpreters \"zz\"))\n")
  (def was-langs (Sys getenv "X_BUNDLE_DIR"))
  (def was-rules (Sys getenv "X_SYNTAX"))
  (Sys setenv "X_BUNDLE_DIR" d)
  (Sys setenv "X_SYNTAX" rules)
  (Syntax forget!)
  (def name (fn (_ path . text)
    (let ((g (apply Syntax (pair 'for-file (pair path text))))) (if (null? g) () (g name)))))
  (def ruled
    (list (name "a.x") (name "src/Build") (name "run" "#!/usr/bin/env zz\n")
          (name "a.x" "; vi: set ft=x:\n") (name "a.xon")))
  (File write-all rules "(grammar fx (module fx/syntax))\n")
  (Syntax forget!)
  (def unread (name "a.x"))
  (File unlink rules)
  (List for-each (fn (_ s) (File unlink (Str8 append d s))) (list "/fx/lib/fx/syntax.x" "/fx/bundle.xon"))
  (List for-each (fn (_ s) (File rmdir (Str8 append d s))) (list "/fx/lib/fx" "/fx/lib" "/fx" ""))
  (Sys setenv "X_BUNDLE_DIR" (if (null? was-langs) "" was-langs))
  (Sys setenv "X_SYNTAX" (if (null? was-rules) "" was-rules))
  (Syntax forget!)
  (list ruled unread))
```
---
    (('fx 'fx 'fx 'x 'x) 'x)

### the syntax file is X_SYNTAX, and an empty X_SYNTAX reads none

```x
(do (import x/sys/posix) (import x/tool/syntax)
  (def was (Sys getenv "X_SYNTAX"))
  (Sys setenv "X_SYNTAX" "/tmp/x-spec-syntax-file")
  (def a (Syntax rules-file))
  (Sys setenv "X_SYNTAX" "")
  (def b (Syntax rules-file))
  (Sys setenv "X_SYNTAX" (if (null? was) "" was))
  (list a b))
```
---
    ("/tmp/x-spec-syntax-file" ())

### a bundle.xon that does not read, or a module that registers nothing, is no grammar

A bundle row is one with a root; the registered grammars and x-lang's own have none.

```x
(do (import x/sys/posix) (import x/sys/file) (import x/tool/syntax)
  (def tmp (File temp "/tmp/x-spec-langs-"))
  (File close (first tmp))
  (def d (rest tmp))
  (File unlink d)
  (List for-each (fn (_ s) (File mkdir (Str8 append d s))) (list "" "/fy" "/fy/lib" "/fy/lib/fy" "/bad"))
  (File write-all (Str8 append d "/fy/bundle.xon")
    "(name \"fy\")\n(grammar fy (module fy/syntax) (files \".fy\"))\n")
  (File write-all (Str8 append d "/fy/lib/fy/syntax.x") "(def fy-loaded #t)\n")
  (File write-all (Str8 append d "/bad/bundle.xon") "(name \"bad\")\n(grammar (module bad/syntax))\n")
  (def was (Sys getenv "X_BUNDLE_DIR"))
  (Sys setenv "X_BUNDLE_DIR" d)
  (Syntax forget!)
  (def names (fn (_) (List map first (List filter (fn (_ r) (not (null? (List ref 2 r)))) (Syntax catalogue)))))
  (def seen (list (names) (Syntax named 'fy) (Syntax for-file "a.fy") (names)))
  (List for-each (fn (_ s) (File unlink (Str8 append d s)))
    (list "/fy/lib/fy/syntax.x" "/fy/bundle.xon" "/bad/bundle.xon"))
  (List for-each (fn (_ s) (File rmdir (Str8 append d s))) (list "/fy/lib/fy" "/fy/lib" "/fy" "/bad" ""))
  (Sys setenv "X_BUNDLE_DIR" (if (null? was) "" was))
  (Syntax forget!)
  seen)
```
---
    (('fy) () () ())

## x-lang's own grammars

x-lang ships grammars for formats no bundle owns in its library, rows in
the catalogue with a module and no root.

### they are in the catalogue and found by file name

```x
(do (import x/tool/syntax)
  (Syntax forget!)
  (def row (fn (_ n) (List find (fn (_ r) (eq? (first r) n)) (Syntax catalogue))))
  (def name (fn (_ f) (let ((g (Syntax for-file f))) (if (null? g) () (g name)))))
  (list (List map (fn (_ n) (List ref 3 (row n))) (list 'json 'markdown 'html))
        (List map name (list "a.json" "README.md" "doc.markdown" "i.htm" "x.html" "x.txt"))))
```
---
    (((".json") (".md" ".markdown") (".html" ".htm" ".xhtml")) ('json 'markdown 'markdown 'html 'html ()))

### JSON: a member's name, its value, and a word no JSON reads

A string followed by a colon is a name; true, false and null are constants;
any other word is an error; a comma or a bracket in a string is part of it.

```x
(do (import x/tool/syntax)
  (def g (Syntax named 'json))
  (list (g spans "{\"k\":\"v\", \"n\":-1.5e3,\"x\": nope, \"s\": \"a,]b\"}")
        (g spans "\"open")))
```
---
    (((0 1 'punct) (1 3 'name) (4 1 'punct) (5 3 'string) (8 1 'punct) (10 3 'name) (13 1 'punct) (14 6 'number) (20 1 'punct) (21 3 'name) (24 1 'punct) (26 4 'error) (30 1 'punct) (32 3 'name) (35 1 'punct) (37 6 'string) (43 1 'punct)) ((0 5 'string)))

### Markdown: quotes, emphasis, escapes and autolinks

Emphasis by _ inside a word is none, so snake_case_name stays plain.

```x
(do (import x/tool/syntax)
  ((Syntax named 'markdown) spans "> q *em* **st** snake_case_name \\* <http://x.y>\n"))
```
---
    ((0 2 'punct) (4 4 'constant) (9 6 'constant) (32 2 'escape) (35 12 'string))

### Markdown: fences, rules, list items, reference definitions, comments and images

```x
(do (import x/tool/syntax)
  (def g (Syntax named 'markdown))
  (list (g spans "```sh\nls\n```\n---\n1. one\n[r]: http://u\n")
        (g spans "text\n<!-- c -->\n![i](p) _e_")))
```
---
    (((0 5 'punct) (5 4 'string) (9 3 'punct) (13 3 'punct) (17 2 'punct) (24 4 'name) (28 9 'string)) ((5 10 'comment) (16 4 'name) (20 3 'string) (24 3 'constant)))

### HTML: declarations, comments, attributes quoted or not, and a lone <

A < before a byte that starts no tag is text.

```x
(do (import x/tool/syntax)
  ((Syntax named 'html) spans "<!DOCTYPE html>\n<!-- c --><p class=a id='b' hidden/>a < b"))
```
---
    ((0 15 'keyword) (16 10 'comment) (26 1 'punct) (27 1 'keyword) (29 5 'name) (34 1 'punct) (35 1 'string) (37 2 'name) (39 1 'punct) (40 3 'string) (44 6 'name) (50 1 'punct) (51 1 'punct))

### HTML: a script's or a style's body opens no tag

```x
(do (import x/tool/syntax)
  ((Syntax named 'html) spans "<script>if (a<b) x()</script><style>p{}</style>"))
```
---
    ((0 1 'punct) (1 6 'keyword) (7 1 'punct) (20 2 'punct) (22 6 'keyword) (28 1 'punct) (29 1 'punct) (30 5 'keyword) (35 1 'punct) (39 2 'punct) (41 5 'keyword) (46 1 'punct))

### the second set is found by file name

```x
(do (import x/tool/syntax)
  (def name (fn (_ f) (let ((g (Syntax for-file f))) (if (null? g) () (g name)))))
  (List map name (list "a.xml" "i.svg" "s.css" "c.yaml" "c.yml" "Cargo.toml" "a.ini" "setup.cfg" "a.diff" "fix.patch")))
```
---
    ('xml 'xml 'css 'yaml 'yaml 'toml 'ini 'ini 'diff 'diff)

### diff: headers, hunks, and added, removed, changed and plain lines

```x
(do (import x/tool/syntax)
  ((Syntax named 'diff) spans "diff --git a/x b/x\nindex 1..2 100644\n--- a/x\n+++ b/x\n@@ -1,2 +1,2 @@ f\n-a\n+b\n c\n\\ No newline at end of file\n! d"))
```
---
    ((0 18 'class) (19 17 'class) (37 7 'class) (45 7 'class) (53 17 'keyword) (71 2 'error) (74 2 'string) (80 27 'comment) (108 3 'operator))

### YAML: keys, anchors, aliases, tags, block indicators, constants and numbers

```x
(do (import x/tool/syntax)
  ((Syntax named 'yaml) spans "%YAML 1.2\n---\nk: &a !t 'v'\nl: *a\nb: |-\n  text\nf: [yes, ~, -1.5, 2026-11-18]\nu: http://x.y # c\n"))
```
---
    ((0 5 'keyword) (6 3 'number) (10 3 'punct) (14 1 'name) (15 1 'punct) (17 2 'private) (20 2 'class) (23 3 'string) (27 1 'name) (28 1 'punct) (30 2 'private) (33 1 'name) (34 1 'punct) (36 2 'punct) (46 1 'name) (47 1 'punct) (49 1 'punct) (50 3 'constant) (53 1 'punct) (55 1 'constant) (56 1 'punct) (58 4 'number) (62 1 'punct) (64 10 'number) (74 1 'punct) (76 1 'name) (77 1 'punct) (90 3 'comment))

### TOML and INI: headers, keys, strings, arrays and comments

```x
(do (import x/tool/syntax)
  (list ((Syntax named 'toml) spans "[[a.b]]\nk = \"\"\"x\ny\"\"\"\nn = [\n  [1, 2],\n  'z',\n]\nd = 1979-05-27T07:32:00Z\n")
        ((Syntax named 'ini) spans "; c\n[s]\nk=v ; d\n")))
```
---
    (((0 7 'keyword) (8 1 'name) (10 1 'punct) (12 9 'string) (22 1 'name) (24 1 'punct) (26 1 'punct) (30 1 'punct) (31 1 'number) (32 1 'punct) (34 1 'number) (35 1 'punct) (36 1 'punct) (40 3 'string) (43 1 'punct) (45 1 'punct) (47 1 'name) (49 1 'punct) (51 20 'number)) ((0 3 'comment) (4 3 'keyword) (8 1 'name) (9 1 'punct) (12 3 'comment)))

### CSS: at-rules, selectors, properties, numbers, colours, !important

```x
(do (import x/tool/syntax)
  ((Syntax named 'css) spans "@media (max-width: 10px) {\n  #id > p::before, .a { margin: -.5em 0 !important; color: #a1b2c3 }\n}\n/* c */"))
```
---
    ((0 6 'keyword) (7 1 'punct) (8 9 'name) (17 1 'punct) (19 4 'number) (23 1 'punct) (25 1 'punct) (29 3 'name) (33 1 'punct) (36 8 'constant) (44 1 'punct) (46 2 'class) (49 1 'punct) (51 6 'name) (57 1 'punct) (59 5 'number) (65 1 'number) (67 10 'keyword) (77 1 'punct) (79 5 'name) (84 1 'punct) (86 7 'number) (94 1 'punct) (96 1 'punct) (98 7 'comment))

### XML: every < opens a tag, and names hold namespaces

```x
(do (import x/tool/syntax)
  ((Syntax named 'xml) spans "<?xml version=\"1.0\"?>\n<r:s xmlns:r=\"u\"><script>a<b/></script><_x/></r:s>"))
```
---
    ((0 21 'keyword) (22 1 'punct) (23 3 'keyword) (27 7 'name) (34 1 'punct) (35 3 'string) (38 1 'punct) (39 1 'punct) (40 6 'keyword) (46 1 'punct) (48 1 'punct) (49 1 'keyword) (50 1 'punct) (51 1 'punct) (52 2 'punct) (54 6 'keyword) (60 1 'punct) (61 1 'punct) (62 2 'keyword) (64 1 'punct) (65 1 'punct) (66 2 'punct) (68 3 'keyword) (71 1 'punct))

### the third set is found by file name, by whole name and by #! line

```x
(do (import x/tool/syntax)
  (def name (fn (_ f) (let ((g (Syntax for-file f))) (if (null? g) () (g name)))))
  (list (List map name (list "lib.rs" "a.js" "m.mjs" "c.cjs" "t.csv" "t.tsv" "ls.1" "x.8" "a.man" "Containerfile" "Dockerfile" "w.dockerfile" "x/Containerfile"))
        ((Syntax for-file "build" "#!/usr/bin/env node\n") name)))
```
---
    (('rust 'javascript 'javascript 'javascript 'csv 'tsv 'roff 'roff 'roff 'containerfile 'containerfile 'containerfile 'containerfile) 'javascript)

### Rust: attributes, lifetimes, characters, macros, raw strings and suffixed numbers

```x
(do (import x/tool/syntax)
  ((Syntax named 'rust) spans "#[derive(Debug)]\nfn f<'a>(s: &'a str) -> Option<u8> {\n    // c\n    let c = b'x'; let d = '\\n';\n    println!(\"{}\", r#\"a\"b\"#);\n    0x1F_u8 + 1_000 /* k */\n}"))
```
---
    ((0 16 'keyword) (17 2 'keyword) (21 1 'operator) (22 2 'class) (24 1 'operator) (25 1 'punct) (27 1 'operator) (29 1 'operator) (30 2 'class) (33 3 'class) (36 1 'punct) (38 2 'operator) (41 6 'class) (47 1 'operator) (48 2 'class) (50 1 'operator) (52 1 'punct) (58 4 'comment) (67 3 'keyword) (73 1 'operator) (76 3 'char) (79 1 'punct) (81 3 'keyword) (87 1 'operator) (89 4 'char) (93 1 'punct) (99 7 'name) (106 1 'operator) (107 1 'punct) (108 4 'string) (112 1 'punct) (114 8 'string) (122 1 'punct) (123 1 'punct) (129 7 'number) (137 1 'operator) (139 5 'number) (145 7 'comment) (153 1 'punct))

### JavaScript: a / divides after an operand and opens a regular expression elsewhere

```x
(do (import x/tool/syntax)
  ((Syntax named 'javascript) spans "#!/usr/bin/env node\nconst r = /a\\/[/]b/g, x = this.n / 2;\nlet s = `t ${f(`u`)} v` // c\nclass A { #p = null; }\nx = a/b;"))
```
---
    ((0 19 'comment) (20 5 'keyword) (28 1 'operator) (30 9 'string) (40 1 'punct) (44 1 'operator) (46 4 'keyword) (53 1 'operator) (55 1 'number) (56 1 'punct) (58 3 'keyword) (64 1 'operator) (66 15 'string) (82 4 'comment) (87 5 'keyword) (93 1 'class) (95 1 'punct) (97 2 'private) (100 1 'operator) (102 4 'constant) (106 1 'punct) (108 1 'punct) (112 1 'operator) (115 1 'operator) (117 1 'punct))

### CSV and TSV: a colour a column, quoted fields holding separators and quotes

```x
(do (import x/tool/syntax)
  (list ((Syntax named 'csv) spans "id,name,,n\r\n1,\"a, \"\"b\"\"\",x,2\n")
        ((Syntax named 'tsv) spans "a\tb\tc\n")))
```
---
    (((0 2 'name) (2 1 'punct) (3 4 'string) (7 1 'punct) (8 1 'punct) (9 1 'keyword) (12 1 'name) (13 1 'punct) (14 10 'string) (24 1 'punct) (25 1 'number) (26 1 'punct) (27 1 'keyword)) ((0 1 'name) (1 1 'punct) (2 1 'string) (3 1 'punct) (4 1 'number)))

### roff: requests, quoted arguments, escapes and comments

```x
(do (import x/tool/syntax)
  ((Syntax named 'roff) spans ".\\\" c\n.TH X 1 \"2026\"\n\\fBx\\fR \\(em \\*[R] \\s-2y\\s0 \\w'ab' z \\\" n\n. B a\n"))
```
---
    ((0 1 'keyword) (1 4 'comment) (6 3 'keyword) (14 6 'string) (21 3 'escape) (25 3 'escape) (29 4 'escape) (34 5 'escape) (40 4 'escape) (45 3 'escape) (49 6 'escape) (58 4 'comment) (63 3 'keyword))

### Containerfile: instructions in any case, FROM's AS, flags, JSON forms, variables

```x
(do (import x/tool/syntax)
  ((Syntax named 'containerfile) spans "# syntax=x\nfrom alpine:3 AS b\nCOPY --from=b [\"/a\", \"/b\"]\nRUN echo \"$HOME\" ${X} as \\\n  && true\n"))
```
---
    ((0 10 'comment) (11 4 'keyword) (25 2 'keyword) (30 4 'keyword) (35 6 'constant) (44 1 'punct) (45 4 'string) (49 1 'punct) (51 4 'string) (55 1 'punct) (57 3 'keyword) (66 7 'string) (74 4 'name) (82 1 'operator))

### CSS: a word after a blank keeps its first byte

```x
(do (import x/tool/syntax)
  ((Syntax named 'css) spans "p { font-family: f }"))
```
---
    ((2 1 'punct) (4 11 'name) (15 1 'punct) (19 1 'punct))
