# Document: the tree a reader answers and a writer takes
# @weight 1

(Document check) answers the first node of a document that is not one of
the nodes (Document blocks) and (Document inlines) hold, as (NAME PART
NODE), or nil.  What the Markdown and HTML readers answer is sound.

## the readers

### every block and inline (Markdown parse) answers is sound

```x
(do (import x/codec/document) (import x/codec/markdown)
  (list (Document check (Markdown parse "# H *e* **s** `c`\n\npara [l](/u \"t\") ![i](/p) <b>raw</b>  \nbreak\nsoft\n\n> quote\n\n- a\n- b\n\n3. c\n\n4. d\n\n```x\ncode\n```\n\n***\n\n<div>\nblock\n</div>\n"))))
```
---
    (())

### every block and inline (Html parse) answers is sound, a form's fields with them

```x
(do (import x/codec/document) (import x/codec/html)
  (list (Document check (Html parse "<h1>H</h1><p>see <a href=/u title=t>a <b>b</b> <i>i</i></a> <code>c</code><br>x</p><pre class=language-x>code</pre><blockquote><p>q</blockquote><ul><li>a<li>b</ul><ol start=3><li>c</ol><hr><table><tr><th>k<td>v</table><dl><dt>t<dd>d</dl><form action=/s method=post><input name=q> <input type=checkbox name=c checked> <select name=s><option>One<option value=2 selected>Two</select> <textarea name=t>x</textarea> <button name=b>Go</button></form><input type=password name=p>"))))
```
---
    (())

## faults

### a node neither table holds, under block or inline; a string is text only among inlines

```x
(do (import x/codec/document)
  (list (Document check (list (list (lit table) ())))
        (Document check (list (list (lit paragraph) (list (list (lit bold) (list "x"))))))
        (Document check (list "text"))
        (Document check (list (list (lit emph) (list "x"))))
        (Document check (list ()))))
```
---
    (('block 'name ('table ())) ('inline 'name ('bold ("x"))) ('block 'name "text") ('block 'name ('emph ("x"))) ('block 'name ()))

### too few parts or too many

```x
(do (import x/codec/document)
  (list (Document check (list (list (lit code-block) "x")))
        (Document check (list (list (lit thematic-break) "x")))
        (Document check (list (list (lit paragraph) (list (list (lit softbreak) "x")))))))
```
---
    (('code-block 'parts ('code-block "x")) ('thematic-break 'parts ('thematic-break "x")) ('softbreak 'parts ('softbreak "x")))

### a part that does not hold its kind: a level past 6, a start no integer, a flag no boolean, a title no string, text no string

```x
(do (import x/codec/document)
  (list (Document check (list (list (lit heading) 7 ())))
        (Document check (list (list (lit list) #t "1" #t ())))
        (Document check (list (list (lit list) () () #t ())))
        (Document check (list (list (lit paragraph) (list (list (lit link) "/u" 1 ())))))
        (Document check (list (list (lit paragraph) (list (list (lit code) (list "x"))))))))
```
---
    (('heading 'level ('heading 7 ())) ('list 'start ('list #t "1" #t ())) ('list 'flag ('list () () #t ())) ('link 'title ('link "/u" 1 ())) ('code 'text ('code ("x"))))

### blocks, inlines and items that are no list; an item that is no list of blocks

```x
(do (import x/codec/document)
  (list (Document check "text")
        (Document check (list (list (lit paragraph) "x")))
        (Document check (list (list (lit block-quote) (lit quote))))
        (Document check (list (list (lit list) #f () #t (list "a"))))
        (Document check (list (list (lit list) #f () #t (list (list "a")))))))
```
---
    (('document 'blocks "text") ('paragraph 'inlines ('paragraph "x")) ('block-quote 'blocks ('block-quote 'quote)) ('list 'items "a") ('block 'name "a"))

### the fault is the first one, and the innermost node's

```x
(do (import x/codec/document)
  (Document check
    (list (list (lit paragraph) (list "fine"))
          (list (lit block-quote)
                (list (list (lit list) #f () #t
                            (list (list (list (lit paragraph) (list (list (lit strong) "x"))))))))
          (list (lit heading) 9 ()))))
```
---
    ('strong 'inlines ('strong "x"))

## the tables

### a node's name, then the kind of each part

```x
(do (import x/codec/document)
  (list (Document blocks) (Document inlines)))
```
---
    ((('heading 'level 'inlines) ('paragraph 'inlines) ('code-block 'text 'text) ('block-quote 'blocks) ('list 'flag 'start 'flag 'items) ('thematic-break) ('html-block 'text)) (('emph 'inlines) ('strong 'inlines) ('code 'text) ('softbreak) ('hardbreak) ('link 'text 'title 'inlines) ('image 'text 'title 'inlines) ('html-inline 'text) ('field 'symbol 'title 'title 'flag 'options 'form)))

## formats

### the formats, and a file's by its name's ending or a PDF's signature

```x
(do (import x/codec/document)
  (list (Document formats)
        (List map (fn (_ n) (Document format n)) (list "a.md" "b/C.MARKDOWN" "d.htm" "e.pdf" "f.txt" "g" "h.md.bak"))
        (Document format "g" "%PDF-1.7\n") (Document format "a.md" "# Hi")))
```
---
    ((("markdown" (".md" ".markdown" ".mdown")) ("html" (".html" ".htm")) ("pdf" (".pdf")) ("text" (".txt" ".text"))) ("markdown" "markdown" "html" "pdf" "text" () ()) "pdf" "markdown")

### a document's title is its first heading's text

```x
(do (import x/codec/document)
  (list (Document title (list (list (lit paragraph) (list "p"))
                              (list (lit heading) 2 (list "A " (list (lit strong) (list "b")) (list (lit softbreak)) (list (lit code) "c") " " (list (lit link) "/u" () (list "d"))))))
        (Document title ())))
```
---
    ("A b c d" ())

### each format read: its own title or nil, then its blocks

```x
(do (import x/codec/document)
  (list (Document read "markdown" "# Hi\n\nthere")
        (Document read "html" "<title>T &amp; U</title><h1>Hi</h1><p>there")
        (Document read "text" "plain\n  kept\n")
        (Document read "text" "")
        (guard (e (e msg)) (Document read "rtf" "x"))))
```
---
    ((() ('heading 1 ("Hi")) ('paragraph ("there"))) ("T & U" ('heading 1 ("Hi")) ('paragraph ("there"))) (() ('code-block "" "plain\n  kept\n")) (()) "Document: no such format")

### each format written, a string for all but a PDF; the title nil is the first heading

```x
(do (import x/codec/document)
  (def %dcs-doc (list (list (lit heading) 1 (list "Hi & <there>")) (list (lit paragraph) (list "one two three four " (list (lit emph) (list "five"))))))
  (list (Document write "markdown" %dcs-doc)
        (Document write "html" %dcs-doc)
        (first (Document write "html" () "Given"))
        (Document write "text" %dcs-doc () 12)
        (first (Document write "text" %dcs-doc))
        (guard (e (e msg)) (Document write "rtf" %dcs-doc))))
```
---
    (("# Hi & \\<there>\n\none two three four *five*\n" 0 43) ("<!DOCTYPE html>\n<html>\n<head>\n<meta charset=\"utf-8\">\n<title>Hi &amp; &lt;there&gt;</title>\n</head>\n<body>\n<h1>Hi &amp; &lt;there&gt;</h1>\n<p>one two three four <em>five</em></p>\n</body>\n</html>\n" 0 194) "<!DOCTYPE html>\n<html>\n<head>\n<meta charset=\"utf-8\">\n<title>Given</title>\n</head>\n<body>\n</body>\n</html>\n" ("Hi & <there>\n\none two\nthree four\nfive\n" 0 38) "Hi & <there>\n\none two three four five\n" "Document: no such format")

### a PDF written is read back as the document, title and all; every format's output is sound when read

```x
(do (import x/codec/document)
  (def %dcs-in (list (list (lit heading) 1 (list "Head")) (list (lit paragraph) (list "A " (list (lit strong) (list "bold")) " word."))))
  (def %dcs-pdf (Document write "pdf" %dcs-in "The title"))
  (list (Document format "out" (first %dcs-pdf))
        (Document read "pdf" (first %dcs-pdf) (List ref 2 %dcs-pdf))
        (List map
          (fn (_ f)
            ((fn (_ r) (null? (Document check (rest (Document read f (first r) (List ref 2 r))))))
             (Document write f %dcs-in)))
          (List map first (Document formats)))))
```
---
    ("pdf" ("The title" ('heading 1 ("Head")) ('paragraph ("A " ('strong ("bold")) " word."))) (#t #t #t #t))
