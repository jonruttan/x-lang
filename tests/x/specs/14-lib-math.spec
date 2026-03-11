
== inc

-- increments by one
(inc 5)
---
6

== dec

-- decrements by one
(dec 5)
---
4

== negate

-- negates positive
(negate 5)
---
-5

-- negates negative
(negate -3)
---
3

== abs

-- positive stays positive
(abs 5)
---
5

-- negative becomes positive
(abs -5)
---
5

-- zero stays zero
(abs 0)
---
0

== min

-- returns smaller
(min 3 7)
---
3

-- returns smaller when first is larger
(min 7 3)
---
3

== max

-- returns larger
(max 3 7)
---
7

-- returns larger when first is larger
(max 7 3)
---
7

== clamp

-- clamps below minimum
(clamp 0 10 -5)
---
0

-- clamps above maximum
(clamp 0 10 15)
---
10

-- passes through in range
(clamp 0 10 5)
---
5

== min-by

-- returns min by key function
(min-by abs 3 -5)
---
3

== max-by

-- returns max by key function
(max-by abs 3 -5)
---
-5

== sum

-- sums a list
(sum (list 1 2 3 4))
---
10

-- sum of empty is zero
(sum ())
---
0

== product

-- multiplies a list
(product (list 1 2 3 4))
---
24

-- product of empty is one
(product ())
---
1

== zero?

-- true for zero
(zero? 0)
---
t

-- false for non-zero
(if (zero? 5) "y" "n")
---
"n"

== positive?

-- true for positive
(positive? 5)
---
t

-- false for negative
(if (positive? -1) "y" "n")
---
"n"

== negative?

-- true for negative
(negative? -5)
---
t

-- false for positive
(if (negative? 1) "y" "n")
---
"n"

== even?

-- true for even
(even? 4)
---
t

-- false for odd
(if (even? 3) "y" "n")
---
"n"

== odd?

-- true for odd
(odd? 3)
---
t

-- false for even
(if (odd? 4) "y" "n")
---
"n"
