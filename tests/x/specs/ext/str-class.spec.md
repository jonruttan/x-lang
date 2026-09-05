# String classes (Str8 / StrUtf8 / Str)
# @weight 2

Two string protocols, each exposing the full string suite as static methods:

- `Str8` -- 8-bit bytes. `(Str8 ref i s)` is always a byte; O(1).
- `StrUtf8` -- UTF-8 code points. `(StrUtf8 ref i s)` is always a code point.

The suite (append, join, includes?, split, trim, =?, <?, upcase, reverse, ...)
is written once on `Str8` through self primitives; `StrUtf8` overrides only the
primitives (`length` / `ref` / `sub` / `step` / `char->bytes`) and inherits
the rest with code-point behaviour.

`Str` names the ACTIVE protocol -- code points by default (`Str = StrUtf8`), so
the bare string call `(s i)`, the `str-*` library, and `str->list` are all
code-point out of the box. `Str` is the ambient alias for `StrUtf8`; method `index` is a
kept alias for `ref`. The classes are preloaded, so no import is needed.

## protocols

### Str8 ref is always a byte

```x
(Char ->int (Str8 ref 1 "$¢€"))
```
---
    194

### Str8 ref errors past the end instead of over-reading

```x
(Str8 ref 10 "ab")
```
---
    Error: #<err:index Str8 ref: index out of range>

### Str8 ref takes a negative index from the end

```x
(Str8 ref -1 "ab")
```
---
    #\b

### Str8 ref errors when a negative index reaches past the front

```x
(Str8 ref -3 "ab")
```
---
    Error: #<err:index Str8 ref: index out of range>

### StrUtf8 ref takes a negative index from the end (code points)

```x
(StrUtf8 ref -1 "$¢€")
```
---
    #\€

### a nil index is unconvertible and errors loudly (a piped index-search miss)

```x
(Str8 ref () "ab")
```
---
    Error: Str8 ref: index not convertible to INT

### StrUtf8 ref errors past the last code point

```x
(StrUtf8 ref 3 "$¢€")
```
---
    Error: #<err:index Str ref: index out of range>

### pad-right is pad-left's twin (elements, not columns)

```x
(Str8 pad-right 5 #\0 "42")
```
---
    "42000"

### slice is the (start, end-exclusive) twin of sub

```x
(Str8 slice 1 4 "hello")
```
---
    "ell"

### StrUtf8 slice inherits through (self sub) and cuts code points

```x
(StrUtf8 slice 1 3 "$¢€!")
```
---
    "¢€"

### Str8 sub clamps start and length to the byte bounds

```x
(Str8 append (Str8 sub 3 10 "hello") (Str8 sub -2 2 "ab") (Str8 sub 9 3 "xy"))
```
---
    "loab"

### StrUtf8 ref is always a code point

```x
(Char ->int (StrUtf8 ref 1 "$¢€"))
```
---
    162

### Str (active) is code points by default

```x
(Char ->int (Str ref 1 "$¢€"))
```
---
    162

### Str8 length counts bytes; StrUtf8 length counts code points

```x
(list (Str8 length "$¢€") (StrUtf8 length "$¢€"))
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
(Str8 make 3 #\x)
```
---
    "xxx"

### make at 16K elements (crash regression)

The list-encode shape of make put one C eval frame per element on the
stack (%map is non-tail), so 16384 segfaulted where 8192 squeaked by --
found via x-awk's stdin slurp.  make now delegates to repeat's binary
doubling; this pins the depth-independence, and the ref probes pin that
the fill actually reached both ends.

```x
(def s (Str8 make 16384 #\a))
(list (Str8 length s) (Str8 ref 0 s) (Str8 ref 16383 s))
```
---
    (16384 #\a #\a)

### make refuses a NUL fill loudly (the allocation door is make-str)

Strings are C strings, so a NUL-filled string would BE "" -- and the old
list-encode path silently allocated n bytes behind that "", which x-awk's
read wrapper leaned on until repeat's 1-byte "" met a raw n-byte kernel
read (the 2026-09-01 stdin heap corruption).  A raw buffer request
belongs to the str make prim; this pins the teaching error.

```x
(Str8 make 8 (Char from-int 0))
```
---
    Error: #<err:value Str8 make: fill encodes to NUL; for a raw read buffer use the str make prim (make-str)>

### upcase at 16K elements (crash regression)

upcase/downcase/->str run %map over every element, so the non-tail %map1
put one C eval frame group per byte -- 16384 segfaulted even after make
itself was fixed.  Pins the tail-shape %map1.

```x
(def s (Str8 upcase (Str8 make 16384 #\a)))
(list (Str8 length s) (Str8 ref 0 s) (Str8 ref 16383 s))
```
---
    (16384 #\A #\A)

### join with separator

```x
(Str8 join ", " (list "a" "b" "c"))
```
---
    "a, b, c"

### includes? finds a substring

```x
(Str8 includes? "ll" "hello")
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
(Str8 pad-left 5 #\. "hi")
```
---
    "...hi"

### reverse by byte

```x
(Str8 reverse "abc")
```
---
    "cba"

## StrUtf8 (code-point view)

### length counts code points, not bytes

```x
(StrUtf8 length "$¢€")
```
---
    3

### ref returns the i-th code point

```x
(Char ->int (StrUtf8 ref 1 "$¢€"))
```
---
    162

### reverse reorders whole code points

```x
(StrUtf8 reverse "a¢€")
```
---
    "€¢a"

### make repeats a multi-byte character

```x
(StrUtf8 length (StrUtf8 make 2 #\€))
```
---
    2

### empty-separator split yields one piece per code point

Value, not length: a count of 3 is true even if the multi-byte code points
were sliced at the wrong boundaries.

```x
(StrUtf8 split "" "a¢€")
```
---
    ("a" "¢" "€")

### append then count code points

```x
(StrUtf8 length (StrUtf8 append "a" "¢" "€"))
```
---
    3

### includes? works on multi-byte content

```x
(StrUtf8 includes? "¢" "a¢€")
```
---
    #t

### the same method differs by class: length

```x
(list (Str8 length "€") (StrUtf8 length "€"))
```
---
    (3 1)

## byte accessors (always byte-level)

### str-length is byte-level (the raw octet accessor)

```x
(%str-length "$¢€")
```
---
    6

### str-ref is byte-level

```x
(Char ->int (%str-ref "$¢€" 1))
```
---
    194

### str->list decodes code points (active protocol)

```x
(List map (method-ref Char ->int) (StrUtf8 ->list "$¢€"))
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

```x
("a,b,c" split ",")
```
---
    ("a" "b" "c")

### another combinator: includes?

```x
("hello" includes? "ell")
```
---
    #t

### the bare (s i) code-point call still works

```x
("hi" 0)
```
---
    #\h

### the bare (s i) call takes a negative index from the end

```x
("hi" -1)
```
---
    #\i

### the bare (s i) call errors past the end instead of over-reading

```x
("hi" 5)
```
---
    Error: #<err:index str: index out of range>

### the bare (s a n) slice clamps at the end

```x
("hello" 3 10)
```
---
    "lo"

### the named accessor now value-dispatches too (data-last -> subject-last)

```x
("abc" index 1)
```
---
    #\b

## index alias

### index is a working alias for ref

```x
(Char ->int (Str8 index 1 "abc"))
```
---
    98

## position search (#25)

### index-of finds the first occurrence; misses are nil

```x
(list (Str8 index-of "ll" "hello") (Str8 index-of "" "hi") (null? (Str8 index-of "zz" "hello")))
```
---
    (2 0 #t)

### last-index-of finds the last occurrence; misses are nil

```x
(list (Str8 last-index-of "l" "hello") (Str8 last-index-of "aa" "aaaa") (null? (Str8 last-index-of "z" "abc")))
```
---
    (3 2 #t)

### StrUtf8 positions are code points

```x
(import x/type/str-utf8)
(StrUtf8 index-of "€" "$¢€!")
```
---
    2

## literal replace (#25)

### replaces every occurrence, non-overlapping, left to right

```x
(list (Str8 replace "l" "L" "hello") (Str8 replace "aa" "b" "aaaa") (Str8 replace "zz" "b" "hello"))
```
---
    ("heLLo" "bb" "hello")

### an empty search string refuses (it would never advance)

```x
(guard (e (Err kind-of e)) (Str8 replace "" "x" "hi"))
```
---
    'value

## format (#25)

### positional slots render display-style

```x
(Str8 format "{} + {} = {}" 1 2 "three")
```
---
    "1 + 2 = three"

### width and alignment: > right, < left (the default)

```x
(list (Str8 format "[{:>6}]" "ok") (Str8 format "[{:<6}]" "ok") (Str8 format "[{:6}]" "ok"))
```
---
    ("[    ok]" "[ok    ]" "[ok    ]")

### precision setup: the tower loads in its OWN block

The harness begin-wraps each block into one form, so a float literal in
the same block as (import x/num/float) would parse BEFORE the import
evaluates -- the tower parse-before-eval trap, begin-flavored.

```x
(do (import x/num/float) #t)
```
---
    #t

### precision: ints gain decimals, floats round and keep exactly P

```x
(list (Str8 format "{:.2}" 7) (Str8 format "{:.2}" 3.14159) (Str8 format "{:.2}" 2.5) (Str8 format "{:>8.2}" 3.5))
```
---
    ("7.00" "3.14" "2.50" "    3.50")

### braces escape by doubling

```x
(Str8 format "{{}} is a slot; {} fills it" "x")
```
---
    "{} is a slot; x fills it"

### slot/argument arity is strict, both directions, and templates must close

```x
(list (guard (e (Err kind-of e)) (Str8 format "{}"))
      (guard (e (Err kind-of e)) (Str8 format "x" 1))
      (guard (e (Err kind-of e)) (Str8 format "{" 1)))
```
---
    ('value 'value 'value)

### StrUtf8 widths pad by code points

```x
(import x/type/str-utf8)
(StrUtf8 format "[{:>4}]" "é")
```
---
    "[   é]"

### upcase rejects a non-string

```x
(Str upcase 42)
```
---
    Error: #<err:type Str8: not a string>

### length rejects a non-string

`Str` is StrUtf8, whose `length` counts code points through the cursor walk,
so the guard fires at `start` rather than in Str8's byte-length seat.

```x
(Str length 42)
```
---
    Error: #<err:type Str8: not a string>

### length on a pair no longer returns a byte count

```x
(Str length (list 1 2))
```
---
    Error: #<err:type Str8: not a string>

### join rejects non-string elements

```x
(Str join ", " (list 1 2 3))
```
---
    Error: #<err:type Str8 join: element not a string>

### sub rejects a non-string

```x
(Str sub 0 2 42)
```
---
    Error: #<err:type Str sub: not a string>


## wrap and fill (#375)

### greedy wrap at the width; fill joins with newlines

```x
(list (Str8 wrap 10 "the quick brown fox jumps")
      (Str8 fill 10 "the quick brown fox"))
```
---
    (("the quick" "brown fox" "jumps") "the quick\nbrown fox")

### long words stand alone unbroken; whitespace-only input gives no lines

```x
(list (Str8 wrap 4 "a verylongword b")
      (Str8 wrap 5 "   ")
      (Str8 fill 5 ""))
```
---
    (("a" "verylongword" "b") () "")
