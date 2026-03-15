## character basics

### char? on char

```scheme
(char? #\a)
```
---
    t

### char? on string

```scheme
(null? (char? "a"))
```
---
    t

### char? on number

```scheme
(null? (char? 65))
```
---
    t

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
    t

### char=? not equal

```scheme
(null? (char=? #\a #\b))
```
---
    t

### char<? less

```scheme
(char<? #\a #\b)
```
---
    t

### char<? not less

```scheme
(null? (char<? #\b #\a))
```
---
    t

### char>? greater

```scheme
(char>? #\b #\a)
```
---
    t

### char<=? equal

```scheme
(char<=? #\a #\a)
```
---
    t

### char<=? less

```scheme
(char<=? #\a #\b)
```
---
    t

### char>=? equal

```scheme
(char>=? #\a #\a)
```
---
    t

### char>=? greater

```scheme
(char>=? #\b #\a)
```
---
    t

### char>=? not greater

```scheme
(null? (char>=? #\a #\b))
```
---
    t

