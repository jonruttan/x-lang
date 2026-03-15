## string basics

### string? on string

```scheme
(string? "hello")
```
---
    #t

### string? on non-string

```scheme
(not (string? 42))
```
---
    #t

### string-length

```scheme
(string-length "hello")
```
---
    5

### string-length empty

```scheme
(string-length "")
```
---
    0

### string-ref first

```scheme
(string-ref "hello" 0)
```
---
    #\h

### string-ref last

```scheme
(string-ref "hello" 4)
```
---
    #\o

## string operations

### string-append two

```scheme
(string-append "hello" " world")
```
---
    "hello world"

### string-append empty

```scheme
(string-append "" "abc")
```
---
    "abc"

### substring

```scheme
(substring "hello world" 6 11)
```
---
    "world"

### substring from start

```scheme
(substring "hello" 0 3)
```
---
    "hel"

### substring empty

```scheme
(substring "hello" 2 2)
```
---
    ""

### string-copy

```scheme
(string-copy "hello")
```
---
    "hello"

### string-copy is equal

```scheme
(define s "hello") (equal? s (string-copy s))
```
---
    #t

## string comparison

### string=? equal

```scheme
(string=? "abc" "abc")
```
---
    #t

### string=? not equal

```scheme
(not (string=? "abc" "abd"))
```
---
    #t

### string<? less

```scheme
(string<? "abc" "abd")
```
---
    #t

### string<? not less

```scheme
(not (string<? "abd" "abc"))
```
---
    #t

### string<? prefix is less

```scheme
(string<? "abc" "abcd")
```
---
    #t

### string>? greater

```scheme
(string>? "abd" "abc")
```
---
    #t

### string<=? equal

```scheme
(string<=? "abc" "abc")
```
---
    #t

### string<=? less

```scheme
(string<=? "abc" "abd")
```
---
    #t

### string>=? equal

```scheme
(string>=? "abc" "abc")
```
---
    #t

### string>=? greater

```scheme
(string>=? "abd" "abc")
```
---
    #t

## string conversion

### symbol->string

```scheme
(symbol->string (quote hello))
```
---
    "hello"

### string->symbol

```scheme
(eq? (string->symbol "hello") (quote hello))
```
---
    #t

### number->string

```scheme
(number->string 42)
```
---
    "42"

### string->number

```scheme
(string->number "42")
```
---
    42

### string->list

```scheme
(string->list "abc")
```
---
    (#\a #\b #\c)

### string->list empty

```scheme
(null? (string->list ""))
```
---
    #t

