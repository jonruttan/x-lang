## string-length

### returns length of string

```scheme
(string-length "hello")
```
---
    5

### returns 0 for empty string

```scheme
(string-length "")
```
---
    0

## string-ref

### returns character at index

```scheme
(string-ref "hello" 0)
```
---
    h

### returns middle character

```scheme
(string-ref "hello" 2)
```
---
    l

## string-append

### concatenates two strings

```scheme
(string-append "hello" " world")
```
---
    "hello world"

### appends to empty string

```scheme
(string-append "" "abc")
```
---
    "abc"

## substring

### extracts substring

```scheme
(substring "hello world" 6 11)
```
---
    "world"

### extracts from start

```scheme
(substring "hello" 0 3)
```
---
    "hel"

### single character

```scheme
(substring "abc" 1 2)
```
---
    "b"

## string=?

### returns t for equal strings

```scheme
(string=? "hello" "hello")
```
---
    t

### returns nil for different strings

```scheme
(string=? "hello" "world")
```
---

## string->symbol

### converts string to symbol

```scheme
(string->symbol "hello")
```
---
    hello

### interned equality

```scheme
(eq? (string->symbol "hello") (lit hello))
```
---
    t

## symbol->string

### converts symbol to string

```scheme
(symbol->string (lit hello))
```
---
    "hello"

### round-trip string->symbol->string

```scheme
(symbol->string (string->symbol "test"))
```
---
    "test"

## number->string

### converts positive number

```scheme
(number->string 42)
```
---
    "42"

### converts zero

```scheme
(number->string 0)
```
---
    "0"

### converts negative number

```scheme
(number->string -7)
```
---
    "-7"

## string->number

### parses positive number

```scheme
(string->number "42")
```
---
    42

### parses negative number

```scheme
(string->number "-5")
```
---
    -5

### parses zero

```scheme
(string->number "0")
```
---
    0

## string escapes

### escaped quote round-trips through write

```scheme
(write "a\"b")
```
---
    "a\"b"

### escaped backslash round-trips through write

```scheme
(write "a\\\\b")
```
---
    "a\\\\b"

### newline round-trips through write

```scheme
(write "a\nb")
```
---
    "a\nb"

### tab round-trips through write

```scheme
(write "a\tb")
```
---
    "a\tb"

### carriage return round-trips through write

```scheme
(write "a\rb")
```
---
    "a\rb"

### hex escape produces correct byte

```scheme
(= (char->integer (string-ref "\x41" 0)) 65)
```
---
    t

### display outputs raw characters

```scheme
(display "a\tb")
```
---
    a	b

## string composition

### round-trips number->string->number

```scheme
(string->number (number->string 99))
```
---
    99

### builds string from parts

```scheme
(string-length (string-append "abc" "defgh"))
```
---
    8

