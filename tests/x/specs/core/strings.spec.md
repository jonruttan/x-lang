# @weight 1
## str-length

### returns length of string

```x
(%str-length "hello")
```
---
    5

### returns 0 for empty string

```x
(%str-length "")
```
---
    0

## str-ref

### returns character at index

```x
(%str-ref "hello" 0)
```
---
    #\h

### returns middle character

```x
(%str-ref "hello" 2)
```
---
    #\l

## Str8 append

### concatenates two strings

```x
(Str8 append "hello" " world")
```
---
    "hello world"

### appends to empty string

```x
(Str8 append "" "abc")
```
---
    "abc"

### a non-string argument raises rather than reading raw memory (#159)

`%str-append` is a raw byte concat, so nil used to segfault here while every
sibling seat already raised. `append` does not coerce -- `(Str8 str ...)` is
the seat that renders non-strings.

```x
(Str8 append "a" ())
```
---
    Error: #<err:type Str8 append: not a string>

### a non-string argument raises wherever it sits

```x
(Str8 append "a" 5 "b")
```
---
    Error: #<err:type Str8 append: not a string>

## substring

### extracts substring

```x
(%substring "hello world" 6 11)
```
---
    "world"

### extracts from start

```x
(%substring "hello" 0 3)
```
---
    "hel"

### single character

```x
(%substring "abc" 1 2)
```
---
    "b"

## str=?

### returns #t for equal strings

```x
(str=? "hello" "hello")
```
---
    #t

### returns #f for different strings

```x
(str=? "hello" "world")
```
---
    #f

## string to symbol

### converts string to symbol

```x
(Convert to "hello" %symbol)
```
---
    'hello

### interned equality

```x
(eq? (Convert to "hello" %symbol) 'hello)
```
---
    #t

## symbol to string

### converts symbol to string

```x
(Convert to 'hello %string)
```
---
    "hello"

### round-trip string/symbol/string

```x
(Convert to (Convert to "test" %symbol) %string)
```
---
    "test"

## number to string

### converts positive number

```x
(Convert to 42 %string)
```
---
    "42"

### converts zero

```x
(Convert to 0 %string)
```
---
    "0"

### converts negative number

```x
(Convert to -7 %string)
```
---
    "-7"

## string to number

### parses positive number

```x
(Convert to "42" %int)
```
---
    42

### parses negative number

```x
(Convert to "-5" %int)
```
---
    -5

### parses zero

```x
(Convert to "0" %int)
```
---
    0

## string escapes

### escaped quote round-trips through write

```x
(write "a\"b")
```
---
    "a\"b"

### escaped backslash round-trips through write

```x
(write "a\\\\b")
```
---
    "a\\\\b"

### newline round-trips through write

```x
(write "a\nb")
```
---
    "a\nb"

### tab round-trips through write

```x
(write "a\tb")
```
---
    "a\tb"

### carriage return round-trips through write

```x
(write "a\rb")
```
---
    "a\rb"

### hex escape produces correct byte

```x
(= (Convert to (%str-ref "\x41" 0) %int) 65)
```
---
    #t

### display outputs raw characters

```x
(display "a\tb")
```
---
    a	b

## string composition

### round-trips number/string/number

```x
(Convert to (Convert to 99 %string) %int)
```
---
    99

### builds string from parts

```x
(%str-length (Str8 append "abc" "defgh"))
```
---
    8


## number->str

### zero and ordinaries

```x
(list (%number->str 0) (%number->str 12345) (%number->str -42))
```
---
    ("0" "12345" "-42")

### radix

```x
(list (%number->str 255 16) (%number->str -255 16) (%number->str 7 2))
```
---
    ("ff" "-ff" "111")

### the most-negative fixnum terminates (word-size portable)

The negative-domain rewrite's INT_MIN pin, computed from %word-size so
the 32-bit Pi build passes too; the round-trip proves the digits.

```x
(do
  (def %n (<< 1 (- (* 8 %word-size) 1)))
  (eq? (%str->number (%number->str %n)) %n))
```
---
    #t

## str->number hex prefix (#76)

The reader has always accepted `0xff` as a literal; the string parser now
matches it. Detection is prefix-only and only when no explicit radix is
passed -- an explicit radix means the caller controls interpretation, which
keeps the JSON `\u` parser (`(%str->number %t 16)`) byte-exact.

### parses the reader's hex notation

```x
(list (%str->number "0xff") (%str->number "0XFF") (%str->number "0x1A"))
```
---
    (255 255 26)

### sign parses before the prefix

```x
(list (%str->number "-0xff") (%str->number "+0x10"))
```
---
    (-255 16)

### misses stay nil -- 0 would be indistinguishable from parsing "0"

```x
(list (null? (%str->number "0x")) (null? (%str->number "0xg")) (null? (%str->number "abc")))
```
---
    (#t #t #t)

### an explicit radix disables auto-detection

```x
(list (%str->number "ff" 16) (null? (%str->number "0xff" 16)) (%str->number "101" 2))
```
---
    (255 #t 5)

## str->number overflow raises (#52 ruled)

Accumulation is negative-domain (the %n2s lesson: |INT_MIN| has no positive
reading), and each digit's multiply is verified by undoing it -- a wrap
fails the round-trip and raises instead of silently becoming a different
number, which is how JSON corrupted 64-bit IDs.

### overflow raises, boundaries parse exactly

```x
(list (guard (e (lit R)) (%str->number "12345678901234567890"))
      (guard (e (lit R)) (%str->number "9223372036854775808"))
      (%str->number "9223372036854775807")
      (%str->number "-9223372036854775808"))
```
---
    ('R 'R 9223372036854775807 -9223372036854775808)
