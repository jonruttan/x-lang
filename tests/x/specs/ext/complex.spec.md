# @lib ../tests/x/lib/complex.x

# complex

## complex literals

### integer real and imaginary

```scheme
(Complex real-part 3+4i)
```
---
    3

### imaginary part of literal

```scheme
(Complex imag-part 3+4i)
```
---
    4

### negative imaginary

```scheme
(Complex imag-part 1-3i)
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
(Complex imag-part 5i)
```
---
    5

### pure imaginary real part is zero

```scheme
(Complex real-part 5i)
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
(Complex real-part (Complex make-rectangular 3 4))
```
---
    3

### imaginary part is accessible

```scheme
(Complex imag-part (Complex make-rectangular 3 4))
```
---
    4

## real-part / imag-part

### real-part of integer is itself

```scheme
(Complex real-part 5)
```
---
    5

### imag-part of integer is zero

```scheme
(Complex imag-part 5)
```
---
    0

## complex arithmetic

### complex addition

```scheme
(Complex real-part (Complex + (Complex make-rectangular 1 2) (Complex make-rectangular 3 4)))
```
---
    4

### complex addition imaginary

```scheme
(Complex imag-part (Complex + (Complex make-rectangular 1 2) (Complex make-rectangular 3 4)))
```
---
    6

### complex subtraction

```scheme
(Complex real-part (Complex - (Complex make-rectangular 5 7) (Complex make-rectangular 2 3)))
```
---
    3

### complex multiplication real part

```scheme
(Complex real-part (Complex * (Complex make-rectangular 1 2) (Complex make-rectangular 3 4)))
```
---
    -5

### complex equality

```scheme
(Complex = (Complex make-rectangular 1 2) (Complex make-rectangular 1 2))
```
---
    #t

### complex inequality

```scheme
(Complex = (Complex make-rectangular 1 2) (Complex make-rectangular 1 3))
```
---
    #f

## magnitude / angle

### magnitude of 3+4i is 5

```scheme
(= (Complex magnitude (Complex make-rectangular 3 4)) 5)
```
---
    #t

### magnitude of negative real

```scheme
(= (Complex magnitude -7) 7)
```
---
    #t

### angle of positive real is zero

```scheme
(= (Complex angle 5) 0)
```
---
    #t

### angle of negative real is pi

```scheme
(= (Complex angle -1) %pi)
```
---
    #t

### angle of pure imaginary

```scheme
(= (Complex angle (Complex make-rectangular 0 1)) (Float / %pi 2.0))
```
---
    #t

## complex/

### complex division real part

```scheme
(Complex real-part (Complex / (Complex make-rectangular 4 2) (Complex make-rectangular 2 0)))
```
---
    2

### complex division of conjugates

```scheme
(= (Complex real-part (Complex / (Complex make-rectangular 1 1) (Complex make-rectangular 1 -1))) 0)
```
---
    #t

### complex division imaginary part

```scheme
(= (Complex imag-part (Complex / (Complex make-rectangular 1 1) (Complex make-rectangular 1 -1))) 1)
```
---
    #t

## make-polar

### make-polar with zero angle

```scheme
(Complex real-part (Complex make-polar 5 0))
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
(Float real? (Complex make-rectangular 5 0))
```
---
    #t

### complex with nonzero imaginary is not real

```scheme
(Float real? (Complex make-rectangular 1 2))
```
---
    #f

## complex?

### complex is complex

```scheme
(Complex complex? (Complex make-rectangular 1 2))
```
---
    #t

### integer is also complex (numeric tower)

```scheme
(Complex complex? 42)
```
---
    #t
