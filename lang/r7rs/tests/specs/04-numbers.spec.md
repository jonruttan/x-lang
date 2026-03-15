## number predicates

### number? on integer

```scheme
(number? 42)
```
---
    #t

### number? on non-number

```scheme
(not (number? "42"))
```
---
    #t

### integer? on integer

```scheme
(integer? 42)
```
---
    #t

### exact-integer? on integer

```scheme
(exact-integer? 42)
```
---
    #t

### exact? on integer

```scheme
(exact? 42)
```
---
    #t

### null? inexact? on integer

```scheme
(not (inexact? 42))
```
---
    #t

### zero? true

```scheme
(zero? 0)
```
---
    #t

### zero? false

```scheme
(not (zero? 1))
```
---
    #t

### positive? true

```scheme
(positive? 1)
```
---
    #t

### negative? true

```scheme
(negative? (- 0 1))
```
---
    #t

### odd? true

```scheme
(odd? 3)
```
---
    #t

### even? true

```scheme
(even? 4)
```
---
    #t

### odd? false

```scheme
(not (odd? 4))
```
---
    #t

### even? false

```scheme
(not (even? 3))
```
---
    #t

## float predicates

### number? on float

```scheme
(number? 3.14)
```
---
    #t

### real? on float

```scheme
(real? 3.14)
```
---
    #t

### real? on integer

```scheme
(real? 42)
```
---
    #t

### complex? on float

```scheme
(complex? 3.14)
```
---
    #t

### complex? on integer

```scheme
(complex? 42)
```
---
    #t

### integer? on inexact integer

```scheme
(integer? 3.0)
```
---
    #t

### integer? on non-integer float

```scheme
(not (integer? 3.5))
```
---
    #t

### exact? on float is false

```scheme
(not (exact? 3.14))
```
---
    #t

### inexact? on float

```scheme
(inexact? 3.14)
```
---
    #t

### exact-integer? on float is false

```scheme
(not (exact-integer? 3.0))
```
---
    #t

### rational? on integer

```scheme
(rational? 42)
```
---
    #t

### rational? on float is false

```scheme
(not (rational? 3.14))
```
---
    #t

### float? on float

```scheme
(float? 3.14)
```
---
    #t

### float? on integer is false

```scheme
(not (float? 42))
```
---
    #t

## IEEE 754 predicates

### nan? on NaN

```scheme
(nan? (/ 0.0 0.0))
```
---
    #t

### nan? on regular float

```scheme
(not (nan? 3.14))
```
---
    #t

### nan? on integer

```scheme
(not (nan? 42))
```
---
    #t

### infinite? on positive infinity

```scheme
(infinite? (/ 1.0 0.0))
```
---
    #t

### infinite? on negative infinity

```scheme
(infinite? (/ (- 0 1.0) 0.0))
```
---
    #t

### infinite? on regular float

```scheme
(not (infinite? 3.14))
```
---
    #t

### finite? on regular float

```scheme
(finite? 3.14)
```
---
    #t

### finite? on integer

```scheme
(finite? 42)
```
---
    #t

### finite? on NaN

```scheme
(not (finite? (/ 0.0 0.0)))
```
---
    #t

### finite? on infinity

```scheme
(not (finite? (/ 1.0 0.0)))
```
---
    #t

## arithmetic

### addition

```scheme
(+ 3 4)
```
---
    7

### addition multiple

```scheme
(+ 1 2 3 4)
```
---
    10

### subtraction

```scheme
(- 10 3)
```
---
    7

### multiplication

```scheme
(* 2 3 4)
```
---
    24

### integer division

```scheme
(/ 10 3)
```
---
    3

### nested arithmetic

```scheme
(+ (* 2 3) (- 10 4))
```
---
    12

### abs positive

```scheme
(abs 7)
```
---
    7

### abs negative

```scheme
(abs (- 0 7))
```
---
    7

### max

```scheme
(max 3 4)
```
---
    4

### min

```scheme
(min 3 4)
```
---
    3

### square

```scheme
(square 5)
```
---
    25

### square negative

```scheme
(square (- 0 3))
```
---
    9

## float arithmetic

### float addition

```scheme
(number->string (+ 1.5 2.5))
```
---
    "4"

### float subtraction

```scheme
(number->string (- 5.5 2.0))
```
---
    "3.5"

### float multiplication

```scheme
(number->string (* 2.5 4.0))
```
---
    "10"

### float division

```scheme
(number->string (/ 7.0 2.0))
```
---
    "3.5"

### mixed int+float addition

```scheme
(float? (+ 1 2.5))
```
---
    #t

### mixed int+float result

```scheme
(number->string (+ 1 2.5))
```
---
    "3.5"

### mixed subtraction

```scheme
(number->string (- 10 2.5))
```
---
    "7.5"

### mixed multiplication

```scheme
(number->string (* 3 2.5))
```
---
    "7.5"

### exactness contagion: int+float is float

```scheme
(inexact? (+ 1 2.0))
```
---
    #t

### unary negation of float

```scheme
(number->string (- 3.5))
```
---
    "-3.5"

## float math functions

### abs on negative float

```scheme
(number->string (abs (- 0 2.5)))
```
---
    "2.5"

### abs on positive float

```scheme
(number->string (abs 2.5))
```
---
    "2.5"

### zero? on 0.0

```scheme
(zero? 0.0)
```
---
    #t

### zero? on non-zero float

```scheme
(not (zero? 0.1))
```
---
    #t

### positive? on positive float

```scheme
(positive? 3.14)
```
---
    #t

### positive? on negative float

```scheme
(not (positive? (- 0 3.14)))
```
---
    #t

### negative? on negative float

```scheme
(negative? (- 0 3.14))
```
---
    #t

### min with mixed types

```scheme
(= (min 5 2.5) 2.5)
```
---
    #t

### max with mixed types

```scheme
(= (max 1 2.5) 2.5)
```
---
    #t

### square on float

```scheme
(number->string (square 2.5))
```
---
    "6.25"

## mixed comparisons

### int = float (equal values)

```scheme
(= 3 3.0)
```
---
    #t

### int = float (unequal)

```scheme
(not (= 3 3.5))
```
---
    #t

### int < float

```scheme
(< 1 2.5)
```
---
    #t

### float < int

```scheme
(< 0.5 1)
```
---
    #t

### int > float

```scheme
(> 3 2.5)
```
---
    #t

### int <= float (equal)

```scheme
(<= 3 3.0)
```
---
    #t

### int >= float

```scheme
(>= 3 2.5)
```
---
    #t

### float <= float

```scheme
(<= 2.5 3.0)
```
---
    #t

## quotient and remainder

### quotient positive

```scheme
(quotient 10 3)
```
---
    3

### remainder positive

```scheme
(remainder 10 3)
```
---
    1

### modulo positive

```scheme
(modulo 10 3)
```
---
    1

### truncate-quotient

```scheme
(truncate-quotient 10 3)
```
---
    3

### truncate-remainder

```scheme
(truncate-remainder 10 3)
```
---
    1

### floor-quotient positive

```scheme
(floor-quotient 7 2)
```
---
    3

### floor-remainder positive

```scheme
(floor-remainder 7 2)
```
---
    1

### floor-quotient negative dividend

```scheme
(floor-quotient (- 0 7) 2)
```
---
    -4

### floor-remainder negative dividend

```scheme
(floor-remainder (- 0 7) 2)
```
---
    1

## gcd and lcm

### gcd of two numbers

```scheme
(gcd 12 8)
```
---
    4

### gcd with zero

```scheme
(gcd 5 0)
```
---
    5

### lcm of two numbers

```scheme
(lcm 4 6)
```
---
    12

### lcm with zero

```scheme
(lcm 0 5)
```
---
    0

## rounding

### floor of positive float

```scheme
(floor 3.7)
```
---
    3

### floor of negative float

```scheme
(floor (- 0 3.3))
```
---
    -4

### floor of integer

```scheme
(floor 5)
```
---
    5

### floor returns exact

```scheme
(exact? (floor 3.7))
```
---
    #t

### ceiling of positive float

```scheme
(ceiling 3.2)
```
---
    4

### ceiling of negative float

```scheme
(ceiling (- 0 3.7))
```
---
    -3

### ceiling of integer

```scheme
(ceiling 5)
```
---
    5

### ceiling returns exact

```scheme
(exact? (ceiling 3.2))
```
---
    #t

### truncate of positive float

```scheme
(truncate 3.7)
```
---
    3

### truncate of negative float

```scheme
(truncate (- 0 3.7))
```
---
    -3

### truncate of integer

```scheme
(truncate 5)
```
---
    5

### round of 3.5

```scheme
(round 3.5)
```
---
    4

### round of 2.5

```scheme
(round 2.5)
```
---
    2

### round of 3.2

```scheme
(round 3.2)
```
---
    3

### round of negative

```scheme
(round (- 0 3.7))
```
---
    -4

### round returns exact

```scheme
(exact? (round 3.7))
```
---
    #t

## sqrt

### sqrt of perfect square

```scheme
(sqrt 9)
```
---
    3

### sqrt of perfect square returns exact

```scheme
(exact? (sqrt 9))
```
---
    #t

### sqrt of 25

```scheme
(sqrt 25)
```
---
    5

### sqrt of non-perfect square returns float

```scheme
(inexact? (sqrt 2))
```
---
    #t

### sqrt of non-perfect square value

```scheme
(> (sqrt 2) 1.4)
```
---
    #t

### sqrt of zero

```scheme
(sqrt 0)
```
---
    0

### sqrt of float

```scheme
(number->string (sqrt 2.0))
```
---
    "1.4142135623731"

## expt

### expt basic

```scheme
(expt 2 10)
```
---
    1024

### expt zero power

```scheme
(expt 5 0)
```
---
    1

### expt power of one

```scheme
(expt 7 1)
```
---
    7

### expt with float base

```scheme
(number->string (expt 2.0 3.0))
```
---
    "8"

### expt with float returns float

```scheme
(inexact? (expt 2.0 3.0))
```
---
    #t

### expt integer result stays exact

```scheme
(exact? (expt 2 10))
```
---
    #t

## exact/inexact conversion

### inexact converts int to float

```scheme
(inexact? (inexact 42))
```
---
    #t

### inexact value

```scheme
(= (inexact 42) 42.0)
```
---
    #t

### exact converts float to int

```scheme
(exact? (exact 3.0))
```
---
    #t

### exact value

```scheme
(= (exact 3.0) 3)
```
---
    #t

### exact->inexact converts int to float

```scheme
(inexact? (exact->inexact 5))
```
---
    #t

### inexact->exact converts float to int

```scheme
(exact? (inexact->exact 5.0))
```
---
    #t

## comparison

### equal numbers

```scheme
(= 5 5)
```
---
    #t

### not equal

```scheme
(not (= 5 6))
```
---
    #t

### less than

```scheme
(< 1 2)
```
---
    #t

### greater than

```scheme
(> 2 1)
```
---
    #t

### less or equal

```scheme
(<= 2 2)
```
---
    #t

### greater or equal

```scheme
(>= 3 2)
```
---
    #t

## string/number conversion

### number->string integer

```scheme
(number->string 42)
```
---
    "42"

### string->number integer

```scheme
(string->number "42")
```
---
    42

### number->string float

```scheme
(number->string 3.14)
```
---
    "3.14"

### string->number float

```scheme
(number->string (string->number "3.14"))
```
---
    "3.14"

### string->number returns float for dotted

```scheme
(inexact? (string->number "3.14"))
```
---
    #t

### string->number returns int for non-dotted

```scheme
(exact? (string->number "42"))
```
---
    #t

### number->string negative

```scheme
(number->string (- 0 7))
```
---
    "-7"

### number->string negative float

```scheme
(number->string (- 0 3.14))
```
---
    "-3.14"

