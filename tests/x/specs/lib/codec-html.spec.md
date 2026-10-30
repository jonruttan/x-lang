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

### iframe is dropped, parting blocks; a select and a textarea outside any form are fields in none; a page with no html, head or body

```x
(do (import x/codec/html)
  (Html parse "<select><option>a<option>b</select><textarea>t</textarea><iframe>f</iframe>just <b>text</b>"))
```
---
    (('paragraph (('field 'select () "a" #f (("a" . "a") ("b" . "b")) ()) ('field 'textarea () "t" #f () ()))) ('paragraph ("just " ('strong ("text")))))

## forms

### a form's fields are inlines, each with its form: inputs by type, a textarea, a select with its options and the one selected, boxes, buttons; reset and button inputs are nothing

```x
(do (import x/codec/html)
  (Html parse "<form action=\"/s\" method=POST><p>Q: <input name=q value=\"a b\"> <input type=hidden name=h value=1><input type=checkbox name=c checked> <input type=radio name=r value=x> <select name=s><option>One<optgroup><option value=2 selected>Two</optgroup></select> <textarea name=t>\nline</textarea> <button name=b>Go</button> <input type=submit value=Send> <input type=reset value=Clear></p></form><form><input type=search name=z><button type=button>No</button></form><input type=password name=p>"))
```
---
    (('paragraph ("Q: " ('field 'text "q" "a b" #f () (0 "/s" 'post)) " " ('field 'hidden "h" "1" #f () (0 "/s" 'post)) ('field 'checkbox "c" "on" #t () (0 "/s" 'post)) " " ('field 'radio "r" "x" #f () (0 "/s" 'post)) " " ('field 'select "s" "2" #f (("One" . "One") ("2" . "Two")) (0 "/s" 'post)) " " ('field 'textarea "t" "line" #f () (0 "/s" 'post)) " " ('field 'submit "b" "Go" #f (("Go" . "Go")) (0 "/s" 'post)) " " ('field 'submit () "Send" #f () (0 "/s" 'post)))) ('paragraph (('field 'search "z" "" #f () (1 "" 'get)))) ('paragraph (('field 'password "p" "" #f () ()))))

### a field keeps its place among the text: a label, a list item, a table cell; an unknown input type is text; a button's value and its text are both kept, a button with no text is Submit

```x
(do (import x/codec/html)
  (Html parse "<form><label>Name <input type=tel name=n></label><ul><li><input type=checkbox name=a> a</ul><table><tr><td>k<td><input name=v value=1></table><button name=b value=1>Send</button><button></button></form>"))
```
---
    (('paragraph ("Name " ('field 'text "n" "" #f () (0 "" 'get)))) ('list #f () #t ((('paragraph (('field 'checkbox "a" "on" #f () (0 "" 'get)) " a"))))) ('paragraph ("k | " ('field 'text "v" "1" #f () (0 "" 'get)))) ('paragraph (('field 'submit "b" "1" #f (("1" . "Send")) (0 "" 'get)) ('field 'submit () "Submit" #f (("Submit" . "Submit")) (0 "" 'get)))))

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
