# @lib ../tests/x/lib/bigint.x

## bigint literal

### parses large number

```scheme
(Bigint bigint? 99999999999999999999)
```
---
    #t

### small numbers stay native

```scheme
(if (Bigint bigint? 42) "big" "native")
```
---
    "native"

### displays correctly

```scheme
(write 10000000000000000000)
```
---
    10000000000000000000

### negative bigint

```scheme
(write -99999999999999999999)
```
---
    -99999999999999999999

## overflow promotion

### multiplication overflow promotes

```scheme
(Bigint bigint? (* 999999999999 999999999999))
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
(Bigint bigint? (+ 9223372036854775807 1))
```
---
    #t

## big+

### adds two bigints

```scheme
(write (+ 99999999999999999999 1))
```
---
    100000000000000000000

## big-

### subtracts bigints

```scheme
(write (- 100000000000000000000 1))
```
---
    99999999999999999999

## big*

### multiplies bigints

```scheme
(write (* 10000000000 10000000000))
```
---
    100000000000000000000

## big<

### compares bigints

```scheme
(< 99999999999999999999 100000000000000000000)
```
---
    #t

## big=

### equal bigints

```scheme
(= 99999999999999999999 99999999999999999999)
```
---
    #t

## would-overflow-add?

### no overflow for small addition

```scheme
(if (Bigint would-overflow-add? 1 2) "y" "n")
```
---
    "n"

### overflow for large positive

```scheme
(Bigint would-overflow-mul? 3037000500 3037000500)
```
---
    #t

## would-overflow-mul?

### detects multiplication overflow

```scheme
(Bigint would-overflow-mul? 9999999999 9999999999)
```
---
    #t

### no overflow for small

```scheme
(if (Bigint would-overflow-mul? 2 3) "y" "n")
```
---
    "n"

## big+

### adds two bigints

```scheme
(write (Bigint + (Convert to 100 %bigint) (Convert to 200 %bigint)))
```
---
    300

### adds large bigints

```scheme
(write (Bigint + (Convert to 999999999999999999 %bigint) (Convert to 1 %bigint)))
```
---
    1000000000000000000

## big-

### subtracts bigints

```scheme
(write (Bigint - (Convert to 1000 %bigint) (Convert to 1 %bigint)))
```
---
    999

## big*

### multiplies bigints

```scheme
(write (Bigint * (Convert to 12345 %bigint) (Convert to 6789 %bigint)))
```
---
    83810205

### large multiply

```scheme
(Bigint bigint? (Bigint * (Convert to 999999999 %bigint) (Convert to 999999999 %bigint)))
```
---
    #t

## big/

### divides bigints

```scheme
(write (Bigint / (Convert to 100 %bigint) (Convert to 7 %bigint)))
```
---
    14

### divides with a multi-limb quotient

```scheme
(write (Bigint / (Convert to 99999999999999999999 %bigint) (Convert to 7 %bigint)))
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
(Bigint < (Convert to 1 %bigint) (Convert to 2 %bigint))
```
---
    #t

### not less than

```scheme
(Bigint < (Convert to 2 %bigint) (Convert to 1 %bigint))
```
---
    #f

## big=

### equal

```scheme
(Bigint = (Convert to 42 %bigint) (Convert to 42 %bigint))
```
---
    #t

### not equal

```scheme
(Bigint = (Convert to 1 %bigint) (Convert to 2 %bigint))
```
---
    #f
