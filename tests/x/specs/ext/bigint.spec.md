# @lib ../tests/x/lib/bigint.x
# @weight 2

## bigint literal

### parses large number

```x
(Bigint bigint? 99999999999999999999)
```
---
    #t

### small numbers stay native

```x
(if (Bigint bigint? 42) "big" "native")
```
---
    "native"

### displays correctly

```x
(write 10000000000000000000)
```
---
    10000000000000000000

### negative bigint

```x
(write -99999999999999999999)
```
---
    -99999999999999999999

## overflow promotion

### multiplication overflow promotes

```x
(Bigint bigint? (* 999999999999 999999999999))
```
---
    #t

### multiplication result correct

```x
(write (* 999999999999 999999999999))
```
---
    999999999998000000000001

### addition overflow promotes

```x
(Bigint bigint? (+ 9223372036854775807 1))
```
---
    #t

## big+

### adds two bigints

```x
(write (+ 99999999999999999999 1))
```
---
    100000000000000000000

## big-

### subtracts bigints

```x
(write (- 100000000000000000000 1))
```
---
    99999999999999999999

## big*

### multiplies bigints

```x
(write (* 10000000000 10000000000))
```
---
    100000000000000000000

## big<

### compares bigints

```x
(< 99999999999999999999 100000000000000000000)
```
---
    #t

## big=

### equal bigints

```x
(= 99999999999999999999 99999999999999999999)
```
---
    #t

## would-overflow-add?

### no overflow for small addition

```x
(if (Bigint would-overflow-add? 1 2) "y" "n")
```
---
    "n"

### overflow for large positive

```x
(Bigint would-overflow-mul? 3037000500 3037000500)
```
---
    #t

### no overflow adding zero to a large negative

```x
(if (Bigint would-overflow-add? 0 -1000000000) "y" "n")
```
---
    "n"

### no overflow for a small negative plus a large negative

```x
(if (Bigint would-overflow-add? -1 -1000000000) "y" "n")
```
---
    "n"

### no overflow adding zero to the most negative

The guard's domain is plain native ints, and the reader promotes long
literals, so the edge operands are computed: 3037000499 squared is the
largest native square, and the trim reaches LONG_MIN exactly.

```x
(let ((m (- (- 0 (* 3037000499 3037000499)) 5928526807)))
  (if (Bigint would-overflow-add? 0 m) "y" "n"))
```
---
    "n"

### overflow for two large negatives

```x
(let ((n (- 0 (* 3037000499 3037000499))))
  (Bigint would-overflow-add? n n))
```
---
    #t

### overflow one below the most negative

```x
(let ((m (- (- 0 (* 3037000499 3037000499)) 5928526807)))
  (Bigint would-overflow-add? m -1))
```
---
    #t

### a sum that fits stays native

```x
(if (Bigint bigint? (+ 0 -1000000000)) "big" "native")
```
---
    "native"

### negative minus digit stays native (regression: wrapped threshold)

```x
(if (Bigint bigint? (- -99999999990 9)) "big" "native")
```
---
    "native"

### negative minus digit answers a value-eq native int

```x
(eq? (- -99999999990 9) -99999999999)
```
---
    #t

## demotion window (regression: 2+ limb results never demoted)

### bigint difference that fits native demotes

```x
(eq? (- 99999999999999999999 99999999990000000000) 9999999999)
```
---
    #t

### 19-digit quotient that fits native demotes

```x
(eq? (/ 10000000000000000000 10) 1000000000000000000)
```
---
    #t

### str->number reads 11 digits of nines (regression: stealth bigint failed its verify)

```x
(%str->number "99999999999")
```
---
    99999999999

### negative subtraction that fits stays native

```x
(if (Bigint bigint? (- 0 1000000000)) "big" "native")
```
---
    "native"

## would-overflow-mul?

### detects multiplication overflow

```x
(Bigint would-overflow-mul? 9999999999 9999999999)
```
---
    #t

### no overflow for small

```x
(if (Bigint would-overflow-mul? 2 3) "y" "n")
```
---
    "n"

## big+

### adds two bigints

```x
(write (Bigint + (Convert to 100 %bigint) (Convert to 200 %bigint)))
```
---
    300

### adds large bigints

```x
(write (Bigint + (Convert to 999999999999999999 %bigint) (Convert to 1 %bigint)))
```
---
    1000000000000000000

## big-

### subtracts bigints

```x
(write (Bigint - (Convert to 1000 %bigint) (Convert to 1 %bigint)))
```
---
    999

## big*

### multiplies bigints

```x
(write (Bigint * (Convert to 12345 %bigint) (Convert to 6789 %bigint)))
```
---
    83810205

### large multiply

```x
(Bigint bigint? (Bigint * (Convert to 99999999999 %bigint) (Convert to 99999999999 %bigint)))
```
---
    #t

### product that fits native demotes

```x
(if (Bigint bigint? (Bigint * (Convert to 999999999 %bigint) (Convert to 999999999 %bigint))) "big" "native")
```
---
    "native"

### demoted product has the native value

```x
(eq? (Bigint * (Convert to 999999999 %bigint) (Convert to 999999999 %bigint)) 999999998000000001)
```
---
    #t

## big/

### divides bigints

```x
(write (Bigint / (Convert to 100 %bigint) (Convert to 7 %bigint)))
```
---
    14

### divides with a multi-limb quotient

```x
(write (Bigint / (Convert to 99999999999999999999 %bigint) (Convert to 7 %bigint)))
```
---
    14285714285714285714

### remainder dispatches through the generic %

```x
(% 99999999999999999999 7)
```
---
    1

## big<

### less than

```x
(Bigint < (Convert to 1 %bigint) (Convert to 2 %bigint))
```
---
    #t

### not less than

```x
(Bigint < (Convert to 2 %bigint) (Convert to 1 %bigint))
```
---
    #f

## big=

### equal

```x
(Bigint = (Convert to 42 %bigint) (Convert to 42 %bigint))
```
---
    #t

### not equal

```x
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

```x
(let ((b (Bigint * 123456789 987654321)))
  (write (Bigint / (Bigint + (Bigint * b 97) 5) b)))
```
---
    97

### remainder of the repro

```x
(let ((b (Bigint * 123456789 987654321)))
  (write (Bigint % (Bigint + (Bigint * b 97) 5) b)))
```
---
    5

### exact multiple: b*b / b = b

```x
(let ((b (Bigint * 123456789 987654321)))
  (Bigint = b (Bigint / (Bigint * b b) b)))
```
---
    #t

### identity at limb gap 2

```x
(let ((b (Bigint * 123456789 987654321)))
  (let ((a (Bigint + (Bigint * b b) 1)))
    (let ((q (Bigint / a b)) (r (Bigint % a b)))
      (Bigint = a (Bigint + (Bigint * q b) r)))))
```
---
    #t

### identity at a large limb gap (formerly value-linear: never finished)

```x
(let ((p (fn (self x n) (if (= n 1) x (Bigint * x (self x (- n 1)))))))
  (let ((a (p 987654321987654321 11)) (b (p 987654321987654321 10)))
    (let ((q (Bigint / a b)) (r (Bigint % a b)))
      (if (Bigint = a (Bigint + (Bigint * q b) r)) (Bigint < r b) #f))))
```
---
    #t

### quotient of zero dividend limbs mid-stream

```x
(let ((b (Bigint * 999999999 999999999)))
  (write (Bigint / (Bigint * b 1000000000000000000) b)))
```
---
    1000000000000000000
