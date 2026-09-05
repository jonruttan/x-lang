# @weight 1
## char-alphabetic?

### lowercase letter

```x
(Char alphabetic? #\a)
```
---
    #t

### uppercase letter

```x
(Char alphabetic? #\Z)
```
---
    #t

### digit is not alphabetic

```x
(Char alphabetic? #\5)
```
---
    #f

## char-numeric?

### digit

```x
(Char numeric? #\7)
```
---
    #t

### letter is not numeric

```x
(Char numeric? #\x)
```
---
    #f

## char-whitespace?

### space

```x
(Char whitespace? #\space)
```
---
    #t

### tab

```x
(Char whitespace? ("\t" 0))
```
---
    #t

### letter is not whitespace

```x
(Char whitespace? #\a)
```
---
    #f

## char-upper-case?

### uppercase

```x
(Char upper-case? #\A)
```
---
    #t

### lowercase is not upper

```x
(Char upper-case? #\a)
```
---
    #f

## char-lower-case?

### lowercase

```x
(Char lower-case? #\a)
```
---
    #t

### uppercase is not lower

```x
(Char lower-case? #\A)
```
---
    #f

## char-upcase

### uppercases lowercase

```x
(= (Char upcase #\a) #\A)
```
---
    #t

### uppercase unchanged

```x
(= (Char upcase #\Z) #\Z)
```
---
    #t

## char-downcase

### lowercases uppercase

```x
(= (Char downcase #\A) #\a)
```
---
    #t

## char=?

### equal chars

```x
(Char =? #\a #\a)
```
---
    #t

### unequal chars

```x
(Char =? #\a #\b)
```
---
    #f

## char<?

### less than

```x
(Char <? #\a #\b)
```
---
    #t

### not less

```x
(Char <? #\b #\a)
```
---
    #f

## char-ci=?

### case insensitive equal

```x
(Char ci=? #\a #\A)
```
---
    #t

### case insensitive unequal

```x
(Char ci=? #\a #\b)
```
---
    #f

## char>?

### greater than

```x
(Char >? #\b #\a)
```
---
    #t

### not greater

```x
(if (Char >? #\a #\b) "y" "n")
```
---
    "n"

## char<=?

### less or equal

```x
(Char <=? #\a #\a)
```
---
    #t

## char>=?

### greater or equal

```x
(Char >=? #\z #\z)
```
---
    #t

## char-ci<?

### case insensitive less

```x
(Char ci<? #\a #\B)
```
---
    #t

## char-ci>?

### case insensitive greater

```x
(Char ci>? #\B #\a)
```
---
    #t

## char-ci<=?

### case insensitive less or equal

```x
(Char ci<=? #\a #\A)
```
---
    #t

## char-ci>=?

### case insensitive greater or equal

```x
(Char ci>=? #\A #\a)
```
---
    #t
