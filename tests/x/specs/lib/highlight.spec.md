# Highlight: transcript classification
# @weight 1

Characterizes how `x/tool/highlight` classifies the LINES of a REPL
transcript, which is the part a byte-level check cannot see. The
`highlight-roundtrip` gate proves the markup strips back to the original
bytes — and it passed while a multi-line expression was rendering as grey
output, because the bytes were right and only the meaning was wrong.

The distinction the transcript mode has to make: a line arriving while the
expression above it is still open is CODE (the session is still reading),
and a line arriving at paren depth zero is the value it returned.

## Highlight transcript

### a continuation line is code, not the value

The body of a multi-line `(match ...)` renders with code classes — `p`, `kc`,
`m` — and only the trailing `1` is `go`. Rendering the body as `go` is the
regression this guards (docs/tutorial.md's Conditionals section, published
that way).

```x
(do (import x/tool/highlight)
    (Highlight transcript "> (match\n    (#t 1))\n1" (list "match")))
```
---
```output
<div class="highlight"><pre class="highlight"><code><span class="gp">&gt; </span><span class="p">(</span><span class="k">match</span>
    <span class="p">(</span><span class="kc">#t</span> <span class="m">1</span><span class="p">)</span><span class="p">)</span>
<span class="go">1</span></code></pre></div>
```

### a closed expression's next line is the value

One line, balanced, so what follows is output rather than more code.

```x
(do (import x/tool/highlight)
    (Highlight transcript "> (+ 1 2)\n3" (list)))
```
---
```output
<div class="highlight"><pre class="highlight"><code><span class="gp">&gt; </span><span class="p">(</span><span class="n">+</span> <span class="m">1</span> <span class="m">2</span><span class="p">)</span>
<span class="go">3</span></code></pre></div>
```

### a paren inside a string does not open an expression

The depth scan counts only the parens the scanner treats as punctuation, so
a string's bracket cannot swallow the result line behind it.

```x
(do (import x/tool/highlight)
    (Highlight transcript "> (id \"(\")\n\"(\"" (list)))
```
---
```output
<div class="highlight"><pre class="highlight"><code><span class="gp">&gt; </span><span class="p">(</span><span class="n">id</span> <span class="s">"("</span><span class="p">)</span>
<span class="go">"("</span></code></pre></div>
```
