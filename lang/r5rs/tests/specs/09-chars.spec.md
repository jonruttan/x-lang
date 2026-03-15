## character basics

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

## character comparison

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

### char>=? not greater

```scheme
(not (char>=? #\a #\b))
```
---
    #t

