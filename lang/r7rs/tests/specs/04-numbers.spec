
== number predicates

-- number? on integer
(number? 42)
---
t

-- number? on non-number
(null? (number? "42"))
---
t

-- integer? on integer
(integer? 42)
---
t

-- exact-integer? on integer
(exact-integer? 42)
---
t

-- exact? on integer
(exact? 42)
---
t

-- null? inexact? on integer
(null? (inexact? 42))
---
t

-- zero? true
(zero? 0)
---
t

-- zero? false
(null? (zero? 1))
---
t

-- positive? true
(positive? 1)
---
t

-- negative? true
(negative? (- 0 1))
---
t

-- odd? true
(odd? 3)
---
t

-- even? true
(even? 4)
---
t

-- odd? false
(null? (odd? 4))
---
t

-- even? false
(null? (even? 3))
---
t

== float predicates

-- number? on float
(number? 3.14)
---
t

-- real? on float
(real? 3.14)
---
t

-- real? on integer
(real? 42)
---
t

-- complex? on float
(complex? 3.14)
---
t

-- complex? on integer
(complex? 42)
---
t

-- integer? on inexact integer
(integer? 3.0)
---
t

-- integer? on non-integer float
(null? (integer? 3.5))
---
t

-- exact? on float is false
(null? (exact? 3.14))
---
t

-- inexact? on float
(inexact? 3.14)
---
t

-- exact-integer? on float is false
(null? (exact-integer? 3.0))
---
t

-- rational? on integer
(rational? 42)
---
t

-- rational? on float is false
(null? (rational? 3.14))
---
t

-- float? on float
(float? 3.14)
---
t

-- float? on integer is false
(null? (float? 42))
---
t

== IEEE 754 predicates

-- nan? on NaN
(nan? (/ 0.0 0.0))
---
t

-- nan? on regular float
(null? (nan? 3.14))
---
t

-- nan? on integer
(null? (nan? 42))
---
t

-- infinite? on positive infinity
(infinite? (/ 1.0 0.0))
---
t

-- infinite? on negative infinity
(infinite? (/ (- 0 1.0) 0.0))
---
t

-- infinite? on regular float
(null? (infinite? 3.14))
---
t

-- finite? on regular float
(finite? 3.14)
---
t

-- finite? on integer
(finite? 42)
---
t

-- finite? on NaN
(null? (finite? (/ 0.0 0.0)))
---
t

-- finite? on infinity
(null? (finite? (/ 1.0 0.0)))
---
t

== arithmetic

-- addition
(+ 3 4)
---
7

-- addition multiple
(+ 1 2 3 4)
---
10

-- subtraction
(- 10 3)
---
7

-- multiplication
(* 2 3 4)
---
24

-- integer division
(/ 10 3)
---
3

-- nested arithmetic
(+ (* 2 3) (- 10 4))
---
12

-- abs positive
(abs 7)
---
7

-- abs negative
(abs (- 0 7))
---
7

-- max
(max 3 4)
---
4

-- min
(min 3 4)
---
3

-- square
(square 5)
---
25

-- square negative
(square (- 0 3))
---
9

== float arithmetic

-- float addition
(number->string (+ 1.5 2.5))
---
"4"

-- float subtraction
(number->string (- 5.5 2.0))
---
"3.5"

-- float multiplication
(number->string (* 2.5 4.0))
---
"10"

-- float division
(number->string (/ 7.0 2.0))
---
"3.5"

-- mixed int+float addition
(float? (+ 1 2.5))
---
t

-- mixed int+float result
(number->string (+ 1 2.5))
---
"3.5"

-- mixed subtraction
(number->string (- 10 2.5))
---
"7.5"

-- mixed multiplication
(number->string (* 3 2.5))
---
"7.5"

-- exactness contagion: int+float is float
(inexact? (+ 1 2.0))
---
t

-- unary negation of float
(number->string (- 3.5))
---
"-3.5"

== float math functions

-- abs on negative float
(number->string (abs (- 0 2.5)))
---
"2.5"

-- abs on positive float
(number->string (abs 2.5))
---
"2.5"

-- zero? on 0.0
(zero? 0.0)
---
t

-- zero? on non-zero float
(null? (zero? 0.1))
---
t

-- positive? on positive float
(positive? 3.14)
---
t

-- positive? on negative float
(null? (positive? (- 0 3.14)))
---
t

-- negative? on negative float
(negative? (- 0 3.14))
---
t

-- min with mixed types
(= (min 5 2.5) 2.5)
---
t

-- max with mixed types
(= (max 1 2.5) 2.5)
---
t

-- square on float
(number->string (square 2.5))
---
"6.25"

== mixed comparisons

-- int = float (equal values)
(= 3 3.0)
---
t

-- int = float (unequal)
(null? (= 3 3.5))
---
t

-- int < float
(< 1 2.5)
---
t

-- float < int
(< 0.5 1)
---
t

-- int > float
(> 3 2.5)
---
t

-- int <= float (equal)
(<= 3 3.0)
---
t

-- int >= float
(>= 3 2.5)
---
t

-- float <= float
(<= 2.5 3.0)
---
t

== quotient and remainder

-- quotient positive
(quotient 10 3)
---
3

-- remainder positive
(remainder 10 3)
---
1

-- modulo positive
(modulo 10 3)
---
1

-- truncate-quotient
(truncate-quotient 10 3)
---
3

-- truncate-remainder
(truncate-remainder 10 3)
---
1

-- floor-quotient positive
(floor-quotient 7 2)
---
3

-- floor-remainder positive
(floor-remainder 7 2)
---
1

-- floor-quotient negative dividend
(floor-quotient (- 0 7) 2)
---
-4

-- floor-remainder negative dividend
(floor-remainder (- 0 7) 2)
---
1

== gcd and lcm

-- gcd of two numbers
(gcd 12 8)
---
4

-- gcd with zero
(gcd 5 0)
---
5

-- lcm of two numbers
(lcm 4 6)
---
12

-- lcm with zero
(lcm 0 5)
---
0

== rounding

-- floor of positive float
(floor 3.7)
---
3

-- floor of negative float
(floor (- 0 3.3))
---
-4

-- floor of integer
(floor 5)
---
5

-- floor returns exact
(exact? (floor 3.7))
---
t

-- ceiling of positive float
(ceiling 3.2)
---
4

-- ceiling of negative float
(ceiling (- 0 3.7))
---
-3

-- ceiling of integer
(ceiling 5)
---
5

-- ceiling returns exact
(exact? (ceiling 3.2))
---
t

-- truncate of positive float
(truncate 3.7)
---
3

-- truncate of negative float
(truncate (- 0 3.7))
---
-3

-- truncate of integer
(truncate 5)
---
5

-- round of 3.5
(round 3.5)
---
4

-- round of 2.5
(round 2.5)
---
2

-- round of 3.2
(round 3.2)
---
3

-- round of negative
(round (- 0 3.7))
---
-4

-- round returns exact
(exact? (round 3.7))
---
t

== sqrt

-- sqrt of perfect square
(sqrt 9)
---
3

-- sqrt of perfect square returns exact
(exact? (sqrt 9))
---
t

-- sqrt of 25
(sqrt 25)
---
5

-- sqrt of non-perfect square returns float
(inexact? (sqrt 2))
---
t

-- sqrt of non-perfect square value
(> (sqrt 2) 1.4)
---
t

-- sqrt of zero
(sqrt 0)
---
0

-- sqrt of float
(number->string (sqrt 2.0))
---
"1.4142135623731"

== expt

-- expt basic
(expt 2 10)
---
1024

-- expt zero power
(expt 5 0)
---
1

-- expt power of one
(expt 7 1)
---
7

-- expt with float base
(number->string (expt 2.0 3.0))
---
"8"

-- expt with float returns float
(inexact? (expt 2.0 3.0))
---
t

-- expt integer result stays exact
(exact? (expt 2 10))
---
t

== exact/inexact conversion

-- inexact converts int to float
(inexact? (inexact 42))
---
t

-- inexact value
(= (inexact 42) 42.0)
---
t

-- exact converts float to int
(exact? (exact 3.0))
---
t

-- exact value
(= (exact 3.0) 3)
---
t

-- exact->inexact converts int to float
(inexact? (exact->inexact 5))
---
t

-- inexact->exact converts float to int
(exact? (inexact->exact 5.0))
---
t

== comparison

-- equal numbers
(= 5 5)
---
t

-- not equal
(null? (= 5 6))
---
t

-- less than
(< 1 2)
---
t

-- greater than
(> 2 1)
---
t

-- less or equal
(<= 2 2)
---
t

-- greater or equal
(>= 3 2)
---
t

== string/number conversion

-- number->string integer
(number->string 42)
---
"42"

-- string->number integer
(string->number "42")
---
42

-- number->string float
(number->string 3.14)
---
"3.14"

-- string->number float
(number->string (string->number "3.14"))
---
"3.14"

-- string->number returns float for dotted
(inexact? (string->number "3.14"))
---
t

-- string->number returns int for non-dotted
(exact? (string->number "42"))
---
t

-- number->string negative
(number->string (- 0 7))
---
"-7"

-- number->string negative float
(number->string (- 0 3.14))
---
"-3.14"
