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
