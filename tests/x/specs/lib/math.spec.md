## inc

### increments by one

```scheme
(Num inc 5)
```
---
    6

## dec

### decrements by one

```scheme
(Num dec 5)
```
---
    4

## negate

### negates positive

```scheme
(Num negate 5)
```
---
    -5

### negates negative

```scheme
(Num negate -3)
```
---
    3

## abs

### positive stays positive

```scheme
(Num abs 5)
```
---
    5

### negative becomes positive

```scheme
(Num abs -5)
```
---
    5

### zero stays zero

```scheme
(Num abs 0)
```
---
    0

## min

### returns smaller

```scheme
(Num min 3 7)
```
---
    3

### returns smaller when first is larger

```scheme
(Num min 7 3)
```
---
    3

## max

### returns larger

```scheme
(Num max 3 7)
```
---
    7

### returns larger when first is larger

```scheme
(Num max 7 3)
```
---
    7

## clamp

### clamps below minimum

```scheme
(Num clamp 0 10 -5)
```
---
    0

### clamps above maximum

```scheme
(Num clamp 0 10 15)
```
---
    10

### passes through in range

```scheme
(Num clamp 0 10 5)
```
---
    5

## min-by

### returns min by key function

```scheme
(Num min-by (method-ref Num abs) 3 -5)
```
---
    3

## max-by

### returns max by key function

```scheme
(Num max-by (method-ref Num abs) 3 -5)
```
---
    -5

## sum

### sums a list

```scheme
(List sum (list 1 2 3 4))
```
---
    10

### sum of empty is zero

```scheme
(List sum ())
```
---
    0

## product

### multiplies a list

```scheme
(List product (list 1 2 3 4))
```
---
    24

### product of empty is one

```scheme
(List product ())
```
---
    1

## zero?

### true for zero

```scheme
(Num zero? 0)
```
---
    #t

### false for non-zero

```scheme
(if (Num zero? 5) "y" "n")
```
---
    "n"

## positive?

### true for positive

```scheme
(Num positive? 5)
```
---
    #t

### false for negative

```scheme
(if (Num positive? -1) "y" "n")
```
---
    "n"

## negative?

### true for negative

```scheme
(Num negative? -5)
```
---
    #t

### false for positive

```scheme
(if (Num negative? 1) "y" "n")
```
---
    "n"

## even?

### true for even

```scheme
(Num even? 4)
```
---
    #t

### false for odd

```scheme
(if (Num even? 3) "y" "n")
```
---
    "n"

## odd?

### true for odd

```scheme
(Num odd? 3)
```
---
    #t

### false for even

```scheme
(if (Num odd? 4) "y" "n")
```
---
    "n"


## gcd

### two numbers

```scheme
(Num gcd 12 8)
```
---
    4

### coprime

```scheme
(Num gcd 7 13)
```
---
    1

### variadic

```scheme
(Num gcd 12 8 6)
```
---
    2

## lcm

### two numbers

```scheme
(Num lcm 4 6)
```
---
    12

### variadic

```scheme
(Num lcm 2 3 4)
```
---
    12

## expt

### power of two

```scheme
(Num expt 2 10)
```
---
    1024

### zero exponent

```scheme
(Num expt 5 0)
```
---
    1

### base one

```scheme
(Num expt 1 100)
```
---
    1

## quotient / remainder / modulo / divmod

### quotient truncates toward zero

```scheme
(list (Num quotient 7 2) (Num quotient -7 2))
```
---
    (3 -3)

### remainder takes the dividend's sign

```scheme
(list (Num remainder 7 2) (Num remainder -7 2))
```
---
    (1 -1)

### modulo takes the divisor's sign

```scheme
(list (Num modulo -7 3) (Num modulo 7 -3))
```
---
    (2 -2)

### divmod pairs them

```scheme
(Num divmod 7 2)
```
---
    (3 1)

## variadic min / max

### more than two arguments

```scheme
(list (Num min 3 1 2) (Num max 3 1 2))
```
---
    (1 3)

### binary still works

```scheme
(Num min 5 4)
```
---
    4

## isqrt

### largest k with k*k <= n

```scheme
(list (Num isqrt 0) (Num isqrt 1) (Num isqrt 99) (Num isqrt 100))
```
---
    (0 1 9 10)

### errors on negatives

```scheme
(Num isqrt -1)
```
---
    Error: Num isqrt: negative input
