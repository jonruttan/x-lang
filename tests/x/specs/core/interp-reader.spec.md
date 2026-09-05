# $"..." string interpolation reader
# @weight 1

The `$"..."` reader macro (lib/x/reader/lit-reader.x) expands an interpolated
string into a `(Str8 str <chunk> <hole> ...)` call. A `{expr}` hole is parsed
and spliced in as a plain sub-expression; `{{` / `}}` (and a lone `}`) are
literal braces. Parsing happens at READ time, so each hole evaluates in place,
in the env where the literal sits.

## $"..." string interpolation

### interpolates a bare-symbol hole

```x
(let ((x 9)) $"a{x}")
```
---
    "a9"

### interpolates a parenthesized-expression hole

```x
$"sum {(+ 3 4)}"
```
---
    "sum 7"

### interpolates multiple holes with surrounding text

```x
$"#<Grid {(+ 3 4)}x{(+ 1 1)}>"
```
---
    "#<Grid 7x2>"

### interpolates adjacent holes

```x
(let ((x 7)) $"{x}{x}{x}")
```
---
    "777"

### passes through a string with no holes

```x
$"no holes here"
```
---
    "no holes here"

### handles an empty string

```x
$""
```
---
    ""

## brace escaping

### {{ and }} are literal braces, not a hole

```x
$"{{literal}} braces"
```
---
    "{literal} braces"

### a lone } is a literal brace

```x
$"a lone } brace"
```
---
    "a lone } brace"

### {{}} yields a pair of literal braces

```x
$"{{}}"
```
---
    "{}"

### \ escapes a brace, so no hole opens

The backslash itself survives, exactly as it does in an ordinary string: the
chunk goes back through the C string reader, so there is one escape table and
`{{` stays the way to write a bare brace.

```x
$"a\{b\}c"
```
---
    "a\\{b\\}c"

## a hole holds arbitrary code

The analyser scans a hole in expression context, so the characters that would
otherwise end the token -- a quote, a brace, another `$"` -- are read as the
code they belong to.

### a string literal inside a hole

```x
$"hi {(Str8 upcase "ab")}!"
```
---
    "hi AB!"

### braces inside a hole's string are not hole syntax

```x
$"[{(Str8 append "a}b{c" "|")}]"
```
---
    "[a}b{c|]"

### a #\ character literal in a hole cannot end the scan

```x
$"{(List length (list #\" #\} #\a))}"
```
---
    "3"

### a nested $"..." inside a hole

```x
(let ((c 7)) $"a{$"<{c}>"}z")
```
---
    "a<7>z"

### three literals deep

```x
$"a{$"b{$"c{(+ 1 1)}"}"}z"
```
---
    "abc2z"

### a hole holding a string and a nested literal at once

```x
$"Hello, {(Str8 join " " (List map (fn (_ c) $"{c}") (list 1 2 3)))}!"
```
---
    "Hello, 1 2 3!"

### $ not followed by a quote stays an ordinary symbol

```x
(lit $foo)
```
---
    '$foo

## degenerate holes (#159)

### an empty hole splices nothing

A hole with no expression reads no form, so it contributes nothing -- the same
way `$""` is `""`. This used to segfault the READER (`first` on the empty token
list is unchecked), before evaluation began.

```x
$"a{}b"
```
---
    "ab"

### a hole of only whitespace is equally empty

```x
$"a{   }b"
```
---
    "ab"

### a literal that is nothing but an empty hole

```x
$"{}"
```
---
    ""

### an unterminated literal falls back to a symbol rather than crashing

Nothing scores the token, so the symbol reader -- the analyse list's tail --
claims the text, exactly as it does for any run of characters no literal wants.

```x
(symbol? (first (Tok read-str (%base) "$\"a{x ")))
```
---
    #t

## holes evaluate in the enclosing scope

These pin the read-time-parsing fix: a hole's variable must resolve in the env
where the literal sits, even when a *second* interpolation follows it.

### as direct arguments to Str8 str

```x
((fn (_ x) (Str8 str $"a{x}" $"b{x}")) 9)
```
---
    "a9b9"

### inside separate let frames

```x
((fn (_ x) (Str8 str (let ((q 1)) $"a{x}") (let ((q 1)) $"b{x}"))) 9)
```
---
    "a9b9"

### a second interpolation in if-tail (TCO) position

```x
((fn (_ x) (Str8 str (if #t $"a{x}" "") (if #t $"b{x}" ""))) 9)
```
---
    "a9b9"

### an expr hole then a symbol hole across if-tails

```x
((fn (_ x) (Str8 str (if #t $"a{(+ 1 1)}" "") (if #t $"b{x}" ""))) 9)
```
---
    "a2b9"

### a single interpolation in a fn body

```x
((fn (_ x) $"a{x}") 9)
```
---
    "a9"

### two holes in one string reference the same binding

```x
((fn (_ x) $"a{x}b{x}c") 9)
```
---
    "a9b9c"

## read-time expansion

### $"..." expands to a direct (Str8 str ...) call at read time

```x
'$"a{x}"
```
---
    ('Str8 'str "a" 'x)

## the tail-only list ( . x)

### a list that is only a tail IS the tail (reads as the bare form)

```x
'( . b)
```
---
    'b

### the bare-variadic parameter form binds everything

```x
(rest ((fn ( . rest) rest) 1 2 3))
```
---
    (1 2 3)

## integer bases (leading zero is decimal)

### 019 is nineteen, not octal-then-stop

```x
(list 019 010 0x13)
```
---
    (19 10 19)
