## char basics

### char? on char

```scheme
(char? #\a)
```
---
    #t

### char? on string

```scheme
(not (char? "a"))
```
---
    #t

### char? on number

```scheme
(not (char? 65))
```
---
    #t

### char->integer uppercase

```scheme
(char->integer #\A)
```
---
    65

### char->integer lowercase

```scheme
(char->integer #\a)
```
---
    97

### char->integer digit

```scheme
(char->integer #\0)
```
---
    48

### integer->char

```scheme
(integer->char 65)
```
---
    #\A

### roundtrip char->int->char

```scheme
(integer->char (char->integer #\z))
```
---
    #\z

### char->integer space

```scheme
(char->integer #\space)
```
---
    32

### char->integer newline

```scheme
(char->integer #\newline)
```
---
    10

## char comparison

### char=? equal

```scheme
(char=? #\a #\a)
```
---
    #t

### char=? not equal

```scheme
(not (char=? #\a #\b))
```
---
    #t

### char<? less

```scheme
(char<? #\a #\b)
```
---
    #t

### char<? not less

```scheme
(not (char<? #\b #\a))
```
---
    #t

### char>? greater

```scheme
(char>? #\b #\a)
```
---
    #t

### char<=? equal

```scheme
(char<=? #\a #\a)
```
---
    #t

### char<=? less

```scheme
(char<=? #\a #\b)
```
---
    #t

### char>=? equal

```scheme
(char>=? #\a #\a)
```
---
    #t

### char>=? greater

```scheme
(char>=? #\b #\a)
```
---
    #t

## char classification

### char-alphabetic? lowercase

```scheme
(char-alphabetic? #\a)
```
---
    #t

### char-alphabetic? uppercase

```scheme
(char-alphabetic? #\Z)
```
---
    #t

### char-alphabetic? digit

```scheme
(not (char-alphabetic? #\0))
```
---
    #t

### char-alphabetic? space

```scheme
(not (char-alphabetic? #\space))
```
---
    #t

### char-numeric? digit

```scheme
(char-numeric? #\5)
```
---
    #t

### char-numeric? letter

```scheme
(not (char-numeric? #\a))
```
---
    #t

### char-whitespace? space

```scheme
(char-whitespace? #\space)
```
---
    #t

### char-whitespace? newline

```scheme
(char-whitespace? #\newline)
```
---
    #t

### char-whitespace? letter

```scheme
(not (char-whitespace? #\a))
```
---
    #t

### char-upper-case? uppercase

```scheme
(char-upper-case? #\A)
```
---
    #t

### char-upper-case? lowercase

```scheme
(not (char-upper-case? #\a))
```
---
    #t

### char-lower-case? lowercase

```scheme
(char-lower-case? #\a)
```
---
    #t

### char-lower-case? uppercase

```scheme
(not (char-lower-case? #\A))
```
---
    #t

## char case conversion

### char-upcase lowercase

```scheme
(char-upcase #\a)
```
---
    #\A

### char-upcase already upper

```scheme
(char-upcase #\A)
```
---
    #\A

### char-upcase digit unchanged

```scheme
(char-upcase #\5)
```
---
    #\5

### char-downcase uppercase

```scheme
(char-downcase #\A)
```
---
    #\a

### char-downcase already lower

```scheme
(char-downcase #\a)
```
---
    #\a

### char-foldcase uppercase

```scheme
(char-foldcase #\A)
```
---
    #\a

### char-foldcase lowercase

```scheme
(char-foldcase #\a)
```
---
    #\a

## char case-insensitive comparison

### char-ci=? same case

```scheme
(char-ci=? #\a #\a)
```
---
    #t

### char-ci=? different case

```scheme
(char-ci=? #\a #\A)
```
---
    #t

### char-ci=? not equal

```scheme
(not (char-ci=? #\a #\b))
```
---
    #t

### char-ci<? less

```scheme
(char-ci<? #\a #\B)
```
---
    #t

### char-ci>? greater

```scheme
(char-ci>? #\B #\a)
```
---
    #t

