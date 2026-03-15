# make-string and number conversions

## make-string

### make-string with fill char

```scheme
(string=? (make-string 3 #\a) "aaa")
```
---
    t

### make-string single char

```scheme
(string=? (make-string 1 #\x) "x")
```
---
    t

### make-string length

```scheme
(string-length (make-string 5 #\z))
```
---
    5

## number->string

### decimal default

```scheme
(string=? (number->string 100) "100")
```
---
    t

### hexadecimal

```scheme
(string=? (number->string 255 16) "ff")
```
---
    t

### binary

```scheme
(string=? (number->string 5 2) "101")
```
---
    t

### octal

```scheme
(string=? (number->string 127 8) "177")
```
---
    t

### hex uppercase value

```scheme
(string=? (number->string 256 16) "100")
```
---
    t

### zero

```scheme
(string=? (number->string 0) "0")
```
---
    t

## string->number

### decimal default

```scheme
(= (string->number "100") 100)
```
---
    t

### hexadecimal

```scheme
(= (string->number "ff" 16) 255)
```
---
    t

### binary

```scheme
(= (string->number "101" 2) 5)
```
---
    t

### octal

```scheme
(= (string->number "177" 8) 127)
```
---
    t

### hex with prefix

```scheme
(= (string->number "100" 16) 256)
```
---
    t

## integer?

### number is integer

```scheme
(integer? 42)
```
---
    t

### zero is integer

```scheme
(integer? 0)
```
---
    t

### negative is integer

```scheme
(integer? -7)
```
---
    t

### string is not integer

```scheme
(null? (integer? "42"))
```
---
    t

### symbol is not integer

```scheme
(null? (integer? 'x))
```
---
    t
