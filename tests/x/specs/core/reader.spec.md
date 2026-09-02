# @lib x-base.x
# @weight 3

## integer reader

### reads positive integers

```x
99
```
---
    99

### reads negative integers

```x
-99
```
---
    -99

### reads zero

```x
0
```
---
    0

## string reader

### reads simple string

```x
"hello"
```
---
    "hello"

### reads empty string

```x
""
```
---
    ""

### reads string with escaped quote

```x
"a\"b"
```
---
    "a\"b"

### reads string with escaped backslash

```x
"a\\\\b"
```
---
    "a\\\\b"

### reads string with newline escape

```x
(%str-length "a\nb")
```
---
    3

### reads string with tab escape

```x
(%str-length "a\tb")
```
---
    3

### reads string with carriage return escape

```x
(%str-length "a\rb")
```
---
    3

### reads string with hex escape

```x
(= (Convert to (%str-ref "\x41" 0) %int) 65)
```
---
    #t

### preserves unknown escape sequences

```x
(%str-length "\q")
```
---
    2

## symbol reader

### reads simple symbol

```x
'abc
```
---
    'abc

### reads symbol with punctuation

```x
'my-var?
```
---
    'my-var?

### reads operator symbols

```x
'+
```
---
    '+

## character reader

### reads character literal

```x
(char? #\x)
```
---
    #t

### reads specific character

```x
(Convert to #\a %int)
```
---
    97

### reads uppercase character

```x
(Convert to #\Z %int)
```
---
    90

### reads named character space

```x
(Convert to #\space %int)
```
---
    32

### reads named character newline

```x
(Convert to #\newline %int)
```
---
    10

### reads named character tab

```x
(Convert to #\tab %int)
```
---
    9

## list reader

### reads proper list

```x
(lit (1 2 3))
```
---
    (1 2 3)

### reads nested list

```x
(lit (1 (2 3)))
```
---
    (1 (2 3))

### reads empty list

```x
()
```
---

### truncated list raises instead of spinning

```x
(guard (e (display e)) ((prim-ref 'tok 'read-str) (%base) "(a b"))
```
---
    Unterminated input

### truncated non-list tail still drops silently

```x
(write ((prim-ref 'tok 'read-str) (%base) "12 34"))
```
---
    (12)

### clean-EOF sentinel is identity-stable

```x
(write ((prim-ref 'obj 'same?) %token-eof %token-eof))
```
---
    #t

## dotted pair reader

### reads dotted pair first

```x
(first (lit (1 . 2)))
```
---
    1

### reads dotted pair rest

```x
(rest (lit (1 . 2)))
```
---
    2

### reads list with dotted tail

```x
(rest (lit (1 2 . 3)))
```
---
    (2 . 3)

## quote shorthand

### single-quote expands to lit

```x
'a
```
---
    'a

## comment handling

### ignores line comments


## vector literal reader

### reads vector literal

```x
(write #(1 2 3))
```
---
    #(1 2 3)

### reads empty vector literal

```x
(write #())
```
---
    #()

## regex literal reader

### reads regex literal

```x
(write #/abc/)
```
---
    #/abc/

