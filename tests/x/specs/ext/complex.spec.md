# @lib ../tests/x/lib/complex.x

# complex

## complex literals

### integer real and imaginary

```scheme
(real-part 3+4i)
```
---
    3

### imaginary part of literal

```scheme
(imag-part 3+4i)
```
---
    4

### negative imaginary

```scheme
(imag-part 1-3i)
```
---
    -3

### float components

```scheme
(display 3.14+2.5i)
```
---
    3.14+2.5i

### pure imaginary

```scheme
(imag-part 5i)
```
---
    5

### pure imaginary real part is zero

```scheme
(real-part 5i)
```
---
    0

### zero imaginary collapses to real

```scheme
3+0i
```
---
    3

### i squared is minus one

```scheme
(* 0+1i 0+1i)
```
---
    -1

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
(= (magnitude (make-rectangular 3 4)) 5)
```
---
    #t

### magnitude of negative real

```scheme
(= (magnitude -7) 7)
```
---
    #t

### angle of positive real is zero

```scheme
(= (angle 5) 0)
```
---
    #t

### angle of negative real is pi

```scheme
(= (angle -1) %pi)
```
---
    #t

### angle of pure imaginary

```scheme
(= (angle (make-rectangular 0 1)) (Float / %pi 2.0))
```
---
    #t

## complex/

### complex division real part

```scheme
(real-part (complex/ (make-rectangular 4 2) (make-rectangular 2 0)))
```
---
    2

### complex division of conjugates

```scheme
(= (real-part (complex/ (make-rectangular 1 1) (make-rectangular 1 -1))) 0)
```
---
    #t

### complex division imaginary part

```scheme
(= (imag-part (complex/ (make-rectangular 1 1) (make-rectangular 1 -1))) 1)
```
---
    #t

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
(Float real? 42)
```
---
    #t

### complex with zero imaginary is real

```scheme
(Float real? (make-rectangular 5 0))
```
---
    #t

### complex with nonzero imaginary is not real

```scheme
(Float real? (make-rectangular 1 2))
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
