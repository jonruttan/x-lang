# @lib x-base.x

# complex

## make-rectangular

### constructs complex from real and imaginary parts

```scheme
(real-part (make-rectangular 3 4))
```
---
    3

### imaginary part is accessible

```scheme
(imag-part (make-rectangular 3 4))
```
---
    4

## real-part / imag-part

### real-part of integer is itself

```scheme
(real-part 5)
```
---
    5

### imag-part of integer is zero

```scheme
(imag-part 5)
```
---
    0

## complex arithmetic

### complex addition

```scheme
(real-part (complex+ (make-rectangular 1 2) (make-rectangular 3 4)))
```
---
    4

### complex addition imaginary

```scheme
(imag-part (complex+ (make-rectangular 1 2) (make-rectangular 3 4)))
```
---
    6

### complex subtraction

```scheme
(real-part (complex- (make-rectangular 5 7) (make-rectangular 2 3)))
```
---
    3

### complex multiplication real part

```scheme
(real-part (complex* (make-rectangular 1 2) (make-rectangular 3 4)))
```
---
    -5

### complex equality

```scheme
(complex= (make-rectangular 1 2) (make-rectangular 1 2))
```
---
    #t

### complex inequality

```scheme
(complex= (make-rectangular 1 2) (make-rectangular 1 3))
```
---
    #f

## magnitude / angle

### magnitude of 3+4i is 5

```scheme
(magnitude (make-rectangular 3 4))
```
---
    5

## make-polar

### make-polar with zero angle

```scheme
(real-part (make-polar 5 0))
```
---
    5

## real?

### integer is real

```scheme
(real? 42)
```
---
    #t

### complex with zero imaginary is real

```scheme
(real? (make-rectangular 5 0))
```
---
    #t

### complex with nonzero imaginary is not real

```scheme
(real? (make-rectangular 1 2))
```
---
    #f

## complex?

### complex is complex

```scheme
(complex? (make-rectangular 1 2))
```
---
    #t

### integer is also complex (numeric tower)

```scheme
(complex? 42)
```
---
    #t
