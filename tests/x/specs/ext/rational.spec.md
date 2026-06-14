# @lib ../tests/x/lib/rational.x

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
(null? (Rational rational? 3/4))
```
---
    #f

### rational? on integer

```scheme
(null? (Rational rational? 42))
```
---
    #f

### exact? on rational

```scheme
(null? (Rational exact? 3/4))
```
---
    #f

### exact? on integer

```scheme
(null? (Rational exact? 42))
```
---
    #f

## accessors

### numerator of rational

```scheme
(Rational numerator 3/4)
```
---
    3

### denominator of rational

```scheme
(Rational denominator 3/4)
```
---
    4

### numerator of integer

```scheme
(Rational numerator 5)
```
---
    5

### denominator of integer

```scheme
(Rational denominator 5)
```
---
    1

## arithmetic

### rat+ basic

```scheme
(Rational + 1/3 1/6)
```
---
    1/2

### rat- basic

```scheme
(Rational - 3/4 1/4)
```
---
    1/2

### rat* basic

```scheme
(Rational * 2/3 3/5)
```
---
    2/5

### rat/ basic

```scheme
(Rational / 1/2 1/3)
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
(null? (Rational < 1/3 1/2))
```
---
    #f

### rat< false

```scheme
(if (Rational < 1/2 1/3) "yes" "no")
```
---
    "no"

### rat= true

```scheme
(if (Rational = 2/4 1/2) "yes" "no")
```
---
    "yes"

### rat= false

```scheme
(if (Rational = 1/3 1/2) "yes" "no")
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
(Convert to 5 %rational)
```
---
    5

### convert string to rational

```scheme
(Convert to "3/4" %rational)
```
---
    3/4

### convert rational to int

```scheme
(Convert to 3/4 (Type of 42))
```
---
    0

### convert rational to string

```scheme
(Convert to 3/4 (Type of ""))
```
---
    "3/4"

## numerator

### extracts numerator

```scheme
(Rational numerator 3/4)
```
---
    3

### integer numerator is itself

```scheme
(Rational numerator 5)
```
---
    5

## denominator

### extracts denominator

```scheme
(Rational denominator 3/4)
```
---
    4

### integer denominator is one

```scheme
(Rational denominator 5)
```
---
    1

## value dispatch (the value calls its class, subject-last)

### numerator via the value

```scheme
(1/2 numerator)
```
---
    1

### denominator via the value

```scheme
(3/4 denominator)
```
---
    4

### predicate via the value

```scheme
(1/3 rational?)
```
---
    #t

### commutative op reads naturally (the receiver is appended last)

```scheme
(1/2 + 1/3)
```
---
    5/6

### a non-commutative op is subject-last too ((1/2 - 1/3) -> (- 1/3 1/2))

```scheme
(1/2 - 1/3)
```
---
    -1/6

### unknown method errors

```scheme
(guard (e "no-such") (1/2 bogus))
```
---
    "no-such"

## value dispatch does not break data lists (regression)

### iterate a list of rationals (re-evaluated data list must pass through)

```scheme
(Iter ->list (Iter new (list 1/2 1/3 1/4)))
```
---
    (1/2 1/3 1/4)

### a single-element rational list iterates

```scheme
(Iter ->list (Iter new (list 3/4)))
```
---
    (3/4)
