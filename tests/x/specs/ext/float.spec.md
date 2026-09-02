# @lib ../tests/x/lib/float.x
# @weight 4

## float literals

### parses simple float

```x
3.14
```
---
    3.14

### parses integer-like float

```x
1.0
```
---
    1.0

### parses negative float

```x
-7.5
```
---
    -7.5

### parses small float

```x
0.5
```
---
    0.5

### parses large float

```x
12345.6789
```
---
    12345.6789

### float? true for float

```x
(Float float? 3.14)
```
---
    #t

### float? false for integer

```x
(Float float? 42)
```
---
    #f

### float? false for string

```x
(Float float? "3.14")
```
---
    #f

## type convert handler

### convert int to float

```x
(Convert to 42 %float)
```
---
    42.0

### convert result is float

```x
(Float float? (Convert to 42 %float))
```
---
    #t

### convert float to float is identity

```x
(def x 3.14) (eq? (Convert to x %float) x)
```
---
    #t

### convert string to float

```x
(Float float? (Convert to "3.14" %float))
```
---
    #t

### convert nil returns nil

```x
(null? (Convert to () %float))
```
---
    #t

### convert negative int

```x
(Convert to -5 %float)
```
---
    -5.0

### convert zero

```x
(Convert to 0 %float)
```
---
    0.0

## float conversions

### from converts int

```x
(Float from 5)
```
---
    5.0

### from result is float

```x
(Float float? (Float from 5))
```
---
    #t

### from float identity

```x
(def x 3.14) (eq? (Float from x) x)
```
---
    #t

### ->int truncates

```x
(Float ->int 3.14)
```
---
    3

### ->int rounds toward zero

```x
(Float ->int 9.99)
```
---
    9

### str->float and back

```x
(Float bits->str (Float str->bits "2.718"))
```
---
    "2.718"

### int->float and back

```x
(Float bits->int (Float int->bits 42))
```
---
    42

## float arithmetic (Float + f- f* f/)

### f+ addition

```x
(Float + 1.5 2.5)
```
---
    4.0

### f- subtraction

```x
(Float - 10.0 3.5)
```
---
    6.5

### f* multiplication

```x
(Float * 3.0 4.0)
```
---
    12.0

### f/ division

```x
(Float / 10.0 4.0)
```
---
    2.5

### f/ non-integer result

```x
(Float / 1.0 3.0)
```
---
    0.333333333333333

## generic arithmetic with floats

### + two floats

```x
(+ 1.5 2.5)
```
---
    4.0

### + int and float

```x
(+ 1 2.5)
```
---
    3.5

### + float and int

```x
(+ 2.5 1)
```
---
    3.5

### + three with float

```x
(+ 1 2 3.0)
```
---
    6.0

### - two floats

```x
(- 10.0 3.5)
```
---
    6.5

### - negate float

```x
(- 3.14)
```
---
    -3.14

### * two floats

```x
(* 3.0 4.0)
```
---
    12.0

### * int and float

```x
(* 2 3.5)
```
---
    7.0

### / two floats

```x
(/ 10.0 4.0)
```
---
    2.5

### / int and float

```x
(/ 7 2.0)
```
---
    3.5

### + integers unchanged

```x
(+ 1 2 3)
```
---
    6

### * integers unchanged

```x
(* 2 3 4)
```
---
    24

## % with floats (fmod)

### % smaller by larger is the dividend

```x
(% 1.2 1.4)
```
---
    1.2

### % larger by smaller

```x
(% 1.4 1.2)
```
---
    0.2

### % float by float

```x
(% 7.5 2.0)
```
---
    1.5

### % truncates toward zero (C semantics)

```x
(% -7.5 2.0)
```
---
    -1.5

### % float by int coerces

```x
(% 5.5 2)
```
---
    1.5

### % integers unchanged

```x
(% 7 3)
```
---
    1

## float comparisons

### f< true

```x
(Float < 1.5 2.5)
```
---
    #t

### f< false

```x
(Float < 2.5 1.5)
```
---
    #f

### f= true

```x
(Float = 1.0 1.0)
```
---
    #t

### f= false

```x
(Float = 1.0 2.0)
```
---
    #f

## generic comparisons with floats

### < with floats

```x
(< 1.5 2.5)
```
---
    #t

### > with floats

```x
(> 3.0 2.0)
```
---
    #t

### = with floats

```x
(= 1.0 1.0)
```
---
    #t

### <= with floats

```x
(<= 2.0 2.0)
```
---
    #t

### >= with floats

```x
(>= 3.0 2.0)
```
---
    #t

### < int and float

```x
(< 1 2.5)
```
---
    #t

### > float and int

```x
(> 3.5 2)
```
---
    #t

### = int and float

```x
(= 2 2.0)
```
---
    #t

### < integers still work

```x
(< 1 2)
```
---
    #t

### = integers still work

```x
(= 5 5)
```
---
    #t

## math functions

### fsin of 0

```x
(Float sin (Float from 0))
```
---
    0.0

### fcos of 0

```x
(Float cos (Float from 0))
```
---
    1.0

### fsqrt of 4

```x
(Float sqrt 4.0)
```
---
    2.0

### fsqrt of 2

```x
(Float sqrt 2.0)
```
---
    1.4142135623731

### fabs positive

```x
(Float abs 3.14)
```
---
    3.14

### fabs negative

```x
(Float abs (- 3.14))
```
---
    3.14

### ffloor

```x
(Float floor 3.7)
```
---
    3.0

### fceil

```x
(Float ceil 3.2)
```
---
    4.0

### fround

```x
(Float round 3.5)
```
---
    4.0

### fexp of 0

```x
(Float exp (Float from 0))
```
---
    1.0

### flog of 1

```x
(Float log 1.0)
```
---
    0.0

### fpow 2^10

```x
(Float pow 2.0 10.0)
```
---
    1024.0

## float constants

### pi is approximately 3.14159

```x
(> %pi 3.14)
```
---
    #t

### pi is approximately 3.14159 upper

```x
(< %pi 3.15)
```
---
    #t

### e is approximately 2.71828

```x
(> %e 2.71)
```
---
    #t

### e is approximately 2.71828 upper

```x
(< %e 2.72)
```
---
    #t

## float predicates

### number? true for integer

```x
(number? 42)
```
---
    #t

### number? true for float

```x
(number? 3.14)
```
---
    #t

### number? false for string

```x
(number? "hello")
```
---
    #f

### integer? true for int

```x
(Float integer? 42)
```
---
    #t

### integer? false for float

```x
(Float integer? 3.14)
```
---
    #f

### float? true for float

```x
(Float float? 3.14)
```
---
    #t

### float? false for int

```x
(Float float? 42)
```
---
    #f

### inexact? true for float

```x
(Float inexact? 3.14)
```
---
    #t

### inexact? false for int

```x
(Float inexact? 42)
```
---
    #f

## float in data structures

### float in list

```x
(list 1.5 2.5 3.5)
```
---
    (1.5 2.5 3.5)

### float in pair

```x
(pair 1.5 2.5)
```
---
    (1.5 . 2.5)

### float in variable

```x
(def x 3.14) x
```
---
    3.14

### map with floats

```x
(List map (fn (_ x) (* x 2.0)) (list 1.0 2.0 3.0))
```
---
    (2.0 4.0 6.0)

### filter with floats

```x
(List filter (fn (_ x) (> x 2.0)) (list 1.0 2.5 3.0 0.5))
```
---
    (2.5 3.0)

### fold with floats

```x
(List fold + 0.0 (list 1.0 2.0 3.0))
```
---
    6.0

### float in vector

```x
(Vector of 1.5 2.5 3.5)
```
---
    #(1.5 2.5 3.5)

## float edge cases

### very small float

```x
(> 0.001 (Float from 0))
```
---
    #t

### negative float

```x
(- 3.14)
```
---
    -3.14

### float zero

```x
(Float = 0.0 (Float from 0))
```
---
    #t

### mixed arithmetic chain

```x
(+ (* 2.0 3.0) (/ 10.0 5.0))
```
---
    8.0


## N5: count/index seats coerce through the tower

### a float count truncates via the registered converter

```x
(list (List take 2.75 (list 1 2 3 4)) (List ref 1.25 (list 10 20 30)))
```
---
    ((1 2) 20)

## floats keep their point (#45 R4)

### an int-valued float prints as a float

```x
(list 1.0 (Float / 4.0 2.0))
```
---
    (1.0 2.0)

## unconvertible operands raise (engine-crash class)

A conversion-catalog miss used to return silent nil, which reached the
unchecked `(first)`/FFI seats and segfaulted the engine. The door in
float.x raises instead; the Convert dispatcher's silent-nil miss policy
is unchanged.

### from on a list raises type, not silent nil

```x
(Float from (list 1))
```
---
    Error: #<err:type Float from: not convertible to FLOAT>

### a mixed op with an unconvertible operand raises type, not a crash

```x
(Float + 1.0 (list 1))
```
---
    Error: #<err:type Float: operand not convertible to FLOAT>

### ->int on a non-number raises type

```x
(Float ->int (list 1))
```
---
    Error: #<err:type Float ->int: not a float>

### ->int int passthrough keeps exact identity

```x
(Float ->int 5)
```
---
    5

### the Convert-level miss stays silent nil (policy unchanged)

```x
(null? (Convert to (list 1) %float))
```
---
    #t

## the math tail (#363)

### log2, log10, hypot

```x
(list (Float log2 8.0) (Float log10 1000.0) (Float hypot 3.0 4.0))
```
---
    (3.0 3.0 5.0)

### the constants: pi, e, tau; tau is 2*pi

```x
(list (Float pi) (Float e) (Float = (Float tau) (Float * 2.0 (Float pi))))
```
---
    (3.14159265358979 2.71828182845905 #t)

### nan? is #t only for a NaN float

```x
(list (Float nan? (/ 0.0 0.0)) (Float nan? (/ 1.0 0.0))
      (Float nan? 1.5) (Float nan? 42))
```
---
    (#t #f #f #f)

### inf? sees both signs, not NaN, not finite

```x
(list (Float inf? (/ 1.0 0.0)) (Float inf? (/ -1.0 0.0))
      (Float inf? (/ 0.0 0.0)) (Float inf? 1.5))
```
---
    (#t #t #f #f)

### finite? is total: ints and finite floats in, specials and non-numbers out

```x
(list (Float finite? 42) (Float finite? 1.5)
      (Float finite? (/ 1.0 0.0)) (Float finite? (/ 0.0 0.0))
      (Float finite? "x"))
```
---
    (#t #t #f #f #f)
