# String classes (Str8 / StrUTF8 / Str)

Two string protocols, each exposing the full string suite as static methods:

- `Str8` -- 8-bit bytes. `(Str8 index s i)` is always a byte; O(1).
- `StrUTF8` -- UTF-8 code points. `(StrUTF8 index s i)` is always a code point.

The suite (append, join, contains?, split, trim, =?, <?, upcase, reverse, ...)
is written once on `Str8` through self primitives; `StrUTF8` overrides only the
primitives (`length` / `index` / `sub` / `step` / `char->bytes`) and inherits
the rest with code-point behaviour.

`Str` names the ACTIVE protocol -- code points by default (`Str = StrUTF8`), so
the bare string call `(s i)`, the `str-*` library, and `str->list` are all
code-point out of the box. `Utf8` is an alias for `StrUTF8`; method `ref` aliases
`index`. The classes are preloaded, so no import is needed.

## protocols

### Str8 index is always a byte

```x
(char->integer (Str8 index "$¢€" 1))
```
---
    194

### StrUTF8 index is always a code point

```x
(char->integer (StrUTF8 index "$¢€" 1))
```
---
    162

### Str (active) is code points by default

```x
(char->integer (Str index "$¢€" 1))
```
---
    162

### Str8 length counts bytes; StrUTF8 length counts code points

```x
(list (Str8 length "$¢€") (StrUTF8 length "$¢€"))
```
---
    (6 3)

### Str (active) length is code points by default

```x
(Str length "$¢€")
```
---
    3

### str-byte-* primitives are always byte (handler-immune)

```x
(char->integer (str-byte-ref "$¢€" 1))
```
---
    194

## Str8 (byte view)

### append concatenates

```x
(Str8 append "he" "llo" "!")
```
---
    "hello!"

### empty? on empty string

```x
(Str8 empty? "")
```
---
    #t

### make builds a repeated-char string

```x
(Str8 make 3 ("x" 0))
```
---
    "xxx"

### join with separator

```x
(Str8 join ", " (list "a" "b" "c"))
```
---
    "a, b, c"

### contains? finds a substring

```x
(Str8 contains? "ll" "hello")
```
---
    #t

### starts? checks a prefix

```x
(Str8 starts? "he" "hello")
```
---
    #t

### ends? checks a suffix

```x
(Str8 ends? "lo" "hello")
```
---
    #t

### <? lexicographic order

```x
(Str8 <? "abc" "abd")
```
---
    #t

### ci=? ignores case

```x
(Str8 ci=? "Hello" "hello")
```
---
    #t

### trim removes surrounding whitespace

```x
(Str8 trim "  hi  ")
```
---
    "hi"

### split on a separator

```x
(Str8 split "," "a,b,c")
```
---
    ("a" "b" "c")

### pad-left to a width

```x
(Str8 pad-left "hi" 5 ("." 0))
```
---
    "...hi"

### reverse by byte

```x
(Str8 reverse "abc")
```
---
    "cba"

## StrUTF8 (code-point view)

### length counts code points, not bytes

```x
(StrUTF8 length "$¢€")
```
---
    3

### ref returns the i-th code point

```x
(char->integer (StrUTF8 ref "$¢€" 1))
```
---
    162

### reverse reorders whole code points

```x
(StrUTF8 reverse "a¢€")
```
---
    "€¢a"

### make repeats a multi-byte character

```x
(StrUTF8 length (StrUTF8 make 2 #\€))
```
---
    2

### empty-separator split yields one piece per code point

```x
(length (StrUTF8 split "" "a¢€"))
```
---
    3

### append then count code points

```x
(StrUTF8 length (StrUTF8 append "a" "¢" "€"))
```
---
    3

### contains? works on multi-byte content

```x
(StrUTF8 contains? "¢" "a¢€")
```
---
    #t

### the same method differs by class: length

```x
(list (Str8 length "€") (StrUTF8 length "€"))
```
---
    (3 1)

## str-* library (active protocol)

### str-length is byte-level (the raw octet accessor)

```x
(str-length "$¢€")
```
---
    6

### str->list decodes code points (active protocol)

```x
(map char->integer (str->list "$¢€"))
```
---
    (36 162 8364)

### str-upcase keeps non-ASCII intact

```x
(str-upcase "café")
```
---
    "CAFé"

### str-split by separator

```x
(str-split "," "a,b,c")
```
---
    ("a" "b" "c")
