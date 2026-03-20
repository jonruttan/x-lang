# @lib x-base.x

## integer reader

### reads positive integers

```scheme
99
```
---
    99

### reads negative integers

```scheme
-99
```
---
    -99

### reads zero

```scheme
0
```
---
    0

## string reader

### reads simple string

```scheme
"hello"
```
---
    "hello"

### reads empty string

```scheme
""
```
---
    ""

### reads string with escaped quote

```scheme
"a\"b"
```
---
    "a\"b"

### reads string with escaped backslash

```scheme
"a\\\\b"
```
---
    "a\\\\b"

### reads string with newline escape

```scheme
(string-length "a\nb")
```
---
    3

### reads string with tab escape

```scheme
(string-length "a\tb")
```
---
    3

### reads string with carriage return escape

```scheme
(string-length "a\rb")
```
---
    3

### reads string with hex escape

```scheme
(= (convert (string-ref "\x41" 0) %int) 65)
```
---
    #t

### preserves unknown escape sequences

```scheme
(string-length "\q")
```
---
    2

## symbol reader

### reads simple symbol

```scheme
(lit abc)
```
---
    abc

### reads symbol with punctuation

```scheme
(lit my-var?)
```
---
    my-var?

### reads operator symbols

```scheme
(lit +)
```
---
    +

## character reader

### reads character literal

```scheme
(char? #\x)
```
---
    #t

### reads specific character

```scheme
(convert #\a %int)
```
---
    97

### reads uppercase character

```scheme
(convert #\Z %int)
```
---
    90

### reads named character space

```scheme
(convert #\space %int)
```
---
    32

### reads named character newline

```scheme
(convert #\newline %int)
```
---
    10

### reads named character tab

```scheme
(convert #\tab %int)
```
---
    9

## list reader

### reads proper list

```scheme
(lit (1 2 3))
```
---
    (1 2 3)

### reads nested list

```scheme
(lit (1 (2 3)))
```
---
    (1 (2 3))

### reads empty list

```scheme
()
```
---

## dotted pair reader

### reads dotted pair first

```scheme
(first (lit (1 . 2)))
```
---
    1

### reads dotted pair rest

```scheme
(rest (lit (1 . 2)))
```
---
    2

### reads list with dotted tail

```scheme
(rest (lit (1 2 . 3)))
```
---
    (2 . 3)

## quote shorthand

### single-quote expands to lit

```scheme
(lit a)
```
---
    a

## comment handling

### ignores line comments


## vector literal reader

### reads vector literal

```scheme
(write #(1 2 3))
```
---
    #(1 2 3)

### reads empty vector literal

```scheme
(write #())
```
---
    #()

## regex literal reader

### reads regex literal

```scheme
(write #/abc/)
```
---
    #/abc/

