## digit-value

### digit-value of 0

```scheme
(digit-value #\0)
```
---
    0

### digit-value of 5

```scheme
(digit-value #\5)
```
---
    5

### digit-value of 9

```scheme
(digit-value #\9)
```
---
    9

### digit-value of non-digit letter

```scheme
(null? (digit-value #\a))
```
---
    t

### digit-value of non-digit space

```scheme
(null? (digit-value #\space))
```
---
    t

### digit-value of non-digit symbol

```scheme
(null? (digit-value #\+))
```
---
    t

## string to vector conversion

### string->vector basic

```scheme
(equal? (string->vector "abc") (vector #\a #\b #\c))
```
---
    t

### string->vector empty

```scheme
(equal? (string->vector "") (vector))
```
---
    t

### string->vector single char

```scheme
(equal? (string->vector "x") (vector #\x))
```
---
    t

### vector->string basic

```scheme
(display (vector->string (vector #\h #\i)))
```
---
    hi

### vector->string empty

```scheme
(display (vector->string (vector)))
```
---

### vector->string single

```scheme
(display (vector->string (vector #\z)))
```
---
    z

### string->vector->string roundtrip

```scheme
(display (vector->string (string->vector "hello")))
```
---
    hello

### vector->string->vector roundtrip

```scheme
(equal? (string->vector (vector->string (vector #\a #\b #\c)))
        (vector #\a #\b #\c))
```
---
    t

## exact-integer-sqrt

### exact-integer-sqrt of perfect square 0

```scheme
(call-with-values (lambda () (exact-integer-sqrt 0))
  (lambda (s r) (list s r)))
```
---
    (0 0)

### exact-integer-sqrt of perfect square 1

```scheme
(call-with-values (lambda () (exact-integer-sqrt 1))
  (lambda (s r) (list s r)))
```
---
    (1 0)

### exact-integer-sqrt of perfect square 4

```scheme
(call-with-values (lambda () (exact-integer-sqrt 4))
  (lambda (s r) (list s r)))
```
---
    (2 0)

### exact-integer-sqrt of perfect square 9

```scheme
(call-with-values (lambda () (exact-integer-sqrt 9))
  (lambda (s r) (list s r)))
```
---
    (3 0)

### exact-integer-sqrt of perfect square 16

```scheme
(call-with-values (lambda () (exact-integer-sqrt 16))
  (lambda (s r) (list s r)))
```
---
    (4 0)

### exact-integer-sqrt of non-perfect 2

```scheme
(call-with-values (lambda () (exact-integer-sqrt 2))
  (lambda (s r) (list s r)))
```
---
    (1 1)

### exact-integer-sqrt of non-perfect 5

```scheme
(call-with-values (lambda () (exact-integer-sqrt 5))
  (lambda (s r) (list s r)))
```
---
    (2 1)

### exact-integer-sqrt of non-perfect 14

```scheme
(call-with-values (lambda () (exact-integer-sqrt 14))
  (lambda (s r) (list s r)))
```
---
    (3 5)

### exact-integer-sqrt invariant s^2+r=k

```scheme
(call-with-values (lambda () (exact-integer-sqrt 27))
  (lambda (s r) (= (+ (* s s) r) 27)))
```
---
    t

### exact-integer-sqrt of perfect square 100

```scheme
(call-with-values (lambda () (exact-integer-sqrt 100))
  (lambda (s r) (list s r)))
```
---
    (10 0)

## error objects

### error-object? on caught error

```scheme
(guard (e (error-object? e)) (error "oops"))
```
---
    t

### error-object-message on caught error

```scheme
(display (guard (e (error-object-message e)) (error "test message")))
```
---
    test message

### error-object-irritants returns list

```scheme
(guard (e (null? (error-object-irritants e))) (error "oops"))
```
---
    t

### error-object? on non-error

```scheme
(null? (error-object? 42))
```
---
    t

## char-ci comparisons (gap fill)

### char-ci<=? less

```scheme
(char-ci<=? #\a #\B)
```
---
    t

### char-ci<=? equal different case

```scheme
(char-ci<=? #\A #\a)
```
---
    t

### char-ci<=? not less or equal

```scheme
(null? (char-ci<=? #\c #\A))
```
---
    t

### char-ci>=? greater

```scheme
(char-ci>=? #\B #\a)
```
---
    t

### char-ci>=? equal different case

```scheme
(char-ci>=? #\a #\A)
```
---
    t

### char-ci>=? not greater or equal

```scheme
(null? (char-ci>=? #\A #\c))
```
---
    t

## string-ci comparisons (gap fill)

### string-ci<=? less

```scheme
(string-ci<=? "abc" "BCD")
```
---
    t

### string-ci<=? equal

```scheme
(string-ci<=? "ABC" "abc")
```
---
    t

### string-ci<=? not less or equal

```scheme
(null? (string-ci<=? "bcd" "ABC"))
```
---
    t

### string-ci>=? greater

```scheme
(string-ci>=? "BCD" "abc")
```
---
    t

### string-ci>=? equal

```scheme
(string-ci>=? "abc" "ABC")
```
---
    t

### string-ci>=? not greater or equal

```scheme
(null? (string-ci>=? "ABC" "bcd"))
```
---
    t

## floor-quotient and floor-remainder (gap fill)

### floor-quotient negative dividend

```scheme
(floor-quotient -7 2)
```
---
    -4

### floor-remainder negative dividend

```scheme
(floor-remainder -7 2)
```
---
    1

### floor-quotient negative divisor

```scheme
(floor-quotient 7 -2)
```
---
    -4

### floor-remainder negative divisor

```scheme
(floor-remainder 7 -2)
```
---
    -1

### floor-quotient both negative

```scheme
(floor-quotient -7 -2)
```
---
    3

### floor-remainder both negative

```scheme
(floor-remainder -7 -2)
```
---
    -1

### truncate-quotient negative

```scheme
(truncate-quotient -7 2)
```
---
    -3

### truncate-remainder negative

```scheme
(truncate-remainder -7 2)
```
---
    -1
