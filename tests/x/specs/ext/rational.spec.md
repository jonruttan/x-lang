# @lib ../tests/x/lib/rational.x
# @weight 4

## construction

### make-rational basic

```x
(%make-rational 3 4)
```
---
    3/4

### make-rational auto-reduce

```x
(%make-rational 6 4)
```
---
    3/2

### make-rational reduces to integer

```x
(%make-rational 6 3)
```
---
    2

### make-rational negative numerator

```x
(%make-rational -3 4)
```
---
    -3/4

### make-rational negative denominator normalizes

```x
(%make-rational 3 -4)
```
---
    -3/4

### make-rational division by zero

```x
(guard (e e) (%make-rational 1 0))
```
---
    "division by zero"

## tokenizer

### rational literal 1/2

```x
1/2
```
---
    1/2

### rational literal 3/4

```x
3/4
```
---
    3/4

### rational literal auto-reduces

```x
6/4
```
---
    3/2

### negative rational literal

```x
-3/4
```
---
    -3/4

### rational literal reduces to integer

```x
4/2
```
---
    2

## predicates

### rational? on rational

```x
(null? (Rational rational? 3/4))
```
---
    #f

### rational? on integer

```x
(null? (Rational rational? 42))
```
---
    #f

### exact? on rational

```x
(null? (Rational exact? 3/4))
```
---
    #f

### exact? on integer

```x
(null? (Rational exact? 42))
```
---
    #f

## accessors

### numerator of rational

```x
(Rational numerator 3/4)
```
---
    3

### denominator of rational

```x
(Rational denominator 3/4)
```
---
    4

### numerator of integer

```x
(Rational numerator 5)
```
---
    5

### denominator of integer

```x
(Rational denominator 5)
```
---
    1

## arithmetic

### rat+ basic

```x
(Rational + 1/3 1/6)
```
---
    1/2

### rat- basic

```x
(Rational - 3/4 1/4)
```
---
    1/2

### rat* basic

```x
(Rational * 2/3 3/5)
```
---
    2/5

### rat/ basic

```x
(Rational / 1/2 1/3)
```
---
    3/2

## operator promotion

### + with rationals

```x
(+ 1/3 1/6)
```
---
    1/2

### + int and rational

```x
(+ 1 1/2)
```
---
    3/2

### - with rational

```x
(- 1 1/3)
```
---
    2/3

### * rational and int

```x
(* 2/3 3)
```
---
    2

### / integers produces rational

```x
(/ 1 3)
```
---
    1/3

### / integers exact produces integer

```x
(/ 6 3)
```
---
    2

### + int stays int

```x
(+ 2 3)
```
---
    5

## comparisons

### rat< true

```x
(null? (Rational < 1/3 1/2))
```
---
    #f

### rat< false

```x
(if (Rational < 1/2 1/3) "yes" "no")
```
---
    "no"

### rat= true

```x
(if (Rational = 2/4 1/2) "yes" "no")
```
---
    "yes"

### rat= false

```x
(if (Rational = 1/3 1/2) "yes" "no")
```
---
    "no"

### < with rationals

```x
(null? (< 1/3 1/2))
```
---
    #f

### = with rationals

```x
(null? (= 2/4 1/2))
```
---
    #f

## conversion

### convert int to rational

```x
(Convert to 5 %rational)
```
---
    5

### convert string to rational

```x
(Convert to "3/4" %rational)
```
---
    3/4

### convert rational to int

```x
(Convert to 3/4 (Type of 42))
```
---
    0

### convert rational to string

```x
(Convert to 3/4 (Type of ""))
```
---
    "3/4"

## numerator

### extracts numerator

```x
(Rational numerator 3/4)
```
---
    3

### integer numerator is itself

```x
(Rational numerator 5)
```
---
    5

## denominator

### extracts denominator

```x
(Rational denominator 3/4)
```
---
    4

### integer denominator is one

```x
(Rational denominator 5)
```
---
    1

## value dispatch (the value calls its class, subject-last)

### numerator via the value

```x
(1/2 numerator)
```
---
    1

### denominator via the value

```x
(3/4 denominator)
```
---
    4

### predicate via the value

```x
(1/3 rational?)
```
---
    #t

### commutative op reads naturally (the receiver is appended last)

```x
(1/2 + 1/3)
```
---
    5/6

### a non-commutative op is subject-last too ((1/2 - 1/3) -> (- 1/3 1/2))

```x
(1/2 - 1/3)
```
---
    -1/6

### unknown method errors

```x
(guard (e "no-such") (1/2 bogus))
```
---
    "no-such"

## value dispatch does not break data lists (regression)

### iterate a list of rationals (re-evaluated data list must pass through)

```x
(Iter ->list (Iter new (list 1/2 1/3 1/4)))
```
---
    (1/2 1/3 1/4)

### a single-element rational list iterates

```x
(Iter ->list (Iter new (list 3/4)))
```
---
    (3/4)

## modulo

### % is truncating, matching int % and float fmod

```x
(% 7/2 1)
```
---
    1/2

### mixed int and rational operands

```x
(% 5 3/2)
```
---
    1/2

## large components promote instead of wrapping (regression)

### coprime 1e13 denominators add exactly

```x
(+ 1/10000000000000 1/9999999999999)
```
---
    19999999999999/99999999999990000000000000

### large-denominator difference demotes to the integer

```x
(- 30000000000001/10000000000000 1/10000000000000)
```
---
    3

### sqrt-2 digit pipeline stays exact

```x
(+ (* (- (/ 14142135623731 10000000000000) 1) 100000) 1/2)
```
---
    4142185623731/100000000

### 11-digit denominator literal reads

```x
1/99999999999
```
---
    1/99999999999

### comparison crosses promote

```x
(< 1/10000000000000 1/9999999999999)
```
---
    #t

### equality crosses promote

```x
(= 20000000000000/10000000000000 2)
```
---
    #t
