
== arithmetic basics

-- adds two numbers
(+ 1 2)
---
3

-- subtracts two numbers
(- 10 3)
---
7

-- multiplies two numbers
(* 4 5)
---
20

-- nests arithmetic
(+ 1 (* 2 3))
---
7

-- handles negative results
(- 3 10)
---
-7

== variadic +

-- adds two numbers
(+ 1 2)
---
3

-- adds three numbers
(+ 1 2 3)
---
6

-- adds many numbers
(+ 1 2 3 4 5)
---
15

-- identity is 0
(+)
---
0

-- single arg returns it
(+ 5)
---
5

== variadic -

-- subtracts two numbers
(- 10 3)
---
7

-- subtracts three numbers
(- 10 3 2)
---
5

-- unary negates
(- 5)
---
-5

-- no args returns 0
(-)
---
0

== variadic *

-- multiplies two numbers
(* 4 5)
---
20

-- multiplies three numbers
(* 2 3 4)
---
24

-- identity is 1
(*)
---
1

-- single arg returns it
(* 7)
---
7

== variadic /

-- divides two numbers
(/ 10 3)
---
3

-- divides evenly
(/ 12 4)
---
3

-- handles negative dividend
(/ -10 3)
---
-3

-- chains division
(/ 100 5 2)
---
10

== variadic %

-- computes modulo
(% 10 3)
---
1

-- returns zero for even division
(% 12 4)
---
0

-- handles negative dividend
(% -10 3)
---
-1

-- chains modulo
(% 100 7 3)
---
2

== ~ (bitwise NOT)

-- inverts zero
(~ 0)
---
-1

-- inverts one
(~ 1)
---
-2

-- inverts negative
(~ -1)
---
0

-- double invert is identity
(~ (~ 42))
---
42

== & (bitwise AND)

-- ands with zero
(& 255 0)
---
0

-- ands with self
(& 42 42)
---
42

-- masks low bits
(& 255 15)
---
15

-- masks high nibble
(& 170 240)
---
160

== | (bitwise OR)

-- ors with zero
(| 42 0)
---
42

-- ors complementary bits
(| 170 85)
---
255

-- ors with self
(| 42 42)
---
42

== ^ (bitwise XOR)

-- xors with zero
(^ 42 0)
---
42

-- xors with self gives zero
(^ 42 42)
---
0

-- xors complementary bits
(^ 170 85)
---
255

-- double xor is identity
(^ (^ 42 99) 99)
---
42

== << (shift left)

-- shifts by 0
(<< 1 0)
---
1

-- shifts by 1
(<< 1 1)
---
2

-- shifts by 4
(<< 1 4)
---
16

-- shifts value
(<< 5 3)
---
40

== >> (shift right)

-- shifts by 0
(>> 16 0)
---
16

-- shifts by 1
(>> 16 1)
---
8

-- shifts by 4
(>> 255 4)
---
15

-- shifts to zero
(>> 1 1)
---
0
