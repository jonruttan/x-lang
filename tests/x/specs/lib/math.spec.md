## inc

### increments by one

```scheme
(inc 5)
```
---
    6

## dec

### decrements by one

```scheme
(dec 5)
```
---
    4

## negate

### negates positive

```scheme
(negate 5)
```
---
    -5

### negates negative

```scheme
(negate -3)
```
---
    3

## abs

### positive stays positive

```scheme
(abs 5)
```
---
    5

### negative becomes positive

```scheme
(abs -5)
```
---
    5

### zero stays zero

```scheme
(abs 0)
```
---
    0

## min

### returns smaller

```scheme
(min 3 7)
```
---
    3

### returns smaller when first is larger

```scheme
(min 7 3)
```
---
    3

## max

### returns larger

```scheme
(max 3 7)
```
---
    7

### returns larger when first is larger

```scheme
(max 7 3)
```
---
    7

## clamp

### clamps below minimum

```scheme
(clamp 0 10 -5)
```
---
    0

### clamps above maximum

```scheme
(clamp 0 10 15)
```
---
    10

### passes through in range

```scheme
(clamp 0 10 5)
```
---
    5

## min-by

### returns min by key function

```scheme
(min-by abs 3 -5)
```
---
    3

## max-by

### returns max by key function

```scheme
(max-by abs 3 -5)
```
---
    -5

## sum

### sums a list

```scheme
(sum (list 1 2 3 4))
```
---
    10

### sum of empty is zero

```scheme
(sum ())
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
(zero? 0)
```
---
    #t

### false for non-zero

```scheme
(if (zero? 5) "y" "n")
```
---
    "n"

## positive?

### true for positive

```scheme
(positive? 5)
```
---
    #t

### false for negative

```scheme
(if (positive? -1) "y" "n")
```
---
    "n"

## negative?

### true for negative

```scheme
(negative? -5)
```
---
    #t

### false for positive

```scheme
(if (negative? 1) "y" "n")
```
---
    "n"

## even?

### true for even

```scheme
(even? 4)
```
---
    #t

### false for odd

```scheme
(if (even? 3) "y" "n")
```
---
    "n"

## odd?

### true for odd

```scheme
(odd? 3)
```
---
    #t

### false for even

```scheme
(if (odd? 4) "y" "n")
```
---
    "n"


## gcd

### two numbers

```scheme
(gcd 12 8)
```
---
    4

### coprime

```scheme
(gcd 7 13)
```
---
    1

### variadic

```scheme
(gcd 12 8 6)
```
---
    2

## lcm

### two numbers

```scheme
(lcm 4 6)
```
---
    12

### variadic

```scheme
(lcm 2 3 4)
```
---
    12

## expt

### power of two

```scheme
(expt 2 10)
```
---
    1024

### zero exponent

```scheme
(expt 5 0)
```
---
    1

### base one

```scheme
(expt 1 100)
```
---
    1
