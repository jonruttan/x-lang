# @lib ../tests/x/lib/float.x

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

### parses negative float

```scheme
-7.5
```
---
    -7.5

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
(Float float? 3.14)
```
---
    #t

### float? false for integer

```scheme
(Float float? 42)
```
---
    #f

### float? false for string

```scheme
(Float float? "3.14")
```
---
    #f

## type convert handler

### convert int to float

```scheme
(Convert to 42 %float)
```
---
    42

### convert result is float

```scheme
(Float float? (Convert to 42 %float))
```
---
    #t

### convert float to float is identity

```scheme
(def x 3.14) (eq? (Convert to x %float) x)
```
---
    #t

### convert string to float

```scheme
(Float float? (Convert to "3.14" %float))
```
---
    #t

### convert nil returns nil

```scheme
(null? (Convert to () %float))
```
---
    #t

### convert negative int

```scheme
(Convert to -5 %float)
```
---
    -5

### convert zero

```scheme
(Convert to 0 %float)
```
---
    0

## float conversions

### exact->inexact converts int

```scheme
(Float exact->inexact 5)
```
---
    5

### exact->inexact result is float

```scheme
(Float float? (Float exact->inexact 5))
```
---
    #t

### exact->inexact float identity

```scheme
(def x 3.14) (eq? (Float exact->inexact x) x)
```
---
    #t

### inexact->exact truncates

```scheme
(Float inexact->exact 3.14)
```
---
    3

### inexact->exact rounds toward zero

```scheme
(Float inexact->exact 9.99)
```
---
    9

### str->float and back

```scheme
(Float ->str (Float from-str "2.718"))
```
---
    "2.718"

### int->float and back

```scheme
(Float ->int (Float from-int 42))
```
---
    42

## float arithmetic (Float + f- f* f/)

### f+ addition

```scheme
(Float + 1.5 2.5)
```
---
    4

### f- subtraction

```scheme
(Float - 10.0 3.5)
```
---
    6.5

### f* multiplication

```scheme
(Float * 3.0 4.0)
```
---
    12

### f/ division

```scheme
(Float / 10.0 4.0)
```
---
    2.5

### f/ non-integer result

```scheme
(Float / 1.0 3.0)
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

## % with floats (fmod)

### % smaller by larger is the dividend

```scheme
(% 1.2 1.4)
```
---
    1.2

### % larger by smaller

```scheme
(% 1.4 1.2)
```
---
    0.2

### % float by float

```scheme
(% 7.5 2.0)
```
---
    1.5

### % truncates toward zero (C semantics)

```scheme
(% -7.5 2.0)
```
---
    -1.5

### % float by int coerces

```scheme
(% 5.5 2)
```
---
    1.5

### % integers unchanged

```scheme
(% 7 3)
```
---
    1

## float comparisons

### f< true

```scheme
(Float < 1.5 2.5)
```
---
    #t

### f< false

```scheme
(Float < 2.5 1.5)
```
---
    #f

### f= true

```scheme
(Float = 1.0 1.0)
```
---
    #t

### f= false

```scheme
(Float = 1.0 2.0)
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
(Float sin (Float exact->inexact 0))
```
---
    0

### fcos of 0

```scheme
(Float cos (Float exact->inexact 0))
```
---
    1

### fsqrt of 4

```scheme
(Float sqrt 4.0)
```
---
    2

### fsqrt of 2

```scheme
(Float sqrt 2.0)
```
---
    1.4142135623731

### fabs positive

```scheme
(Float abs 3.14)
```
---
    3.14

### fabs negative

```scheme
(Float abs (- 3.14))
```
---
    3.14

### ffloor

```scheme
(Float floor 3.7)
```
---
    3

### fceil

```scheme
(Float ceil 3.2)
```
---
    4

### fround

```scheme
(Float round 3.5)
```
---
    4

### fexp of 0

```scheme
(Float exp (Float exact->inexact 0))
```
---
    1

### flog of 1

```scheme
(Float log 1.0)
```
---
    0

### fpow 2^10

```scheme
(Float pow 2.0 10.0)
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
(Float integer? 42)
```
---
    #t

### integer? false for float

```scheme
(Float integer? 3.14)
```
---
    #f

### float? true for float

```scheme
(Float float? 3.14)
```
---
    #t

### float? false for int

```scheme
(Float float? 42)
```
---
    #f

### inexact? true for float

```scheme
(Float inexact? 3.14)
```
---
    #t

### inexact? false for int

```scheme
(Float inexact? 42)
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
(Vector of 1.5 2.5 3.5)
```
---
    #(1.5 2.5 3.5)

## float edge cases

### very small float

```scheme
(> 0.001 (Float exact->inexact 0))
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
(Float = 0.0 (Float exact->inexact 0))
```
---
    #t

### mixed arithmetic chain

```scheme
(+ (* 2.0 3.0) (/ 10.0 5.0))
```
---
    8


## N5: count/index seats coerce through the tower

### a float count truncates via the registered converter

```scheme
(list (List take 2.75 (list 1 2 3 4)) (List ref 1.25 (list 10 20 30)))
```
---
    ((1 2) 20)
