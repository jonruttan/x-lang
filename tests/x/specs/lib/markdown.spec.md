# Markdown codec: CommonMark parse, and HTML out
# @weight 1

(Markdown parse) answers a document as a list of blocks led by their
CommonMark names, inlines as strings and tagged lists; (Markdown html)
renders them as the CommonMark reference renderer does.  The HTML cases
were checked against pandoc's CommonMark reader, where it agrees with the
reference (pandoc leaves destinations unencoded and orders image attributes
its own way).

## parse: blocks

### ATX and setext headings, paragraphs, a thematic break

```x
(do (import x/codec/markdown)
  (Markdown parse "# One #\nSetext\n===\npara\none\n\n***\n## "))
```
---
    (('heading 1 ("One")) ('heading 1 ("Setext")) ('paragraph ("para" ('softbreak) "one")) ('thematic-break) ('heading 2 ()))

### fenced code keeps its info; indented code its text; a fence's indent comes off

```x
(do (import x/codec/markdown)
  (Markdown parse "``` x lang\n(a)\n```\n\n    b\n      c\n\n  ~~~\n  d\n e\n  ~~~"))
```
---
    (('code-block "x lang" "(a)\n") ('code-block "" "b\n  c\n") ('code-block "" "d\ne\n"))

### block quotes nest; a lazy line goes on the paragraph

```x
(do (import x/codec/markdown)
  (Markdown parse "> a\nb\n> > c"))
```
---
    (('block-quote (('paragraph ("a" ('softbreak) "b")) ('block-quote (('paragraph ("c")))))))

### lists: bullets tight, ordered with a start, loose when a blank line parts items

```x
(do (import x/codec/markdown)
  (Markdown parse "- a\n- b\n\n3. c\n\n4. d\n\n+ e\n  - f"))
```
---
    (('list #f () #t ((('paragraph ("a"))) (('paragraph ("b"))))) ('list #t 3 #f ((('paragraph ("c"))) (('paragraph ("d"))))) ('list #f () #t ((('paragraph ("e")) ('list #f () #t ((('paragraph ("f")))))))))

### an ordered list interrupts a paragraph only from 1

```x
(do (import x/codec/markdown)
  (Markdown parse "a\n2. b\n\nc\n1. d"))
```
---
    (('paragraph ("a" ('softbreak) "2. b")) ('paragraph ("c")) ('list #t 1 #t ((('paragraph ("d"))))))

### HTML blocks: a block tag runs to a blank line, a comment to its end

```x
(do (import x/codec/markdown)
  (Markdown parse "<div>\n*a*\n</div>\n\n<!-- b\n\nc -->\nd"))
```
---
    (('html-block "<div>\n*a*\n</div>") ('html-block "<!-- b\n\nc -->") ('paragraph ("d")))

### empty text, and blank lines only, have no blocks

```x
(do (import x/codec/markdown)
  (list (Markdown parse "") (Markdown parse "\n  \n\t\n")))
```
---
    (() ())

## parse: inlines

### emphasis and strong, nested, by the delimiter rules

```x
(do (import x/codec/markdown)
  (Markdown parse "*a* __b__ ***c*** *d **e** f* snake_case_name"))
```
---
    (('paragraph (('emph ("a")) " " ('strong ("b")) " " ('emph (('strong ("c")))) " " ('emph ("d " ('strong ("e")) " f")) " snake_case_name")))

### code spans strip one space each side; backslash escapes; entities

```x
(do (import x/codec/markdown)
  (Markdown parse "` a `` b ` \\*x\\* &amp; &#65; &#x42; &copy; &nope;"))
```
---
    (('paragraph (('code "a `` b") " *x* & A B © &nope;")))

### inline links and images, with titles; a reference link by its folded label

```x
(do (import x/codec/markdown)
  (Markdown parse "[a](/u \"t\") ![i](p.png) [B][Ref] [ref]\n\n[REF]: /r 'T'"))
```
---
    (('paragraph (('link "/u" "t" ("a")) " " ('image "p.png" () ("i")) " " ('link "/r" "T" ("B")) " " ('link "/r" "T" ("ref")))))

### a link holds no link; a bracket with no destination is text

```x
(do (import x/codec/markdown)
  (Markdown parse "[a [b](/x) c](/y) [d]"))
```
---
    (('paragraph ("[a " ('link "/x" () ("b")) " c](/y) [d]")))

### autolinks, email autolinks, raw HTML inline

```x
(do (import x/codec/markdown)
  (Markdown parse "<https://x.org/a> <me@x.org> <b class=\"c\">d</b>"))
```
---
    (('paragraph (('link "https://x.org/a" () ("https://x.org/a")) " " ('link "mailto:me@x.org" () ("me@x.org")) " " ('html-inline "<b class=\"c\">") "d" ('html-inline "</b>"))))

### hard breaks: two spaces or a backslash before the line end

```x
(do (import x/codec/markdown)
  (Markdown parse "a  \nb\\\nc\nd"))
```
---
    (('paragraph ("a" ('hardbreak) "b" ('hardbreak) "c" ('softbreak) "d")))

## html

### a document as the reference renders it

```x
(do (import x/codec/markdown)
  (Markdown html (Markdown parse "# T\n\n> q *e*\n\n- a\n- b\n\n1. c\n\n   d\n2. e\n\n```x\n<&>\n```\n\n---")))
```
---
    "<h1>T</h1>\n<blockquote>\n<p>q <em>e</em></p>\n</blockquote>\n<ul>\n<li>a</li>\n<li>b</li>\n</ul>\n<ol>\n<li>\n<p>c</p>\n<p>d</p>\n</li>\n<li>\n<p>e</p>\n</li>\n</ol>\n<pre><code class=\"language-x\">&lt;&amp;&gt;\n</code></pre>\n<hr />\n"

### destinations percent-encoded, text and attributes escaped, an ordered start kept

```x
(do (import x/codec/markdown)
  (Markdown html (Markdown parse "7. [a \"b\"](</a b> \"t&\") ![x *y*](/é 'z') <x@y.z>")))
```
---
    "<ol start=\"7\">\n<li><a href=\"/a%20b\" title=\"t&amp;\">a &quot;b&quot;</a> <img src=\"/%C3%A9\" alt=\"x y\" title=\"z\" /> <a href=\"mailto:x@y.z\">x@y.z</a></li>\n</ol>\n"

### raw HTML passes through; breaks render

```x
(do (import x/codec/markdown)
  (Markdown html (Markdown parse "<div>\nx\n</div>\n\na <i>b</i>  \nc")))
```
---
    "<div>\nx\n</div>\n<p>a <i>b</i><br />\nc</p>\n"
