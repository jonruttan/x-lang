# @lib ../tests/x/lib/complex.x
# @weight 7

# complex

## complex literals

### integer real and imaginary

```x
(Complex real-part 3+4i)
```
---
    3

### imaginary part of literal

```x
(Complex imag-part 3+4i)
```
---
    4

### negative imaginary

```x
(Complex imag-part 1-3i)
```
---
    -3

### float components

```x
(display 3.14+2.5i)
```
---
    3.14+2.5i

### pure imaginary

```x
(Complex imag-part 5i)
```
---
    5

### pure imaginary real part is zero

```x
(Complex real-part 5i)
```
---
    0

### zero imaginary collapses to real

```x
3+0i
```
---
    3

### i squared is minus one

```x
(* 0+1i 0+1i)
```
---
    -1

## make

### constructs complex from real and imaginary parts

```x
(Complex real-part (Complex make 3 4))
```
---
    3

### imaginary part is accessible

```x
(Complex imag-part (Complex make 3 4))
```
---
    4

## real-part / imag-part

### real-part of integer is itself

```x
(Complex real-part 5)
```
---
    5

### imag-part of integer is zero

```x
(Complex imag-part 5)
```
---
    0

## complex arithmetic

### complex addition

```x
(Complex real-part (Complex + (Complex make 1 2) (Complex make 3 4)))
```
---
    4

### complex addition imaginary

```x
(Complex imag-part (Complex + (Complex make 1 2) (Complex make 3 4)))
```
---
    6

### complex subtraction

```x
(Complex real-part (Complex - (Complex make 5 7) (Complex make 2 3)))
```
---
    3

### complex multiplication real part

```x
(Complex real-part (Complex * (Complex make 1 2) (Complex make 3 4)))
```
---
    -5

### complex equality

```x
(Complex = (Complex make 1 2) (Complex make 1 2))
```
---
    #t

### complex inequality

```x
(Complex = (Complex make 1 2) (Complex make 1 3))
```
---
    #f

## magnitude / angle

### magnitude of 3+4i is 5

```x
(= (Complex magnitude (Complex make 3 4)) 5)
```
---
    #t

### magnitude of negative real

```x
(= (Complex magnitude -7) 7)
```
---
    #t

### angle of positive real is zero

```x
(= (Complex angle 5) 0)
```
---
    #t

### angle of negative real is pi

```x
(= (Complex angle -1) %pi)
```
---
    #t

### angle of pure imaginary

```x
(= (Complex angle (Complex make 0 1)) (Float / %pi 2.0))
```
---
    #t

## complex/

### complex division real part

```x
(Complex real-part (Complex / (Complex make 4 2) (Complex make 2 0)))
```
---
    2

### complex division of conjugates

```x
(= (Complex real-part (Complex / (Complex make 1 1) (Complex make 1 -1))) 0)
```
---
    #t

### complex division imaginary part

```x
(= (Complex imag-part (Complex / (Complex make 1 1) (Complex make 1 -1))) 1)
```
---
    #t

## from-polar

### from-polar with zero angle

```x
(Complex real-part (Complex from-polar 5 0))
```
---
    5.0

## real?

### integer is real

```x
(Float real? 42)
```
---
    #t

### complex with zero imaginary is real

```x
(Float real? (Complex make 5 0))
```
---
    #t

### complex with nonzero imaginary is not real

```x
(Float real? (Complex make 1 2))
```
---
    #f

## complex?

### complex is complex

```x
(Complex complex? (Complex make 1 2))
```
---
    #t

### integer is also complex (numeric tower)

```x
(Complex complex? 42)
```
---
    #t

## modulo

### % refuses instead of computing garbage

```x
(% 1+2i 2)
```
---
    Error: complex: % is undefined for complex numbers

## negative real part (#45 R4)

### -1+2i parses as a complex literal

```x
-1+2i
```
---
    -1+2i

### arithmetic on a negative-real literal

```x
(+ -1+2i 2)
```
---
    1+2i
