# @weight 1
## inc

### increments by one

```x
(Num inc 5)
```
---
    6

## dec

### decrements by one

```x
(Num dec 5)
```
---
    4

## negate

### negates positive

```x
(Num negate 5)
```
---
    -5

### negates negative

```x
(Num negate -3)
```
---
    3

## abs

### positive stays positive

```x
(Num abs 5)
```
---
    5

### negative becomes positive

```x
(Num abs -5)
```
---
    5

### zero stays zero

```x
(Num abs 0)
```
---
    0

## min

### returns smaller

```x
(Num min 3 7)
```
---
    3

### returns smaller when first is larger

```x
(Num min 7 3)
```
---
    3

## max

### returns larger

```x
(Num max 3 7)
```
---
    7

### returns larger when first is larger

```x
(Num max 7 3)
```
---
    7

## clamp

### clamps below minimum

```x
(Num clamp 0 10 -5)
```
---
    0

### clamps above maximum

```x
(Num clamp 0 10 15)
```
---
    10

### passes through in range

```x
(Num clamp 0 10 5)
```
---
    5

## min-by

### returns min by key function

```x
(Num min-by (method-ref Num abs) 3 -5)
```
---
    3

## max-by

### returns max by key function

```x
(Num max-by (method-ref Num abs) 3 -5)
```
---
    -5

## sum

### sums a list

```x
(List sum (list 1 2 3 4))
```
---
    10

### sum of empty is zero

```x
(List sum ())
```
---
    0

## product

### multiplies a list

```x
(List product (list 1 2 3 4))
```
---
    24

### product of empty is one

```x
(List product ())
```
---
    1

## zero?

### true for zero

```x
(Num zero? 0)
```
---
    #t

### false for non-zero

```x
(if (Num zero? 5) "y" "n")
```
---
    "n"

## positive?

### true for positive

```x
(Num positive? 5)
```
---
    #t

### false for negative

```x
(if (Num positive? -1) "y" "n")
```
---
    "n"

## negative?

### true for negative

```x
(Num negative? -5)
```
---
    #t

### false for positive

```x
(if (Num negative? 1) "y" "n")
```
---
    "n"

## even?

### true for even

```x
(Num even? 4)
```
---
    #t

### false for odd

```x
(if (Num even? 3) "y" "n")
```
---
    "n"

## odd?

### true for odd

```x
(Num odd? 3)
```
---
    #t

### false for even

```x
(if (Num odd? 4) "y" "n")
```
---
    "n"


## gcd

### two numbers

```x
(Num gcd 12 8)
```
---
    4

### coprime

```x
(Num gcd 7 13)
```
---
    1

### variadic

```x
(Num gcd 12 8 6)
```
---
    2

## lcm

### two numbers

```x
(Num lcm 4 6)
```
---
    12

### variadic

```x
(Num lcm 2 3 4)
```
---
    12

## expt

### power of two

```x
(Num expt 2 10)
```
---
    1024

### zero exponent

```x
(Num expt 5 0)
```
---
    1

### base one

```x
(Num expt 1 100)
```
---
    1

### errors on a negative exponent (x-lang#545)

A negative exponent used to walk away from the base case, squaring the base
each even step until it exhausted memory.

```x
(Num expt 2 -1)
```
---
    Error: #<err:value Num expt: negative exponent>

## quotient / remainder / modulo / divmod

### quotient truncates toward zero

```x
(list (Num quotient 7 2) (Num quotient -7 2))
```
---
    (3 -3)

### remainder takes the dividend's sign

```x
(list (Num remainder 7 2) (Num remainder -7 2))
```
---
    (1 -1)

### modulo takes the divisor's sign

```x
(list (Num modulo -7 3) (Num modulo 7 -3))
```
---
    (2 -2)

### divmod pairs them

```x
(Num divmod 7 2)
```
---
    (3 1)

## variadic min / max

### more than two arguments

```x
(list (Num min 3 1 2) (Num max 3 1 2))
```
---
    (1 3)

### binary still works

```x
(Num min 5 4)
```
---
    4

## isqrt

### largest k with k*k <= n

```x
(list (Num isqrt 0) (Num isqrt 1) (Num isqrt 99) (Num isqrt 100))
```
---
    (0 1 9 10)

### errors on negatives

```x
(Num isqrt -1)
```
---
    Error: #<err:value Num isqrt: negative input>

## int?

### recognizes machine integers only (N5's explicit-control door)

```x
(list (Num int? 3) (Num int? ()) (Num int? "3"))
```
---
    (#t #f #f)
