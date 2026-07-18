# String classes (Str8 / StrUTF8 / Str)

Two string protocols, each exposing the full string suite as static methods:

- `Str8` -- 8-bit bytes. `(Str8 ref i s)` is always a byte; O(1).
- `StrUTF8` -- UTF-8 code points. `(StrUTF8 ref i s)` is always a code point.

The suite (append, join, contains?, split, trim, =?, <?, upcase, reverse, ...)
is written once on `Str8` through self primitives; `StrUTF8` overrides only the
primitives (`length` / `ref` / `sub` / `step` / `char->bytes`) and inherits
the rest with code-point behaviour.

`Str` names the ACTIVE protocol -- code points by default (`Str = StrUTF8`), so
the bare string call `(s i)`, the `str-*` library, and `str->list` are all
code-point out of the box. `Utf8` is an alias for `StrUTF8`; method `index` is a
kept alias for `ref`. The classes are preloaded, so no import is needed.

## protocols

### Str8 ref is always a byte

```x
(Char ->int (Str8 ref 1 "$¢€"))
```
---
    194

### Str8 ref errors past the end instead of over-reading

```scheme
(Str8 ref 10 "ab")
```
---
    Error: Str8 ref: index out of range

### Str8 ref takes a negative index from the end

```scheme
(Str8 ref -1 "ab")
```
---
    #\b

### Str8 ref errors when a negative index reaches past the front

```scheme
(Str8 ref -3 "ab")
```
---
    Error: Str8 ref: index out of range

### StrUTF8 ref takes a negative index from the end (code points)

```scheme
(StrUTF8 ref -1 "$¢€")
```
---
    #\€

### a nil index errors loudly (a piped index-search miss)

```scheme
(Str8 ref () "ab")
```
---
    Error: Str8 ref: nil index

### StrUTF8 ref errors past the last code point

```scheme
(StrUTF8 ref 3 "$¢€")
```
---
    Error: Str ref: index out of range

### Str8 sub clamps start and length to the byte bounds

```scheme
(Str8 append (Str8 sub 3 10 "hello") (Str8 sub -2 2 "ab") (Str8 sub 9 3 "xy"))
```
---
    "loab"

### StrUTF8 ref is always a code point

```x
(Char ->int (StrUTF8 ref 1 "$¢€"))
```
---
    162

### Str (active) is code points by default

```x
(Char ->int (Str ref 1 "$¢€"))
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
(Char ->int (Str8 ref 1 "$¢€"))
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
(Str8 pad-left 5 ("." 0) "hi")
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
(Char ->int (StrUTF8 ref 1 "$¢€"))
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

## byte accessors (always byte-level)

### str-length is byte-level (the raw octet accessor)

```x
(str-length "$¢€")
```
---
    6

### str-ref is byte-level

```x
(Char ->int (str-ref "$¢€" 1))
```
---
    194

### str->list decodes code points (active protocol)

```x
(map (method-ref Char ->int) (str->list "$¢€"))
```
---
    (36 162 8364)

## active protocol via Str

### Str upcase keeps non-ASCII intact

```x
(Str upcase "café")
```
---
    "CAFé"

### Str split by separator

```x
(Str split "," "a,b,c")
```
---
    ("a" "b" "c")

## value dispatch (subject-last method form + preserved code-point call)

### method form: a string dispatches to Str, appended as the subject (last arg)

```scheme
("a,b,c" split ",")
```
---
    ("a" "b" "c")

### another combinator: contains?

```scheme
("hello" contains? "ell")
```
---
    #t

### the bare (s i) code-point call still works

```scheme
("hi" 0)
```
---
    #\h

### the bare (s i) call takes a negative index from the end

```scheme
("hi" -1)
```
---
    #\i

### the bare (s i) call errors past the end instead of over-reading

```scheme
("hi" 5)
```
---
    Error: str: index out of range

### the bare (s a n) slice clamps at the end

```scheme
("hello" 3 10)
```
---
    "lo"

### the named accessor now value-dispatches too (data-last -> subject-last)

```scheme
("abc" index 1)
```
---
    #\b

## index alias

### index is a working alias for ref

```scheme
(Char ->int (Str8 index 1 "abc"))
```
---
    98
