# @lib x-base.x

## bignum literal

### parses large number

```scheme
(bignum? 99999999999999999999)
```
---
    #t

### small numbers stay native

```scheme
(if (bignum? 42) "big" "native")
```
---
    "native"

### displays correctly

```scheme
(write 10000000000000000000)
```
---
    10000000000000000000

### negative bignum

```scheme
(write -99999999999999999999)
```
---
    -99999999999999999999

## overflow promotion

### multiplication overflow promotes

```scheme
(bignum? (* 999999999999 999999999999))
```
---
    #t

### multiplication result correct

```scheme
(write (* 999999999999 999999999999))
```
---
    999999999998000000000001

### addition overflow promotes

```scheme
(bignum? (+ 9223372036854775807 1))
```
---
    #t

## big+

### adds two bignums

```scheme
(write (+ 99999999999999999999 1))
```
---
    100000000000000000000

## big-

### subtracts bignums

```scheme
(write (- 100000000000000000000 1))
```
---
    99999999999999999999

## big*

### multiplies bignums

```scheme
(write (* 10000000000 10000000000))
```
---
    100000000000000000000

## big<

### compares bignums

```scheme
(< 99999999999999999999 100000000000000000000)
```
---
    #t

## big=

### equal bignums

```scheme
(= 99999999999999999999 99999999999999999999)
```
---
    #t

## would-overflow-add?

### no overflow for small addition

```scheme
(if (would-overflow-add? 1 2) "y" "n")
```
---
    "n"

### overflow for large positive

```scheme
(would-overflow-mul? 3037000500 3037000500)
```
---
    #t

## would-overflow-mul?

### detects multiplication overflow

```scheme
(would-overflow-mul? 9999999999 9999999999)
```
---
    #t

### no overflow for small

```scheme
(if (would-overflow-mul? 2 3) "y" "n")
```
---
    "n"
