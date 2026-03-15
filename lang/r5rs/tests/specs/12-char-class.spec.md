# Character Classification and Case

## char-alphabetic?

### alphabetic lowercase

```scheme
(char-alphabetic? #\a)
```
---
    #t

### alphabetic uppercase

```scheme
(char-alphabetic? #\Z)
```
---
    #t

### digit is not alphabetic

```scheme
(not (char-alphabetic? #\5))
```
---
    #t

### space is not alphabetic

```scheme
(not (char-alphabetic? #\space))
```
---
    #t

## char-numeric?

### digit is numeric

```scheme
(char-numeric? #\0)
```
---
    #t

### nine is numeric

```scheme
(char-numeric? #\9)
```
---
    #t

### letter is not numeric

```scheme
(not (char-numeric? #\a))
```
---
    #t

## char-whitespace?

### space is whitespace

```scheme
(char-whitespace? #\space)
```
---
    #t

### newline is whitespace

```scheme
(char-whitespace? #\newline)
```
---
    #t

### letter is not whitespace

```scheme
(not (char-whitespace? #\a))
```
---
    #t

## char-upper-case? / char-lower-case?

### uppercase detection

```scheme
(char-upper-case? #\A)
```
---
    #t

### lowercase detection

```scheme
(char-lower-case? #\z)
```
---
    #t

### uppercase is not lowercase

```scheme
(not (char-lower-case? #\A))
```
---
    #t

### lowercase is not uppercase

```scheme
(not (char-upper-case? #\a))
```
---
    #t

## char-upcase / char-downcase

### upcase lowercase letter

```scheme
(char=? (char-upcase #\a) #\A)
```
---
    #t

### downcase uppercase letter

```scheme
(char=? (char-downcase #\Z) #\z)
```
---
    #t

### upcase already uppercase

```scheme
(char=? (char-upcase #\A) #\A)
```
---
    #t

### downcase already lowercase

```scheme
(char=? (char-downcase #\a) #\a)
```
---
    #t

### upcase digit unchanged

```scheme
(char=? (char-upcase #\5) #\5)
```
---
    #t

## case-insensitive char comparison

### char-ci=? same case

```scheme
(char-ci=? #\a #\a)
```
---
    #t

### char-ci=? different case

```scheme
(char-ci=? #\A #\a)
```
---
    #t

### char-ci<? across case

```scheme
(char-ci<? #\A #\b)
```
---
    #t

### char-ci>? across case

```scheme
(char-ci>? #\b #\A)
```
---
    #t

### char-ci<=? equal across case

```scheme
(char-ci<=? #\a #\A)
```
---
    #t

### char-ci>=? equal across case

```scheme
(char-ci>=? #\A #\a)
```
---
    #t

## case-insensitive string comparison

### string-ci=? same case

```scheme
(string-ci=? "hello" "hello")
```
---
    #t

### string-ci=? different case

```scheme
(string-ci=? "Hello" "HELLO")
```
---
    #t

### string-ci=? not equal

```scheme
(not (string-ci=? "hello" "world"))
```
---
    #t

### string-ci<? across case

```scheme
(string-ci<? "ABC" "def")
```
---
    #t

### string-ci>? across case

```scheme
(string-ci>? "DEF" "abc")
```
---
    #t
