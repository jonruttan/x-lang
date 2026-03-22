## char-alphabetic?

### lowercase letter

```scheme
(char-alphabetic? ("a" 0))
```
---
    #t

### uppercase letter

```scheme
(char-alphabetic? ("Z" 0))
```
---
    #t

### digit is not alphabetic

```scheme
(char-alphabetic? ("5" 0))
```
---
    #f

## char-numeric?

### digit

```scheme
(char-numeric? ("7" 0))
```
---
    #t

### letter is not numeric

```scheme
(char-numeric? ("x" 0))
```
---
    #f

## char-whitespace?

### space

```scheme
(char-whitespace? (" " 0))
```
---
    #t

### tab

```scheme
(char-whitespace? ("\t" 0))
```
---
    #t

### letter is not whitespace

```scheme
(char-whitespace? ("a" 0))
```
---
    #f

## char-upper-case?

### uppercase

```scheme
(char-upper-case? ("A" 0))
```
---
    #t

### lowercase is not upper

```scheme
(char-upper-case? ("a" 0))
```
---
    #f

## char-lower-case?

### lowercase

```scheme
(char-lower-case? ("a" 0))
```
---
    #t

### uppercase is not lower

```scheme
(char-lower-case? ("A" 0))
```
---
    #f

## char-upcase

### uppercases lowercase

```scheme
(= (char-upcase ("a" 0)) ("A" 0))
```
---
    #t

### uppercase unchanged

```scheme
(= (char-upcase ("Z" 0)) ("Z" 0))
```
---
    #t

## char-downcase

### lowercases uppercase

```scheme
(= (char-downcase ("A" 0)) ("a" 0))
```
---
    #t

## char=?

### equal chars

```scheme
(char=? ("a" 0) ("a" 0))
```
---
    #t

### unequal chars

```scheme
(char=? ("a" 0) ("b" 0))
```
---
    #f

## char<?

### less than

```scheme
(char<? ("a" 0) ("b" 0))
```
---
    #t

### not less

```scheme
(char<? ("b" 0) ("a" 0))
```
---
    #f

## char-ci=?

### case insensitive equal

```scheme
(char-ci=? ("a" 0) ("A" 0))
```
---
    #t

### case insensitive unequal

```scheme
(char-ci=? ("a" 0) ("b" 0))
```
---
    #f

## char>?

### greater than

```scheme
(char>? ("b" 0) ("a" 0))
```
---
    #t

### not greater

```scheme
(if (char>? ("a" 0) ("b" 0)) "y" "n")
```
---
    "n"

## char<=?

### less or equal

```scheme
(char<=? ("a" 0) ("a" 0))
```
---
    #t

## char>=?

### greater or equal

```scheme
(char>=? ("z" 0) ("z" 0))
```
---
    #t

## char-ci<?

### case insensitive less

```scheme
(char-ci<? ("a" 0) ("B" 0))
```
---
    #t

## char-ci>?

### case insensitive greater

```scheme
(char-ci>? ("B" 0) ("a" 0))
```
---
    #t

## char-ci<=?

### case insensitive less or equal

```scheme
(char-ci<=? ("a" 0) ("A" 0))
```
---
    #t

## char-ci>=?

### case insensitive greater or equal

```scheme
(char-ci>=? ("A" 0) ("a" 0))
```
---
    #t
