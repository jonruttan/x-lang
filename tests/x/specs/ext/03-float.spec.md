# @lib x-base.x

## float literals

### parses simple float

```scheme
3.14
```
---
    3.14

### parses integer-like float

```scheme
1.0
```
---
    1

### parses small float

```scheme
0.5
```
---
    0.5

### parses large float

```scheme
12345.6789
```
---
    12345.6789

### float? true for float

```scheme
(float? 3.14)
```
---
    #t

### float? false for integer

```scheme
(float? 42)
```
---
    #f

### float? false for string

```scheme
(float? "3.14")
```
---
    #f

## type convert handler

### convert int to float

```scheme
(convert 42 %float)
```
---
    42

### convert result is float

```scheme
(float? (convert 42 %float))
```
---
    #t

### convert float to float is identity

```scheme
(def x 3.14) (eq? (convert x %float) x)
```
---
    #t

### convert string to float

```scheme
(float? (convert "3.14" %float))
```
---
    #t

### convert nil returns nil

```scheme
(null? (convert () %float))
```
---
    #t

### convert negative int

```scheme
(convert -5 %float)
```
---
    -5

### convert zero

```scheme
(convert 0 %float)
```
---
    0

## float conversions

### exact->inexact converts int

```scheme
(exact->inexact 5)
```
---
    5

### exact->inexact result is float

```scheme
(float? (exact->inexact 5))
```
---
    #t

### exact->inexact float identity

```scheme
(def x 3.14) (eq? (exact->inexact x) x)
```
---
    #t

### inexact->exact truncates

```scheme
(inexact->exact 3.14)
```
---
    3

### inexact->exact rounds toward zero

```scheme
(inexact->exact 9.99)
```
---
    9

### string->float and back

```scheme
(float->string (string->float "2.718"))
```
---
    "2.718"

### int->float and back

```scheme
(float->int (int->float 42))
```
---
    42

## float arithmetic (f+ f- f* f/)

### f+ addition

```scheme
(f+ 1.5 2.5)
```
---
    4

### f- subtraction

```scheme
(f- 10.0 3.5)
```
---
    6.5

### f* multiplication

```scheme
(f* 3.0 4.0)
```
---
    12

### f/ division

```scheme
(f/ 10.0 4.0)
```
---
    2.5

### f/ non-integer result

```scheme
(f/ 1.0 3.0)
```
---
    0.333333333333333

## generic arithmetic with floats

### + two floats

```scheme
(+ 1.5 2.5)
```
---
    4

### + int and float

```scheme
(+ 1 2.5)
```
---
    3.5

### + float and int

```scheme
(+ 2.5 1)
```
---
    3.5

### + three with float

```scheme
(+ 1 2 3.0)
```
---
    6

### - two floats

```scheme
(- 10.0 3.5)
```
---
    6.5

### - negate float

```scheme
(- 3.14)
```
---
    -3.14

### * two floats

```scheme
(* 3.0 4.0)
```
---
    12

### * int and float

```scheme
(* 2 3.5)
```
---
    7

### / two floats

```scheme
(/ 10.0 4.0)
```
---
    2.5

### / int and float

```scheme
(/ 7 2.0)
```
---
    3.5

### + integers unchanged

```scheme
(+ 1 2 3)
```
---
    6

### * integers unchanged

```scheme
(* 2 3 4)
```
---
    24

## float comparisons

### f< true

```scheme
(f< 1.5 2.5)
```
---
    #t

### f< false

```scheme
(f< 2.5 1.5)
```
---
    #f

### f= true

```scheme
(f= 1.0 1.0)
```
---
    #t

### f= false

```scheme
(f= 1.0 2.0)
```
---
    #f

## generic comparisons with floats

### < with floats

```scheme
(< 1.5 2.5)
```
---
    #t

### > with floats

```scheme
(> 3.0 2.0)
```
---
    #t

### = with floats

```scheme
(= 1.0 1.0)
```
---
    #t

### <= with floats

```scheme
(<= 2.0 2.0)
```
---
    #t

### >= with floats

```scheme
(>= 3.0 2.0)
```
---
    #t

### < int and float

```scheme
(< 1 2.5)
```
---
    #t

### > float and int

```scheme
(> 3.5 2)
```
---
    #t

### = int and float

```scheme
(= 2 2.0)
```
---
    #t

### < integers still work

```scheme
(< 1 2)
```
---
    #t

### = integers still work

```scheme
(= 5 5)
```
---
    #t

## math functions

### fsin of 0

```scheme
(fsin (exact->inexact 0))
```
---
    0

### fcos of 0

```scheme
(fcos (exact->inexact 0))
```
---
    1

### fsqrt of 4

```scheme
(fsqrt 4.0)
```
---
    2

### fsqrt of 2

```scheme
(fsqrt 2.0)
```
---
    1.4142135623731

### fabs positive

```scheme
(fabs 3.14)
```
---
    3.14

### fabs negative

```scheme
(fabs (- 3.14))
```
---
    3.14

### ffloor

```scheme
(ffloor 3.7)
```
---
    3

### fceil

```scheme
(fceil 3.2)
```
---
    4

### fround

```scheme
(fround 3.5)
```
---
    4

### fexp of 0

```scheme
(fexp (exact->inexact 0))
```
---
    1

### flog of 1

```scheme
(flog 1.0)
```
---
    0

### fpow 2^10

```scheme
(fpow 2.0 10.0)
```
---
    1024

## float constants

### pi is approximately 3.14159

```scheme
(> %pi 3.14)
```
---
    #t

### pi is approximately 3.14159 upper

```scheme
(< %pi 3.15)
```
---
    #t

### e is approximately 2.71828

```scheme
(> %e 2.71)
```
---
    #t

### e is approximately 2.71828 upper

```scheme
(< %e 2.72)
```
---
    #t

## float predicates

### number? true for integer

```scheme
(number? 42)
```
---
    #t

### number? true for float

```scheme
(number? 3.14)
```
---
    #t

### number? false for string

```scheme
(number? "hello")
```
---
    #f

### integer? true for int

```scheme
(integer? 42)
```
---
    #t

### integer? false for float

```scheme
(integer? 3.14)
```
---
    #f

### float? true for float

```scheme
(float? 3.14)
```
---
    #t

### float? false for int

```scheme
(float? 42)
```
---
    #f

### inexact? true for float

```scheme
(inexact? 3.14)
```
---
    #t

### inexact? false for int

```scheme
(inexact? 42)
```
---
    #f

## float in data structures

### float in list

```scheme
(list 1.5 2.5 3.5)
```
---
    (1.5 2.5 3.5)

### float in pair

```scheme
(pair 1.5 2.5)
```
---
    (1.5 . 2.5)

### float in variable

```scheme
(def x 3.14) x
```
---
    3.14

### map with floats

```scheme
(map (fn (_ x) (* x 2.0)) (list 1.0 2.0 3.0))
```
---
    (2 4 6)

### filter with floats

```scheme
(filter (fn (_ x) (> x 2.0)) (list 1.0 2.5 3.0 0.5))
```
---
    (2.5 3)

### fold with floats

```scheme
(fold + 0.0 (list 1.0 2.0 3.0))
```
---
    6

### float in vector

```scheme
(vector 1.5 2.5 3.5)
```
---
    #(1.5 2.5 3.5)

## float edge cases

### very small float

```scheme
(> 0.001 (exact->inexact 0))
```
---
    #t

### negative float

```scheme
(- 3.14)
```
---
    -3.14

### float zero

```scheme
(f= 0.0 (exact->inexact 0))
```
---
    #t

### mixed arithmetic chain

```scheme
(+ (* 2.0 3.0) (/ 10.0 5.0))
```
---
    8

