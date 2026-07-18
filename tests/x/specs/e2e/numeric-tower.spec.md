# @lib x-base.x

## integer arithmetic

### basic addition

```scheme
(+ 2 3)
```
---
    5

### basic multiplication

```scheme
(* 6 7)
```
---
    42

## bignum promotion

### multiply overflow promotes

```scheme
(Bignum bignum? (* 999999999999 999999999999))
```
---
    #t

### add overflow promotes

```scheme
(Bignum bignum? (+ 4611686018427387904 4611686018427387904))
```
---
    #t

### bignum subtraction produces correct value

```scheme
(= (- (+ 4611686018427387904 4611686018427387904) 4611686018427387904) 4611686018427387904)
```
---
    #t

## float arithmetic

### float addition

```scheme
(write (+ 1.5 2.5))
```
---
    4.0

### int plus float promotes

```scheme
(Float float? (+ 1 1.5))
```
---
    #t

### float times float

```scheme
(Float float? (* 2.0 3.0))
```
---
    #t

### float plus bignum promotes to float

```scheme
(Float float? (+ 1.0 99999999999999999999))
```
---
    #t

## rational arithmetic

### rational addition

```scheme
(write (+ 1/3 1/6))
```
---
    1/2

### int division produces rational

```scheme
(write (/ 1 3))
```
---
    1/3

### rational times int

```scheme
(write (* 1/3 6))
```
---
    2

## complex arithmetic

### complex addition

```scheme
(write (+ 1+2i 3+4i))
```
---
    4+6i

### complex times real

```scheme
(write (* 2+3i 2))
```
---
    4+6i

## cross-tower promotion

### int < float comparison

```scheme
(< 1 1.5)
```
---
    #t

### rational equality

```scheme
(= 1/2 1/2)
```
---
    #t

### float equality with rational

```scheme
(= 0.5 1/2)
```
---
    #t
