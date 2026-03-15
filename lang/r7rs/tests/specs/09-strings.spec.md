## string basics

### string? on string

```scheme
(string? "hello")
```
---
    t

### string? on non-string

```scheme
(null? (string? 42))
```
---
    t

### string? on symbol

```scheme
(null? (string? (quote hello)))
```
---
    t

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

### string-ref middle

```scheme
(string-ref "abcde" 2)
```
---
    #\c

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

### string-append both empty

```scheme
(string-append "" "")
```
---
    ""

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

### substring full

```scheme
(substring "hello" 0 5)
```
---
    "hello"

### string-copy

```scheme
(string-copy "hello")
```
---
    "hello"

### string-copy is equal

```scheme
(equal? (string-copy "test") "test")
```
---
    t

## string comparison

### string=? equal

```scheme
(string=? "abc" "abc")
```
---
    t

### string=? not equal

```scheme
(null? (string=? "abc" "abd"))
```
---
    t

### string<? less

```scheme
(string<? "abc" "abd")
```
---
    t

### string<? not less

```scheme
(null? (string<? "abd" "abc"))
```
---
    t

### string<? prefix is less

```scheme
(string<? "abc" "abcd")
```
---
    t

### string>? greater

```scheme
(string>? "abd" "abc")
```
---
    t

### string<=? equal

```scheme
(string<=? "abc" "abc")
```
---
    t

### string<=? less

```scheme
(string<=? "abc" "abd")
```
---
    t

### string>=? equal

```scheme
(string>=? "abc" "abc")
```
---
    t

### string>=? greater

```scheme
(string>=? "abd" "abc")
```
---
    t

## string case-insensitive comparison

### string-ci=? equal same case

```scheme
(string-ci=? "abc" "abc")
```
---
    t

### string-ci=? equal different case

```scheme
(string-ci=? "Hello" "hello")
```
---
    t

### string-ci=? not equal

```scheme
(null? (string-ci=? "abc" "abd"))
```
---
    t

### string-ci<? less

```scheme
(string-ci<? "abc" "ABD")
```
---
    t

### string-ci>? greater

```scheme
(string-ci>? "ABD" "abc")
```
---
    t

### string-ci<=? equal different case

```scheme
(string-ci<=? "ABC" "abc")
```
---
    t

### string-ci>=? equal different case

```scheme
(string-ci>=? "abc" "ABC")
```
---
    t

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
    t

### number->string

```scheme
(number->string 42)
```
---
    "42"

### string->number valid

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
    t

### string->list single

```scheme
(string->list "x")
```
---
    (#\x)

## list->string

### list->string basic

```scheme
(list->string (list #\a #\b #\c))
```
---
    "abc"

### list->string empty

```scheme
(list->string ())
```
---
    ""

### list->string single

```scheme
(list->string (list #\z))
```
---
    "z"

### list->string roundtrip

```scheme
(list->string (string->list "hello"))
```
---
    "hello"

## make-string

### make-string with fill

```scheme
(make-string 3 #\a)
```
---
    "aaa"

### make-string length

```scheme
(string-length (make-string 5 #\x))
```
---
    5

### make-string zero

```scheme
(make-string 0 #\a)
```
---
    ""

## string constructor

### string from chars

```scheme
(string #\a #\b #\c)
```
---
    "abc"

### string single char

```scheme
(string #\z)
```
---
    "z"

### string empty

```scheme
(string)
```
---
    ""

## string case conversion

### string-upcase

```scheme
(string-upcase "hello")
```
---
    "HELLO"

### string-upcase mixed

```scheme
(string-upcase "Hello World")
```
---
    "HELLO WORLD"

### string-upcase already upper

```scheme
(string-upcase "ABC")
```
---
    "ABC"

### string-downcase

```scheme
(string-downcase "HELLO")
```
---
    "hello"

### string-downcase mixed

```scheme
(string-downcase "Hello World")
```
---
    "hello world"

### string-foldcase

```scheme
(string-foldcase "Hello")
```
---
    "hello"

### string-foldcase upper

```scheme
(string-foldcase "ABC")
```
---
    "abc"

## string-map

### string-map upcase

```scheme
(string-map char-upcase "hello")
```
---
    "HELLO"

### string-map identity

```scheme
(string-map (lambda (c) c) "abc")
```
---
    "abc"

### string-map empty

```scheme
(string-map char-upcase "")
```
---
    ""

## string-for-each

### string-for-each accumulates

```scheme
(define acc 0) (string-for-each (lambda (c) (set! acc (+ acc 1))) "hello") acc
```
---
    5

