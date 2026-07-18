## char-alphabetic?

### lowercase letter

```scheme
(Char alphabetic? #\a)
```
---
    #t

### uppercase letter

```scheme
(Char alphabetic? #\Z)
```
---
    #t

### digit is not alphabetic

```scheme
(Char alphabetic? #\5)
```
---
    #f

## char-numeric?

### digit

```scheme
(Char numeric? #\7)
```
---
    #t

### letter is not numeric

```scheme
(Char numeric? #\x)
```
---
    #f

## char-whitespace?

### space

```scheme
(Char whitespace? #\space)
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
(Char whitespace? #\a)
```
---
    #f

## char-upper-case?

### uppercase

```scheme
(Char upper-case? #\A)
```
---
    #t

### lowercase is not upper

```scheme
(Char upper-case? #\a)
```
---
    #f

## char-lower-case?

### lowercase

```scheme
(Char lower-case? #\a)
```
---
    #t

### uppercase is not lower

```scheme
(Char lower-case? #\A)
```
---
    #f

## char-upcase

### uppercases lowercase

```scheme
(= (Char upcase #\a) #\A)
```
---
    #t

### uppercase unchanged

```scheme
(= (Char upcase #\Z) #\Z)
```
---
    #t

## char-downcase

### lowercases uppercase

```scheme
(= (Char downcase #\A) #\a)
```
---
    #t

## char=?

### equal chars

```scheme
(Char =? #\a #\a)
```
---
    #t

### unequal chars

```scheme
(Char =? #\a #\b)
```
---
    #f

## char<?

### less than

```scheme
(Char <? #\a #\b)
```
---
    #t

### not less

```scheme
(Char <? #\b #\a)
```
---
    #f

## char-ci=?

### case insensitive equal

```scheme
(Char ci=? #\a #\A)
```
---
    #t

### case insensitive unequal

```scheme
(Char ci=? #\a #\b)
```
---
    #f

## char>?

### greater than

```scheme
(Char >? #\b #\a)
```
---
    #t

### not greater

```scheme
(if (Char >? #\a #\b) "y" "n")
```
---
    "n"

## char<=?

### less or equal

```scheme
(Char <=? #\a #\a)
```
---
    #t

## char>=?

### greater or equal

```scheme
(Char >=? #\z #\z)
```
---
    #t

## char-ci<?

### case insensitive less

```scheme
(Char ci<? #\a #\B)
```
---
    #t

## char-ci>?

### case insensitive greater

```scheme
(Char ci>? #\B #\a)
```
---
    #t

## char-ci<=?

### case insensitive less or equal

```scheme
(Char ci<=? #\a #\A)
```
---
    #t

## char-ci>=?

### case insensitive greater or equal

```scheme
(Char ci>=? #\A #\a)
```
---
    #t
