
== arithmetic

-- addition
(+ 1 2 3)
---
6

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

-- unary minus
(- 0 5)
---
-5

-- multiplication by zero
(* 42 0)
---
0

== comparison

-- equal numbers
(= 5 5)
---
t

-- not equal
(null? (= 5 6))
---
t

-- less than true
(< 1 2)
---
t

-- less than false
(null? (< 2 1))
---
t

-- greater than true
(> 2 1)
---
t

-- greater than false
(null? (> 1 2))
---
t

-- less or equal on equal
(<= 2 2)
---
t

-- less or equal on less
(<= 1 2)
---
t

-- greater or equal on equal
(>= 2 2)
---
t

-- greater or equal on greater
(>= 3 2)
---
t

== quotient and remainder

-- quotient positive
(quotient 10 3)
---
3

-- quotient exact
(quotient 9 3)
---
3

-- remainder positive
(remainder 10 3)
---
1

-- remainder zero
(remainder 9 3)
---
0

-- modulo positive
(modulo 10 3)
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

-- gcd zero with number
(gcd 0 7)
---
7

-- gcd coprime
(gcd 7 13)
---
1

-- lcm of two numbers
(lcm 4 6)
---
12

-- lcm with zero
(lcm 0 5)
---
0

-- lcm same numbers
(lcm 5 5)
---
5

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

-- expt small base
(expt 3 4)
---
81
