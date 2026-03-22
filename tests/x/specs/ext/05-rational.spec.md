# @lib x-base.x

## construction

### make-rational basic

```scheme
(%make-rational 3 4)
```
---
    3/4

### make-rational auto-reduce

```scheme
(%make-rational 6 4)
```
---
    3/2

### make-rational reduces to integer

```scheme
(%make-rational 6 3)
```
---
    2

### make-rational negative numerator

```scheme
(%make-rational -3 4)
```
---
    -3/4

### make-rational negative denominator normalizes

```scheme
(%make-rational 3 -4)
```
---
    -3/4

### make-rational division by zero

```scheme
(guard (e e) (%make-rational 1 0))
```
---
    "division by zero"

## tokenizer

### rational literal 1/2

```scheme
1/2
```
---
    1/2

### rational literal 3/4

```scheme
3/4
```
---
    3/4

### rational literal auto-reduces

```scheme
6/4
```
---
    3/2

### negative rational literal

```scheme
-3/4
```
---
    -3/4

### rational literal reduces to integer

```scheme
4/2
```
---
    2

## predicates

### rational? on rational

```scheme
(null? (rational? 3/4))
```
---
    #f

### rational? on integer

```scheme
(null? (rational? 42))
```
---
    #f

### exact? on rational

```scheme
(null? (exact? 3/4))
```
---
    #f

### exact? on integer

```scheme
(null? (exact? 42))
```
---
    #f

## accessors

### numerator of rational

```scheme
(numerator 3/4)
```
---
    3

### denominator of rational

```scheme
(denominator 3/4)
```
---
    4

### numerator of integer

```scheme
(numerator 5)
```
---
    5

### denominator of integer

```scheme
(denominator 5)
```
---
    1

## arithmetic

### rat+ basic

```scheme
(rat+ 1/3 1/6)
```
---
    1/2

### rat- basic

```scheme
(rat- 3/4 1/4)
```
---
    1/2

### rat* basic

```scheme
(rat* 2/3 3/5)
```
---
    2/5

### rat/ basic

```scheme
(rat/ 1/2 1/3)
```
---
    3/2

## operator promotion

### + with rationals

```scheme
(+ 1/3 1/6)
```
---
    1/2

### + int and rational

```scheme
(+ 1 1/2)
```
---
    3/2

### - with rational

```scheme
(- 1 1/3)
```
---
    2/3

### * rational and int

```scheme
(* 2/3 3)
```
---
    2

### / integers produces rational

```scheme
(/ 1 3)
```
---
    1/3

### / integers exact produces integer

```scheme
(/ 6 3)
```
---
    2

### + int stays int

```scheme
(+ 2 3)
```
---
    5

## comparisons

### rat< true

```scheme
(null? (rat< 1/3 1/2))
```
---
    #f

### rat< false

```scheme
(if (rat< 1/2 1/3) "yes" "no")
```
---
    "no"

### rat= true

```scheme
(if (rat= 2/4 1/2) "yes" "no")
```
---
    "yes"

### rat= false

```scheme
(if (rat= 1/3 1/2) "yes" "no")
```
---
    "no"

### < with rationals

```scheme
(null? (< 1/3 1/2))
```
---
    #f

### = with rationals

```scheme
(null? (= 2/4 1/2))
```
---
    #f

## conversion

### convert int to rational

```scheme
(convert 5 %rational)
```
---
    5

### convert string to rational

```scheme
(convert "3/4" %rational)
```
---
    3/4

### convert rational to int

```scheme
(convert 3/4 (type-of 42))
```
---
    0

### convert rational to string

```scheme
(convert 3/4 (type-of ""))
```
---
    "3/4"

## numerator

### extracts numerator

```scheme
(numerator 3/4)
```
---
    3

### integer numerator is itself

```scheme
(numerator 5)
```
---
    5

## denominator

### extracts denominator

```scheme
(denominator 3/4)
```
---
    4

### integer denominator is one

```scheme
(denominator 5)
```
---
    1
