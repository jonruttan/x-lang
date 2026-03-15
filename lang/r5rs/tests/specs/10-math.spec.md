## arithmetic

### addition

```scheme
(+ 1 2 3)
```
---
    6

### subtraction

```scheme
(- 10 3)
```
---
    7

### multiplication

```scheme
(* 2 3 4)
```
---
    24

### integer division

```scheme
(/ 10 3)
```
---
    3

### nested arithmetic

```scheme
(+ (* 2 3) (- 10 4))
```
---
    12

### unary minus

```scheme
(- 0 5)
```
---
    -5

### multiplication by zero

```scheme
(* 42 0)
```
---
    0

## comparison

### equal numbers

```scheme
(= 5 5)
```
---
    #t

### not equal

```scheme
(not (= 5 6))
```
---
    #t

### less than true

```scheme
(< 1 2)
```
---
    #t

### less than false

```scheme
(not (< 2 1))
```
---
    #t

### greater than true

```scheme
(> 2 1)
```
---
    #t

### greater than false

```scheme
(not (> 1 2))
```
---
    #t

### less or equal on equal

```scheme
(<= 2 2)
```
---
    #t

### less or equal on less

```scheme
(<= 1 2)
```
---
    #t

### greater or equal on equal

```scheme
(>= 2 2)
```
---
    #t

### greater or equal on greater

```scheme
(>= 3 2)
```
---
    #t

## quotient and remainder

### quotient positive

```scheme
(quotient 10 3)
```
---
    3

### quotient exact

```scheme
(quotient 9 3)
```
---
    3

### remainder positive

```scheme
(remainder 10 3)
```
---
    1

### remainder zero

```scheme
(remainder 9 3)
```
---
    0

### modulo positive

```scheme
(modulo 10 3)
```
---
    1

## gcd and lcm

### gcd of two numbers

```scheme
(gcd 12 8)
```
---
    4

### gcd with zero

```scheme
(gcd 5 0)
```
---
    5

### gcd zero with number

```scheme
(gcd 0 7)
```
---
    7

### gcd coprime

```scheme
(gcd 7 13)
```
---
    1

### lcm of two numbers

```scheme
(lcm 4 6)
```
---
    12

### lcm with zero

```scheme
(lcm 0 5)
```
---
    0

### lcm same numbers

```scheme
(lcm 5 5)
```
---
    5

## expt

### expt basic

```scheme
(expt 2 10)
```
---
    1024

### expt zero power

```scheme
(expt 5 0)
```
---
    1

### expt power of one

```scheme
(expt 7 1)
```
---
    7

### expt small base

```scheme
(expt 3 4)
```
---
    81

