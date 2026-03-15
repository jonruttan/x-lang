# R5RS Numeric Tower

## rational arithmetic

### exact division produces rational

```scheme
(/ 3 4)
```
---
    3/4

### rational addition

```scheme
(+ 1/2 1/3)
```
---
    5/6

### rational multiplication

```scheme
(* 2/3 3/4)
```
---
    1/2

### exact division reduces

```scheme
(/ 6 4)
```
---
    3/2

### exact division integer result

```scheme
(/ 10 5)
```
---
    2

## predicates

### number? on rational

```scheme
(number? 3/4)
```
---
    #t

### complex? on integer

```scheme
(complex? 42)
```
---
    #t

### real? on rational

```scheme
(real? 3/4)
```
---
    #t

### rational? on integer

```scheme
(rational? 5)
```
---
    #t

### rational? on rational

```scheme
(rational? 3/4)
```
---
    #t

### exact? on rational

```scheme
(exact? 3/4)
```
---
    #t

### inexact? on float

```scheme
(inexact? 3.14)
```
---
    #t

## accessors

### numerator of rational

```scheme
(numerator 3/4)
```
---
    3

### denominator of rational

```scheme
(denominator 3/4)
```
---
    4

### numerator of integer

```scheme
(numerator 5)
```
---
    5

### denominator of integer

```scheme
(denominator 5)
```
---
    1

## conversion

### exact->inexact rational

```scheme
(exact->inexact 3/4)
```
---
    0.75

### quotient still works

```scheme
(quotient 10 3)
```
---
    3

### remainder still works

```scheme
(remainder 10 3)
```
---
    1

### modulo still works

```scheme
(modulo 10 3)
```
---
    1

## complex numbers

### make-rectangular

```scheme
(make-rectangular 3 4)
```
---
    3+4i

### real-part

```scheme
(real-part (make-rectangular 3 4))
```
---
    3

### imag-part

```scheme
(imag-part (make-rectangular 3 4))
```
---
    4

### complex addition

```scheme
(+ (make-rectangular 1 2) (make-rectangular 3 4))
```
---
    4+6i

### complex multiplication

```scheme
(* (make-rectangular 1 2) (make-rectangular 3 4))
```
---
    -5+10i

### magnitude

```scheme
(magnitude (make-rectangular 3 4))
```
---
    5

### real-part of real

```scheme
(real-part 5)
```
---
    5

### imag-part of real

```scheme
(imag-part 5)
```
---
    0

### complex with rational parts

```scheme
(make-rectangular 1/2 3/4)
```
---
    1/2+3/4i

## mixed promotion

### integer + rational

```scheme
(+ 1 1/2)
```
---
    3/2

### rational + float

```scheme
(+ 1/2 1.5)
```
---
    2

### integer + complex

```scheme
(+ 1 (make-rectangular 0 1))
```
---
    1+1i

### complex = check

```scheme
(= (make-rectangular 3 4) (make-rectangular 3 4))
```
---
    #t
