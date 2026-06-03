## str-length

### returns length of string

```scheme
(str-length "hello")
```
---
    5

### returns 0 for empty string

```scheme
(str-length "")
```
---
    0

## str-ref

### returns character at index

```scheme
(str-ref "hello" 0)
```
---
    #\h

### returns middle character

```scheme
(str-ref "hello" 2)
```
---
    #\l

## str-append

### concatenates two strings

```scheme
(str-append "hello" " world")
```
---
    "hello world"

### appends to empty string

```scheme
(str-append "" "abc")
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

## str=?

### returns #t for equal strings

```scheme
(str=? "hello" "hello")
```
---
    #t

### returns #f for different strings

```scheme
(str=? "hello" "world")
```
---
    #f

## string to symbol

### converts string to symbol

```scheme
(convert "hello" %symbol)
```
---
    (lit hello)

### interned equality

```scheme
(eq? (convert "hello" %symbol) (lit hello))
```
---
    #t

## symbol to string

### converts symbol to string

```scheme
(convert (lit hello) %string)
```
---
    "hello"

### round-trip string/symbol/string

```scheme
(convert (convert "test" %symbol) %string)
```
---
    "test"

## number to string

### converts positive number

```scheme
(convert 42 %string)
```
---
    "42"

### converts zero

```scheme
(convert 0 %string)
```
---
    "0"

### converts negative number

```scheme
(convert -7 %string)
```
---
    "-7"

## string to number

### parses positive number

```scheme
(convert "42" %int)
```
---
    42

### parses negative number

```scheme
(convert "-5" %int)
```
---
    -5

### parses zero

```scheme
(convert "0" %int)
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
(= (convert (str-ref "\x41" 0) %int) 65)
```
---
    #t

### display outputs raw characters

```scheme
(display "a\tb")
```
---
    a	b

## string composition

### round-trips number/string/number

```scheme
(convert (convert 99 %string) %int)
```
---
    99

### builds string from parts

```scheme
(str-length (str-append "abc" "defgh"))
```
---
    8

