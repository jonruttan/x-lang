# @lib ../tests/x/lib/decimal.x
# @weight 12

Arbitrary-precision decimal floating-point (`x/num/decimal`): a significand
that grows without bound times a power of ten, so the digits a decimal
fraction is written with are the digits it keeps. `+ - *` are exact; `/` and
`sqrt` round half-even to `(Decimal precision)`.

## decimal literals

### parses a simple decimal

```scheme
1.5d
```
---
    1.5d

### parses a negative decimal

```scheme
-0.001d
```
---
    -0.001d

### parses an integer-shaped decimal

```scheme
3d
```
---
    3d

### parses an exponent form

```scheme
1.5e3d
```
---
    1500d

### parses a negative exponent

```scheme
2.5e-4d
```
---
    0.00025d

### the suffix is what claims the token: without it a float still reads

```scheme
(Float float? 1.5)
```
---
    #t

### with it a decimal wins the same digits

```scheme
(Decimal decimal? 1.5d)
```
---
    #t

### a lone sign is still the operator

```scheme
(- 5d 2d)
```
---
    3d

## canonical storage

### trailing zeros are stripped, so one value has one spelling

```scheme
(Decimal = 1.50d 1.5d)
```
---
    #t

### and print alike

```scheme
1.500d
```
---
    1.5d

### zero has one form

```scheme
(Decimal = 0d (- 1.5d 1.5d))
```
---
    #t

### the significand is the stripped one

```scheme
(Decimal significand 1.500d)
```
---
    15

### paired with its exponent

```scheme
(Decimal exponent 1.500d)
```
---
    -1

### (Decimal make) builds from the pair directly

```scheme
(Decimal ->str (Decimal make 125 -2))
```
---
    "1.25"

## exact arithmetic

### the decimal fraction addition a double cannot do

```scheme
(+ 0.1d 0.2d)
```
---
    0.3d

### the same sum in doubles is not 0.3

```scheme
(Float = (+ 0.1 0.2) 0.3)
```
---
    #f

### subtraction is exact too

```scheme
(- 1d 0.9d)
```
---
    0.1d

### multiplication keeps every digit

```scheme
(* 1.5d 1.5d)
```
---
    2.25d

### and grows the significand past the machine word

```scheme
(* 99999999999999999999d 99999999999999999999d)
```
---
    9999999999999999999800000000000000000001d

### a hundred additions of a tenth land exactly on ten

```scheme
(let ((go (fn (self n acc) (if (= n 0) acc (self (- n 1) (+ acc 0.1d))))))
  (Decimal = (go 100 0d) 10d))
```
---
    #t

## division rounds

### a terminating quotient is exact

```scheme
(/ 1d 8d)
```
---
    0.125d

### a repeating one rounds to the precision

```scheme
(/ 1d 3d)
```
---
    0.3333333333333333333333333333333333d

### the default precision is decimal128's coefficient width

```scheme
(Decimal precision)
```
---
    34

### the precision is a knob

```scheme
(do (Decimal precision! 10)
    (let ((q (/ 1d 3d))) (do (Decimal precision! 34) q)))
```
---
    0.3333333333d

### rounding is half-even: a tie goes to the even digit

```scheme
(do (Decimal precision! 2)
    (let ((q (/ 25d 100d))) (do (Decimal precision! 34) q)))
```
---
    0.25d

### dividing by zero is a raise, not a trap

```scheme
(guard (e 'raised) (/ 1d 0d))
```
---
    'raised

### zero divided by anything is zero

```scheme
(/ 0d 7d)
```
---
    0d

## remainder

### truncating, like int % and float fmod

```scheme
(% 7.5d 2d)
```
---
    1.5d

### the sign follows the dividend

```scheme
(% -7.5d 2d)
```
---
    -1.5d

### a negative divisor does not change that

```scheme
(% 7.5d -2d)
```
---
    1.5d

### and the division identity holds

```scheme
(let ((a 22.75d) (b 3.5d))
  (Decimal = a (+ (* b (Decimal trunc (/ a b))) (% a b))))
```
---
    #t

## comparison

### ordering

```scheme
(< 1.5d 1.6d)
```
---
    #t

### across wildly different scales, without scaling anything

```scheme
(< 1e-1000d 1e1000d)
```
---
    #t

### negatives order the other way

```scheme
(< -2d -1d)
```
---
    #t

### three-way compare

```scheme
(Decimal compare 2d 1d)
```
---
    1

### equality is value equality

```scheme
(= 2.50d 2.5d)
```
---
    #t

## conversion

### a double widens EXACTLY -- this is 0.1's true value, not its short form

```scheme
(Decimal ->str (Decimal from 0.1))
```
---
    "0.1000000000000000055511151231257827021181583404541015625"

### and converts back to the same double

```scheme
(Float = 0.1 (Decimal ->float (Decimal from 0.1)))
```
---
    #t

### from a numeric string

```scheme
(Decimal ->str (Decimal from "1.25"))
```
---
    "1.25"

### from a bigint, with no limb walk in between

```scheme
(Decimal ->str (Decimal from (* 99999999999 99999999999)))
```
---
    "9999999999800000000001"

### garbage text is a raise, not a zero

```scheme
(guard (e 'raised) (Decimal from "abc"))
```
---
    'raised

### and so is a half-written number

```scheme
(guard (e 'raised) (Decimal from "1e"))
```
---
    'raised

### a point with nothing after it is still a number

```scheme
(Decimal ->str (Decimal from "12."))
```
---
    "12"

### so is one with nothing before it

```scheme
(Decimal ->str (Decimal from ".5"))
```
---
    "0.5"

### a rational rounds -- 1/3 has no finite decimal

```scheme
(Decimal ->str (Decimal from 1/4))
```
---
    "0.25"

### ->int truncates toward zero

```scheme
(Decimal ->int -2.9d)
```
---
    -2

### ->str drops the suffix that `write` adds for round-tripping

```scheme
(Decimal ->str 1.5d)
```
---
    "1.5"

### a value too spread out to spell positionally prints scientific

```scheme
1e25d
```
---
    1e25d

### and re-reads as itself

```scheme
(= 1e25d (Decimal make 1 25))
```
---
    #t

## rounding and integral parts

### round to decimal places, half-even

```scheme
(Decimal ->str (Decimal round 2.675d 2))
```
---
    "2.68"

### an exact tie at an even digit stays put

```scheme
(Decimal ->str (Decimal round 2.665d 2))
```
---
    "2.66"

### negative places round to tens, hundreds, ...

```scheme
(Decimal ->str (Decimal round 1250d -2))
```
---
    "1200"

### floor goes down

```scheme
(Decimal floor -1.5d)
```
---
    -2d

### ceil goes up

```scheme
(Decimal ceil -1.5d)
```
---
    -1d

### trunc goes toward zero

```scheme
(Decimal trunc -1.9d)
```
---
    -1d

## roots and powers

### sqrt to the current precision

```scheme
(Decimal sqrt 2d)
```
---
    1.414213562373095048801688724209698d

### an exact root comes back exact

```scheme
(Decimal sqrt 2.25d)
```
---
    1.5d

### squaring the root gets back to the value

```scheme
(let ((r (Decimal sqrt 9d))) (Decimal = 9d (* r r)))
```
---
    #t

### a negative has no real root

```scheme
(guard (e 'raised) (Decimal sqrt -1d))
```
---
    'raised

### an integer power is exact

```scheme
(Decimal pow 1.1d 10)
```
---
    2.5937424601d

### a negative power divides once

```scheme
(Decimal pow 2d -2)
```
---
    0.25d

## logarithms and the exponential

Series, not libm -- there is no C double wide enough to borrow from. Most of
these run at a lower precision on purpose: the algorithm is the same at 12
digits as at 34, and the suite is not the place to pay for 34.

### e, to the full default precision

```scheme
(Decimal exp 1d)
```
---
    2.718281828459045235360287471352662d

### ln 2, likewise -- both agree with the published constants to the last digit

```scheme
(Decimal ln 2d)
```
---
    0.6931471805599453094172321214581766d

### exp of zero is exactly one

```scheme
(Decimal exp 0d)
```
---
    1d

### and ln of one is exactly zero

```scheme
(Decimal ln 1d)
```
---
    0d

### the exponential at a lower precision

```scheme
(do (Decimal precision! 12)
    (let ((v (Decimal exp 2d))) (do (Decimal precision! 34) v)))
```
---
    7.38905609893d

### a negative exponent

```scheme
(do (Decimal precision! 12)
    (let ((v (Decimal exp -1d))) (do (Decimal precision! 34) v)))
```
---
    0.367879441171d

### ln 10, the constant the exponent rides on

```scheme
(do (Decimal precision! 12)
    (let ((v (Decimal ln 10d))) (do (Decimal precision! 34) v)))
```
---
    2.30258509299d

### an argument below one

```scheme
(do (Decimal precision! 12)
    (let ((v (Decimal ln 0.5d))) (do (Decimal precision! 34) v)))
```
---
    -0.69314718056d

### ln of e is one, round-tripped

```scheme
(do (Decimal precision! 12)
    (let ((v (Decimal ln (Decimal exp 1d)))) (do (Decimal precision! 34) v)))
```
---
    1d

### log10

```scheme
(do (Decimal precision! 12)
    (let ((v (Decimal log10 2d))) (do (Decimal precision! 34) v)))
```
---
    0.301029995664d

### an exact power of ten answers exactly, at any precision

```scheme
(Decimal log10 1000d)
```
---
    3d

### including a negative one

```scheme
(Decimal log10 0.00001d)
```
---
    -5d

### an argument near one keeps its digits -- no cancellation against ln 10

```scheme
(Decimal ln 1.000000000000000000001d)
```
---
    9.999999999999999999995e-22d

### other numerics coerce

```scheme
(do (Decimal precision! 12)
    (let ((v (Decimal ln 2.0))) (do (Decimal precision! 34) v)))
```
---
    0.69314718056d

### the logarithm of zero is a raise

```scheme
(guard (e 'raised) (Decimal ln 0d))
```
---
    'raised

### and so is the logarithm of a negative

```scheme
(guard (e 'raised) (Decimal log10 -1d))
```
---
    'raised

## predicates

### decimals are numbers

```scheme
(number? 1.5d)
```
---
    #t

### and real ones

```scheme
(real? 1.5d)
```
---
    #t

### zero?

```scheme
(Decimal zero? 0d)
```
---
    #t

### a float is not a decimal

```scheme
(Decimal decimal? 1.5)
```
---
    #f

### value dispatch is subject-last

```scheme
(1.5d decimal?)
```
---
    #t

## mixed operands

### an int coerces

```scheme
(+ 1 0.5d)
```
---
    1.5d

### either way round

```scheme
(- 1 1.5d)
```
---
    -0.5d

### a bigint coerces

```scheme
(+ 99999999999999999999 0.5d)
```
---
    99999999999999999999.5d

### a float coerces, exactly

```scheme
(* 2d 3.5)
```
---
    7d

### a rational coerces

```scheme
(+ 1/2 0.25d)
```
---
    0.75d

### complex still absorbs the decimal

```scheme
(Complex complex? (+ 1+2i 0.5d))
```
---
    #t

### and the real part carries the decimal through

```scheme
(Decimal = 1.5d (Complex real-part (+ 1+2i 0.5d)))
```
---
    #t

### a value that converts to nothing numeric is a raise

```scheme
(guard (e 'raised) (Decimal + 'sym 1d))
```
---
    'raised

## context

### precision must be at least one digit

```scheme
(guard (e 'raised) (Decimal precision! 0))
```
---
    'raised

### and the setter answers the new precision

```scheme
(do (Decimal precision! 12)
    (let ((p (Decimal precision))) (do (Decimal precision! 34) p)))
```
---
    12
