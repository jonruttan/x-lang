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

## multi-limb division (#401)

The old multi-limb arm subtracted its trial product unshifted: wrong
quotients once the dividend outgrew the divisor by more than one limb,
and an iteration count that scaled with the quotient's VALUE. Every
block here checks the q*b+r=a identity a broken quotient cannot fake.

### the #401 repro: 97b+5 over a two-limb b

```scheme
(let ((b (Bigint * 123456789 987654321)))
  (write (Bigint / (Bigint + (Bigint * b 97) 5) b)))
```
---
    97

### remainder of the repro

```scheme
(let ((b (Bigint * 123456789 987654321)))
  (write (Bigint % (Bigint + (Bigint * b 97) 5) b)))
```
---
    5

### exact multiple: b*b / b = b

```scheme
(let ((b (Bigint * 123456789 987654321)))
  (Bigint = b (Bigint / (Bigint * b b) b)))
```
---
    #t

### identity at limb gap 2

```scheme
(let ((b (Bigint * 123456789 987654321)))
  (let ((a (Bigint + (Bigint * b b) 1)))
    (let ((q (Bigint / a b)) (r (Bigint % a b)))
      (Bigint = a (Bigint + (Bigint * q b) r)))))
```
---
    #t

### identity at a large limb gap (formerly value-linear: never finished)

```scheme
(let ((p (fn (self x n) (if (= n 1) x (Bigint * x (self x (- n 1)))))))
  (let ((a (p 987654321987654321 11)) (b (p 987654321987654321 10)))
    (let ((q (Bigint / a b)) (r (Bigint % a b)))
      (if (Bigint = a (Bigint + (Bigint * q b) r)) (Bigint < r b) #f))))
```
---
    #t

### quotient of zero dividend limbs mid-stream

```scheme
(let ((b (Bigint * 999999999 999999999)))
  (write (Bigint / (Bigint * b 1000000000000000000) b)))
```
---
    1000000000000000000
