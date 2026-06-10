## char-alphabetic?

### lowercase letter

```scheme
(Char alphabetic? ("a" 0))
```
---
    #t

### uppercase letter

```scheme
(Char alphabetic? ("Z" 0))
```
---
    #t

### digit is not alphabetic

```scheme
(Char alphabetic? ("5" 0))
```
---
    #f

## char-numeric?

### digit

```scheme
(Char numeric? ("7" 0))
```
---
    #t

### letter is not numeric

```scheme
(Char numeric? ("x" 0))
```
---
    #f

## char-whitespace?

### space

```scheme
(Char whitespace? (" " 0))
```
---
    #t

### tab

```scheme
(Char whitespace? ("\t" 0))
```
---
    #t

### letter is not whitespace

```scheme
(Char whitespace? ("a" 0))
```
---
    #f

## char-upper-case?

### uppercase

```scheme
(Char upper-case? ("A" 0))
```
---
    #t

### lowercase is not upper

```scheme
(Char upper-case? ("a" 0))
```
---
    #f

## char-lower-case?

### lowercase

```scheme
(Char lower-case? ("a" 0))
```
---
    #t

### uppercase is not lower

```scheme
(Char lower-case? ("A" 0))
```
---
    #f

## char-upcase

### uppercases lowercase

```scheme
(= (Char upcase ("a" 0)) ("A" 0))
```
---
    #t

### uppercase unchanged

```scheme
(= (Char upcase ("Z" 0)) ("Z" 0))
```
---
    #t

## char-downcase

### lowercases uppercase

```scheme
(= (Char downcase ("A" 0)) ("a" 0))
```
---
    #t

## char=?

### equal chars

```scheme
(Char =? ("a" 0) ("a" 0))
```
---
    #t

### unequal chars

```scheme
(Char =? ("a" 0) ("b" 0))
```
---
    #f

## char<?

### less than

```scheme
(Char <? ("a" 0) ("b" 0))
```
---
    #t

### not less

```scheme
(Char <? ("b" 0) ("a" 0))
```
---
    #f

## char-ci=?

### case insensitive equal

```scheme
(Char ci=? ("a" 0) ("A" 0))
```
---
    #t

### case insensitive unequal

```scheme
(Char ci=? ("a" 0) ("b" 0))
```
---
    #f

## char>?

### greater than

```scheme
(Char >? ("b" 0) ("a" 0))
```
---
    #t

### not greater

```scheme
(if (Char >? ("a" 0) ("b" 0)) "y" "n")
```
---
    "n"

## char<=?

### less or equal

```scheme
(Char <=? ("a" 0) ("a" 0))
```
---
    #t

## char>=?

### greater or equal

```scheme
(Char >=? ("z" 0) ("z" 0))
```
---
    #t

## char-ci<?

### case insensitive less

```scheme
(Char ci<? ("a" 0) ("B" 0))
```
---
    #t

## char-ci>?

### case insensitive greater

```scheme
(Char ci>? ("B" 0) ("a" 0))
```
---
    #t

## char-ci<=?

### case insensitive less or equal

```scheme
(Char ci<=? ("a" 0) ("A" 0))
```
---
    #t

## char-ci>=?

### case insensitive greater or equal

```scheme
(Char ci>=? ("A" 0) ("a" 0))
```
---
    #t
