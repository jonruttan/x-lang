# String classes (Str8 / StrUTF8 / Str)

`Str8` (8-bit bytes) and `StrUTF8` (UTF-8 code points) each expose the full
string suite as static methods: `(Str8 append a b)`, `(StrUTF8 length s)`, etc.
The suite is written once on `Str8`; `StrUTF8` overrides only the primitives
(length / index / sub / step / char->bytes) and inherits the rest with
code-point behaviour. `Str` names the ambient protocol (currently `Str8`);
`Utf8` is an alias for `StrUTF8`; method `ref` is an alias for `index`.

## protocols (Str8 / StrUTF8 / Str)

### Str8 index is always a byte

```x
(do (import x/protocol/str/utf8) (char->integer (Str8 index "$¢€" 1)))
```
---
    194

### StrUTF8 index is always a code point

```x
(do (import x/protocol/str/utf8) (char->integer (StrUTF8 index "$¢€" 1)))
```
---
    162

### Str (ambient) indexes by byte today

```x
(do (import x/protocol/str/utf8) (char->integer (Str index "$¢€" 1)))
```
---
    194

### Str8 length counts bytes, StrUTF8 length counts code points

```x
(do (import x/protocol/str/utf8) (list (Str8 length "$¢€") (StrUTF8 length "$¢€")))
```
---
    (6 3)

### the byte primitives are handler-immune (always byte)

```x
(do (char->integer (str-byte-ref "$¢€" 1)))
```
---
    194

## Str (byte view via Str8)

## Str (byte view)

### append concatenates

```x
(do (import x/protocol/str/str) (Str append "he" "llo" "!"))
```
---
    "hello!"

### empty? on empty string

```x
(do (import x/protocol/str/str) (Str empty? ""))
```
---
    #t

### make builds a repeated-char string

```x
(do (import x/protocol/str/str) (Str make 3 ("x" 0)))
```
---
    "xxx"

### length counts bytes

```x
(do (import x/protocol/str/str) (Str length "$¢€"))
```
---
    6

### join with separator

```x
(do (import x/protocol/str/str) (Str join ", " (list "a" "b" "c")))
```
---
    "a, b, c"

### contains? finds a substring

```x
(do (import x/protocol/str/str) (Str contains? "ll" "hello"))
```
---
    #t

### starts? checks a prefix

```x
(do (import x/protocol/str/str) (Str starts? "he" "hello"))
```
---
    #t

### ends? checks a suffix

```x
(do (import x/protocol/str/str) (Str ends? "lo" "hello"))
```
---
    #t

### <? lexicographic order

```x
(do (import x/protocol/str/str) (Str <? "abc" "abd"))
```
---
    #t

### ci=? ignores case

```x
(do (import x/protocol/str/str) (Str ci=? "Hello" "hello"))
```
---
    #t

### trim removes surrounding whitespace

```x
(do (import x/protocol/str/str) (Str trim "  hi  "))
```
---
    "hi"

### split on a separator

```x
(do (import x/protocol/str/str) (Str split "," "a,b,c"))
```
---
    ("a" "b" "c")

### pad-left to a width

```x
(do (import x/protocol/str/str) (Str pad-left "hi" 5 ("." 0)))
```
---
    "...hi"

### reverse by byte

```x
(do (import x/protocol/str/str) (Str reverse "abc"))
```
---
    "cba"

## Utf8 (code-point view)

### length counts code points, not bytes

```x
(do (import x/protocol/str/utf8) (Utf8 length "$¢€"))
```
---
    3

### ref returns the i-th code point

```x
(do (import x/protocol/str/utf8) (char->integer (Utf8 ref "$¢€" 1)))
```
---
    162

### reverse reorders whole code points

```x
(do (import x/protocol/str/utf8) (Utf8 reverse "a¢€"))
```
---
    "€¢a"

### make repeats a multi-byte character

```x
(do (import x/protocol/str/utf8) (Utf8 length (Utf8 make 2 #\€)))
```
---
    2

### empty-separator split yields one piece per code point

```x
(do (import x/protocol/str/utf8) (length (Utf8 split "" "a¢€")))
```
---
    3

### append then count code points

```x
(do (import x/protocol/str/utf8) (Utf8 length (Utf8 append "a" "¢" "€")))
```
---
    3

### contains? works on multi-byte content

```x
(do (import x/protocol/str/utf8) (Utf8 contains? "¢" "a¢€"))
```
---
    #t

### the same method differs by class: length

```x
(do
  (import x/protocol/str/utf8)
  (list (Str length "€") (Utf8 length "€")))
```
---
    (3 1)
