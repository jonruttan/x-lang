# @lib ../tests/x/lib/bignum.x

## bignum literal

### parses large number

```scheme
(Bignum bignum? 99999999999999999999)
```
---
    #t

### small numbers stay native

```scheme
(if (Bignum bignum? 42) "big" "native")
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
(Bignum bignum? (* 999999999999 999999999999))
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
(Bignum bignum? (+ 9223372036854775807 1))
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
(if (Bignum would-overflow-add? 1 2) "y" "n")
```
---
    "n"

### overflow for large positive

```scheme
(Bignum would-overflow-mul? 3037000500 3037000500)
```
---
    #t

## would-overflow-mul?

### detects multiplication overflow

```scheme
(Bignum would-overflow-mul? 9999999999 9999999999)
```
---
    #t

### no overflow for small

```scheme
(if (Bignum would-overflow-mul? 2 3) "y" "n")
```
---
    "n"

## big+

### adds two bignums

```scheme
(write (Bignum + (convert 100 %bignum) (convert 200 %bignum)))
```
---
    300

### adds large bignums

```scheme
(write (Bignum + (convert 999999999999999999 %bignum) (convert 1 %bignum)))
```
---
    1000000000000000000

## big-

### subtracts bignums

```scheme
(write (Bignum - (convert 1000 %bignum) (convert 1 %bignum)))
```
---
    999

## big*

### multiplies bignums

```scheme
(write (Bignum * (convert 12345 %bignum) (convert 6789 %bignum)))
```
---
    83810205

### large multiply

```scheme
(Bignum bignum? (Bignum * (convert 999999999 %bignum) (convert 999999999 %bignum)))
```
---
    #t

## big/

### divides bignums

```scheme
(write (Bignum / (convert 100 %bignum) (convert 7 %bignum)))
```
---
    14

### divides with a multi-limb quotient

```scheme
(write (Bignum / (convert 99999999999999999999 %bignum) (convert 7 %bignum)))
```
---
    14285714285714285714

### remainder dispatches through the generic %

```scheme
(% 99999999999999999999 7)
```
---
    1

## big<

### less than

```scheme
(Bignum < (convert 1 %bignum) (convert 2 %bignum))
```
---
    #t

### not less than

```scheme
(Bignum < (convert 2 %bignum) (convert 1 %bignum))
```
---
    #f

## big=

### equal

```scheme
(Bignum = (convert 42 %bignum) (convert 42 %bignum))
```
---
    #t

### not equal

```scheme
(Bignum = (convert 1 %bignum) (convert 2 %bignum))
```
---
    #f
