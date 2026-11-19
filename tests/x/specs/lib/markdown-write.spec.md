# MarkdownWrite: a document as Markdown text
# @weight 1

(MarkdownWrite text) writes a document tree as CommonMark.  The cases
give the text written and read it back with (Markdown parse).

## blocks

### a heading, a paragraph, a rule, a code block with its info, raw HTML

```x
(do (import x/codec/markdown-write)
  (MarkdownWrite text
    (list (list (lit heading) 2 (list "Head " (list (lit code) "x")))
          (list (lit paragraph) (list "one" (list (lit softbreak)) "two" (list (lit hardbreak)) "three"))
          (list (lit thematic-break))
          (list (lit code-block) "sh" "ls -l\n  x\n")
          (list (lit html-block) "<div>\nraw\n</div>\n"))))
```
---
    "## Head `x`\n\none\ntwo\\\nthree\n\n---\n\n```sh\nls -l\n  x\n```\n\n<div>\nraw\n</div>\n"

### a quote leads each line, a blank one bare; a list's items are marked and what follows a marker is indented

```x
(do (import x/codec/markdown-write)
  (MarkdownWrite text
    (list (list (lit block-quote) (list (list (lit paragraph) (list "a")) (list (lit paragraph) (list "b"))))
          (list (lit list) #f () #t (list (list (list (lit paragraph) (list "one")) (list (lit list) #f () #t (list (list (list (lit paragraph) (list "in"))))))
                                           (list (list (lit paragraph) (list "two")))))
          (list (lit list) #t 9 #f (list (list (list (lit paragraph) (list "nine")) (list (lit paragraph) (list "more")))
                                          (list (list (lit paragraph) (list "ten"))))))))
```
---
    "> a\n>\n> b\n\n- one\n  - in\n- two\n\n9. nine\n\n   more\n\n10. ten\n"

### a code block holding a fence is fenced longer; one with no line end is given one

```x
(do (import x/codec/markdown-write)
  (MarkdownWrite text (list (list (lit code-block) "" "```\nin\n```") (list (lit code-block) "" ""))))
```
---
    "````\n```\nin\n```\n````\n\n```\n```\n"

## inlines

### emphasis, strong, code holding backticks, a link and an image with titles, a destination with a space

```x
(do (import x/codec/markdown-write)
  (MarkdownWrite text
    (list (list (lit paragraph)
            (list (list (lit emph) (list "a")) " " (list (lit strong) (list "b " (list (lit emph) (list "c")))) " "
                  (list (lit code) "x `y` z") " " (list (lit code) "`q") " "
                  (list (lit link) "/u" "t \"q\"" (list "l")) " " (list (lit image) "i.png" () (list "alt")) " "
                  (list (lit link) "a b" () (list "s")) (list (lit html-inline) "<br>")
                  (list (lit field) (lit text) "q" "typed" #f () ()))))))
```
---
    "*a* **b *c*** ``x `y` z`` `` `q `` [l](/u \"t \\\"q\\\"\") ![alt](i.png) [s](<a b>)<br>typed\n"

### a mark's spaces go outside it

```x
(do (import x/codec/markdown-write)
  (MarkdownWrite text (list (list (lit paragraph) (list "a" (list (lit strong) (list " b ")) "c" (list (lit emph) (list " ")))))))
```
---
    "a **b** c \n"

## escapes

### markup characters in text, and an ampersand only where it would begin a character reference

```x
(do (import x/codec/markdown-write)
  (MarkdownWrite text (list (list (lit paragraph) (list "a*b_c`d[e]f<g\\h Q&A &amp; &#65; &x")))))
```
---
    "a\\*b\\_c\\`d\\[e\\]f\\<g\\\\h Q&A \\&amp; \\&#65; &x\n"

### what would begin a block at a line's start

```x
(do (import x/codec/markdown-write)
  (MarkdownWrite text
    (List map (fn (_ s) (list (lit paragraph) (list s)))
      (list "# no" "> no" "- no" "+ no" "-" "1. no" "12) no" "1.5 yes" "---" "===" "~~~" "    lead" "-x yes" "a\n=="))))
```
---
    "\\# no\n\n\\> no\n\n\\- no\n\n\\+ no\n\n\\-\n\n1\\. no\n\n12\\) no\n\n1.5 yes\n\n\\---\n\n\\===\n\n\\~~~\n\nlead\n\n-x yes\n\na\n\\==\n"

## reading back

### what the writer writes, the reader reads as the tree it was given

```x
(do (import x/codec/markdown-write) (import x/codec/markdown) (import x/codec/document)
  (def %mws-src "# T *e* `c`\n\npara **s** [l](/u \"t\") ![i](p.png) 2 \\* 3 \\# &amp;amp; a\\\nb\nc\n\n> q1\n>\n> - i\n> - j\n\n1. one\n\n   two\n2. three\n\n- a\n  - b\n\n```x\n(code)\n```\n\n---\n\n<div>\nh\n</div>\n\n\\# not\n\\- not\n1\\. not\n")
  (def %mws-a (Markdown parse %mws-src))
  (def %mws-b (Markdown parse (MarkdownWrite text %mws-a)))
  (list (null? (Document check %mws-a)) (equal? %mws-a %mws-b) (MarkdownWrite text ())))
```
---
    (#t #t "")
