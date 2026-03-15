## set-car!/set-cdr!

### set-car! mutates pair

```scheme
(define p (cons 1 2))
(set-car! p 3)
(car p)
```
---
    3

### set-cdr! mutates pair

```scheme
(define p (cons 1 2))
(set-cdr! p 3)
(cdr p)
```
---
    3

## variadic comparisons

### = with multiple args (true)

```scheme
(= 1 1 1 1)
```
---
    #t

### = with multiple args (false)

```scheme
(not (= 1 1 2 1))
```
---
    #t

### < with multiple args

```scheme
(< 1 2 3 4)
```
---
    #t

### < not strictly increasing

```scheme
(not (< 1 2 2 3))
```
---
    #t

### > with multiple args

```scheme
(> 4 3 2 1)
```
---
    #t

### <= with equal elements

```scheme
(<= 1 1 2 3 3)
```
---
    #t

### >= with equal elements

```scheme
(>= 5 3 3 1)
```
---
    #t

### = with single arg

```scheme
(= 42)
```
---
    #t

### < with two args

```scheme
(< 1 2)
```
---
    #t

## variadic min/max

### max with multiple args

```scheme
(max 3 1 4 1 5 9)
```
---
    9

### min with multiple args

```scheme
(min 3 1 4 1 5 9)
```
---
    1

### max with single arg

```scheme
(max 42)
```
---
    42

## variadic gcd/lcm

### gcd with two args

```scheme
(gcd 12 8)
```
---
    4

### gcd with three args

```scheme
(gcd 12 8 6)
```
---
    2

### gcd with no args

```scheme
(gcd)
```
---
    0

### gcd with single arg

```scheme
(gcd 42)
```
---
    42

### gcd with negative

```scheme
(gcd -12 8)
```
---
    4

### lcm with two args

```scheme
(lcm 4 6)
```
---
    12

### lcm with three args

```scheme
(lcm 4 6 10)
```
---
    60

### lcm with no args

```scheme
(lcm)
```
---
    1

### lcm with zero

```scheme
(lcm 5 0)
```
---
    0

## values and call-with-values

### single value pass-through

```scheme
(values 42)
```
---
    42

### call-with-values basic

```scheme
(call-with-values (lambda () (values 1 2)) +)
```
---
    3

### call-with-values single value

```scheme
(call-with-values (lambda () 5) (lambda (x) (* x x)))
```
---
    25

## write-char

### write-char outputs character

```scheme
(write-char #\A)
```
---
    A

## number predicates

### exact? on integer

```scheme
(exact? 42)
```
---
    #t

### inexact? on float

```scheme
(inexact? (exact->inexact 1))
```
---
    #t

### exact? on float

```scheme
(not (exact? (exact->inexact 1)))
```
---
    #t

### real? on integer

```scheme
(real? 42)
```
---
    #t

### complex? on integer

```scheme
(complex? 42)
```
---
    #t

## R5RS math with floats

### floor of positive float

```scheme
(floor (exact->inexact 3))
```
---
    3

### ceiling of positive float

```scheme
(ceiling (inexact->exact (exact->inexact 4)))
```
---
    4

### sqrt of perfect square

```scheme
(sqrt 25)
```
---
    5

### sqrt of non-perfect square is float

```scheme
(inexact? (sqrt 2))
```
---
    #t

### sin of zero

```scheme
(display (sin 0))
```
---
    0

### cos of zero

```scheme
(display (cos 0))
```
---
    1

### exp of zero

```scheme
(display (exp 0))
```
---
    1

### log of e

```scheme
(display (log (exp 1)))
```
---
    1

### atan with one arg

```scheme
(inexact? (atan 1))
```
---
    #t

### atan with two args

```scheme
(inexact? (atan 1 1))
```
---
    #t

### expt with float exponent

```scheme
(inexact? (expt 2 (exact->inexact 3)))
```
---
    #t

## number->string and string->number

### number->string integer

```scheme
(number->string 42)
```
---
    "42"

### number->string float

```scheme
(display (number->string (exact->inexact 3)))
```
---
    3

### string->number valid integer

```scheme
(string->number "42")
```
---
    42

### string->number invalid returns false

```scheme
(not (string->number "abc"))
```
---
    #t

### string->number float

```scheme
(inexact? (string->number "3.14"))
```
---
    #t

### string->number empty returns false

```scheme
(not (string->number ""))
```
---
    #t

## letrec-syntax

### basic letrec-syntax

```scheme
(letrec-syntax
  ((double (syntax-rules ()
             ((_ x) (+ x x)))))
  (double 5))
```
---
    10

### letrec-syntax with mutual reference

```scheme
(letrec-syntax
  ((add1 (syntax-rules () ((_ x) (+ x 1))))
   (add2 (syntax-rules () ((_ x) (+ x 2)))))
  (+ (add1 10) (add2 20)))
```
---
    33
