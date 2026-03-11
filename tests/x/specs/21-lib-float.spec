# @lib x.x

== float literals

-- parses simple float
3.14
---
3.14

-- parses integer-like float
1.0
---
1

-- parses small float
0.5
---
0.5

-- parses large float
12345.6789
---
12345.6789

-- float? true for float
(float? 3.14)
---
t

-- float? false for integer
(null? (float? 42))
---
t

-- float? false for string
(null? (float? "3.14"))
---
t

== type convert handler

-- convert int to float
(convert 42 %float)
---
42

-- convert result is float
(float? (convert 42 %float))
---
t

-- convert float to float is identity
(def x 3.14) (eq? (convert x %float) x)
---
t

-- convert string to float
(float? (convert "3.14" %float))
---
t

-- convert nil returns nil
(null? (convert () %float))
---
t

-- convert negative int
(convert -5 %float)
---
-5

-- convert zero
(convert 0 %float)
---
0

== float conversions

-- exact->inexact converts int
(exact->inexact 5)
---
5

-- exact->inexact result is float
(float? (exact->inexact 5))
---
t

-- exact->inexact float identity
(def x 3.14) (eq? (exact->inexact x) x)
---
t

-- inexact->exact truncates
(inexact->exact 3.14)
---
3

-- inexact->exact rounds toward zero
(inexact->exact 9.99)
---
9

-- string->float and back
(float->string (string->float "2.718"))
---
"2.718"

-- int->float and back
(float->int (int->float 42))
---
42

== float arithmetic (f+ f- f* f/)

-- f+ addition
(f+ 1.5 2.5)
---
4

-- f- subtraction
(f- 10.0 3.5)
---
6.5

-- f* multiplication
(f* 3.0 4.0)
---
12

-- f/ division
(f/ 10.0 4.0)
---
2.5

-- f/ non-integer result
(f/ 1.0 3.0)
---
0.333333333333333

== generic arithmetic with floats

-- + two floats
(+ 1.5 2.5)
---
4

-- + int and float
(+ 1 2.5)
---
3.5

-- + float and int
(+ 2.5 1)
---
3.5

-- + three with float
(+ 1 2 3.0)
---
6

-- - two floats
(- 10.0 3.5)
---
6.5

-- - negate float
(- 3.14)
---
-3.14

-- * two floats
(* 3.0 4.0)
---
12

-- * int and float
(* 2 3.5)
---
7

-- / two floats
(/ 10.0 4.0)
---
2.5

-- / int and float
(/ 7 2.0)
---
3.5

-- + integers unchanged
(+ 1 2 3)
---
6

-- * integers unchanged
(* 2 3 4)
---
24

== float comparisons

-- f< true
(f< 1.5 2.5)
---
t

-- f< false
(null? (f< 2.5 1.5))
---
t

-- f= true
(f= 1.0 1.0)
---
t

-- f= false
(null? (f= 1.0 2.0))
---
t

== generic comparisons with floats

-- < with floats
(< 1.5 2.5)
---
t

-- > with floats
(> 3.0 2.0)
---
t

-- = with floats
(= 1.0 1.0)
---
t

-- <= with floats
(<= 2.0 2.0)
---
t

-- >= with floats
(>= 3.0 2.0)
---
t

-- < int and float
(< 1 2.5)
---
t

-- > float and int
(> 3.5 2)
---
t

-- = int and float
(= 2 2.0)
---
t

-- < integers still work
(< 1 2)
---
t

-- = integers still work
(= 5 5)
---
t

== math functions

-- fsin of 0
(fsin (exact->inexact 0))
---
0

-- fcos of 0
(fcos (exact->inexact 0))
---
1

-- fsqrt of 4
(fsqrt 4.0)
---
2

-- fsqrt of 2
(fsqrt 2.0)
---
1.4142135623731

-- fabs positive
(fabs 3.14)
---
3.14

-- fabs negative
(fabs (- 3.14))
---
3.14

-- ffloor
(ffloor 3.7)
---
3

-- fceil
(fceil 3.2)
---
4

-- fround
(fround 3.5)
---
4

-- fexp of 0
(fexp (exact->inexact 0))
---
1

-- flog of 1
(flog 1.0)
---
0

-- fpow 2^10
(fpow 2.0 10.0)
---
1024

== float constants

-- pi is approximately 3.14159
(> %pi 3.14)
---
t

-- pi is approximately 3.14159 upper
(< %pi 3.15)
---
t

-- e is approximately 2.71828
(> %e 2.71)
---
t

-- e is approximately 2.71828 upper
(< %e 2.72)
---
t

== float predicates

-- number? true for integer
(number? 42)
---
t

-- number? true for float
(number? 3.14)
---
t

-- number? false for string
(null? (number? "hello"))
---
t

-- integer? true for int
(integer? 42)
---
t

-- integer? false for float
(null? (integer? 3.14))
---
t

-- float? true for float
(float? 3.14)
---
t

-- float? false for int
(null? (float? 42))
---
t

-- inexact? true for float
(inexact? 3.14)
---
t

-- inexact? false for int
(null? (inexact? 42))
---
t

== float in data structures

-- float in list
(list 1.5 2.5 3.5)
---
(1.5 2.5 3.5)

-- float in pair
(pair 1.5 2.5)
---
(1.5 . 2.5)

-- float in variable
(def x 3.14) x
---
3.14

-- map with floats
(map (fn (x) (* x 2.0)) (list 1.0 2.0 3.0))
---
(2 4 6)

-- filter with floats
(filter (fn (x) (> x 2.0)) (list 1.0 2.5 3.0 0.5))
---
(2.5 3)

-- fold with floats
(fold + 0.0 (list 1.0 2.0 3.0))
---
6

-- float in vector
(vector 1.5 2.5 3.5)
---
#(1.5 2.5 3.5)

== float edge cases

-- very small float
(> 0.001 (exact->inexact 0))
---
t

-- negative float
(- 3.14)
---
-3.14

-- float zero
(f= 0.0 (exact->inexact 0))
---
t

-- mixed arithmetic chain
(+ (* 2.0 3.0) (/ 10.0 5.0))
---
8
