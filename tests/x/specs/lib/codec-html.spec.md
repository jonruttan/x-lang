# HTML codec: a page as Markdown's blocks, and character references
# @weight 1

(Html parse) answers a page as the blocks (Markdown parse) answers, so
x/tui/page lays it out unchanged; (Html title) its <title>.  (Entity
decode) and (Entity at) read character references for both codecs.

## blocks

### headings and paragraphs; head, script, style and comments dropped; white space collapsed

```x
(do (import x/codec/html)
  (Html parse "<!DOCTYPE html>\n<html><head><title>T</title><style>p{}</style><script>'<p>'</script></head>\n<body>\n <h2>Two</h2>\n <p>one\n  two <!-- c --> three</p>\n<div>stray <span>text</span></div>\n</body></html>"))
```
---
    (('heading 2 ("Two")) ('paragraph ("one two three")) ('paragraph ("stray text")))

### lists nest; an ol keeps its start; an li closes the one before it; what is not an li joins the item before it

```x
(do (import x/codec/html)
  (Html parse "<ul><li>x<ul><li>y</ul><li>z</ul><ol start=\"3\"><li>c<li>d<p>e</ol>"))
```
---
    (('list #f () #t ((('paragraph ("x")) ('list #f () #t ((('paragraph ("y")))))) (('paragraph ("z"))))) ('list #t 3 #t ((('paragraph ("c"))) (('paragraph ("d")) ('paragraph ("e"))))))

### a table is a paragraph a row, cells parted, a th bold, its caption first; a dl's terms bold

```x
(do (import x/codec/html)
  (Html parse "<table><caption>Cap</caption><thead><tr><th>H1<th>H2</thead><tr><td>a<td><b>b</b><tr><td></td><td>only</table><dl><dt>Term<dd>Def</dl>"))
```
---
    (('paragraph ("Cap")) ('paragraph (('strong ("H1")) " | " ('strong ("H2")))) ('paragraph ("a | " ('strong ("b")))) ('paragraph ("only")) ('paragraph (('strong ("Term")))) ('paragraph ("Def")))

### pre keeps its text, its language from a class; hr; block quotes; a heading closes an open one

```x
(do (import x/codec/html)
  (Html parse "<pre><code class=\"language-x\">\n(a\n b)</code></pre><pre class=\"language-c\">x\r\ny</pre><hr/><blockquote><p>q1<p>q2</blockquote><h1>H<h2>sub"))
```
---
    (('code-block "x" "(a\n b)\n") ('code-block "c" "x\ny\n") ('thematic-break) ('block-quote (('paragraph ("q1")) ('paragraph ("q2")))) ('heading 1 ("H")) ('heading 2 ("sub")))

### empty text, and white space alone, have no blocks

```x
(do (import x/codec/html)
  (list (Html parse "") (Html parse " \n\t ") (Html parse "<p> </p><div></div>")))
```
---
    (() () ())

## inlines

### links with titles, strong, emphasis, code, a line break, an image's alt text; an anchor with no href is its text

```x
(do (import x/codec/html)
  (Html parse "<p>see <a href=\"/u\" title=\"t\">the <b>bold <i>both</i></b> page</a>, <code> a  b </code><br>\n<img src=x.png alt=\"an image\"> and <a name=top>anchor</a> <em>e</em>.</p>"))
```
---
    (('paragraph ("see " ('link "/u" "t" ("the " ('strong ("bold " ('emph ("both")))) " page")) ", " ('code "a b") ('hardbreak) "an image and anchor " ('emph ("e")) ".")))

### entities decode in text and attributes; a < that starts no tag is text; a trailing br and spaces come off

```x
(do (import x/codec/html)
  (Html parse "<p>&lt;a&gt; &amp; &copy; &#169; &#xA9; &hearts; &nope;</p><p>5 < 6 <a href=\"?a=1&amp;b=2\">q</a> <br> </p>"))
```
---
    (('paragraph ("<a> & © © © ♥ &nope;")) ('paragraph ("5 < 6 " ('link "?a=1&b=2" () ("q")))))

## tolerance

### names in any case, attributes in either quote or none, p and td unclosed, a stray close tag, a block inside a link

```x
(do (import x/codec/html)
  (Html parse "<P CLASS=foo>one<P>two</b><TABLE><TR><TD>a<TD>b</TABLE><div><A HREF='/x'><div>in a link</div></A></div>"))
```
---
    (('paragraph ("one")) ('paragraph ("two")) ('paragraph ("a | b")) ('paragraph (('link "/x" () ("in a link")))))

### select, textarea and iframe are dropped; a page with no html, head or body

```x
(do (import x/codec/html)
  (Html parse "<select><option>a<option>b</select><textarea>t</textarea><iframe>f</iframe>just <b>text</b>"))
```
---
    (('paragraph ("just " ('strong ("text")))))

## title

### the <title>'s text, collapsed; nil with none or an empty one; a title in a script is not one

```x
(do (import x/codec/html)
  (list (Html title "<html><head><script>'<title>no</title>'</script><title> A &amp;\n B </title></head>")
        (Html title "<p>no title") (Html title "<title> </title>")))
```
---
    ("A & B" () ())

## layout

### a page laid out by x/tui/page, as Markdown is

```x
(do (import x/codec/html) (import x/tui/page)
  (def p (Page markdown (Html parse "<h1>Hi</h1><p>see <a href=/u>this link</a> here</p><ul><li>one<li>two</ul>") 20))
  (list (List map (fn (_ i) (Page line-text p i)) (List range 0 (Page count p))) (Page links p)))
```
---
    (("Hi" "" "see this link here" "" "• one" "• two") (("/u" () ((2 4 9)))))

## Entity

### named, decimal and hex references; what is not one stays

```x
(do (import x/codec/entity)
  (list (Entity decode "&lt;&eacute;&mdash;&#65;&#x42;&#X43; &amp &nope; & &#;")
        (Entity at "x&quot;" 1) (Entity at "x&quot;" 0) (Entity at "&#0;&#55296;&#1114112;" 0)))
```
---
    ("<é—ABC &amp &nope; & &#;" ("\"" . 7) () ("�" . 4))
