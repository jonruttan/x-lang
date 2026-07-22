# $"..." string interpolation reader

The `$"..."` reader macro (lib/x/reader/lit-reader.x) expands an interpolated
string into a `(Str8 str <chunk> <hole> ...)` call. A `{expr}` hole is parsed
and spliced in as a plain sub-expression; `{{` / `}}` (and a lone `}`) are
literal braces. Parsing happens at READ time, so each hole evaluates in place,
in the env where the literal sits.

## $"..." string interpolation

### interpolates a bare-symbol hole

```scheme
(let ((x 9)) $"a{x}")
```
---
    "a9"

### interpolates a parenthesized-expression hole

```scheme
$"sum {(+ 3 4)}"
```
---
    "sum 7"

### interpolates multiple holes with surrounding text

```scheme
$"#<Grid {(+ 3 4)}x{(+ 1 1)}>"
```
---
    "#<Grid 7x2>"

### interpolates adjacent holes

```scheme
(let ((x 7)) $"{x}{x}{x}")
```
---
    "777"

### passes through a string with no holes

```scheme
$"no holes here"
```
---
    "no holes here"

### handles an empty string

```scheme
$""
```
---
    ""

## brace escaping

### {{ and }} are literal braces, not a hole

```scheme
$"{{literal}} braces"
```
---
    "{literal} braces"

### a lone } is a literal brace

```scheme
$"a lone } brace"
```
---
    "a lone } brace"

### {{}} yields a pair of literal braces

```scheme
$"{{}}"
```
---
    "{}"

## holes evaluate in the enclosing scope

These pin the read-time-parsing fix: a hole's variable must resolve in the env
where the literal sits, even when a *second* interpolation follows it.

### as direct arguments to Str8 str

```scheme
((fn (_ x) (Str8 str $"a{x}" $"b{x}")) 9)
```
---
    "a9b9"

### inside separate let frames

```scheme
((fn (_ x) (Str8 str (let ((q 1)) $"a{x}") (let ((q 1)) $"b{x}"))) 9)
```
---
    "a9b9"

### a second interpolation in if-tail (TCO) position

```scheme
((fn (_ x) (Str8 str (if #t $"a{x}" "") (if #t $"b{x}" ""))) 9)
```
---
    "a9b9"

### an expr hole then a symbol hole across if-tails

```scheme
((fn (_ x) (Str8 str (if #t $"a{(+ 1 1)}" "") (if #t $"b{x}" ""))) 9)
```
---
    "a2b9"

### a single interpolation in a fn body

```scheme
((fn (_ x) $"a{x}") 9)
```
---
    "a9"

### two holes in one string reference the same binding

```scheme
((fn (_ x) $"a{x}b{x}c") 9)
```
---
    "a9b9c"

## read-time expansion

### $"..." expands to a direct (Str8 str ...) call at read time

```scheme
'$"a{x}"
```
---
    ('Str8 'str "a" 'x)

## the tail-only list ( . x)

### a list that is only a tail IS the tail (reads as the bare form)

```scheme
'( . b)
```
---
    'b

### the bare-variadic parameter form binds everything

```scheme
(rest ((fn ( . rest) rest) 1 2 3))
```
---
    (1 2 3)

## integer bases (leading zero is decimal)

### 019 is nineteen, not octal-then-stop

```scheme
(list 019 010 0x13)
```
---
    (19 10 19)
