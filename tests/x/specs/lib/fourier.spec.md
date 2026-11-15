# Discrete Fourier transform (Fourier)
# @weight 2

`Fourier` plans a transform of one length: radix-2 for a power of two,
Bluestein's algorithm for every other length. `fft` / `ifft` make a plan
per call; `dft` / `idft` are the O(n^2) definition the fast paths are
checked against.

Where rounding enters, the cases compare within a tolerance: `near?` is the
largest distance between two vectors of numbers, below 1e-9.

## Exact small transforms

### a power of two, radix-2

```x
(import x/num/fourier)
(Fourier fft #(1 2 3 4))
```
---
    #(10.0+0.0i -2.0+2.0i -2.0+0.0i -2.0-2.0i)

### the definition gives the same

```x
(import x/num/fourier)
(Fourier dft #(1 2 3 4))
```
---
    #(10.0+0.0i -2.0+2.0i -2.0+0.0i -2.0-2.0i)

### an impulse transforms to a constant

```x
(import x/num/fourier)
(Fourier fft #(1 0 0 0 0 0 0 0))
```
---
    #(1.0+0.0i 1.0+0.0i 1.0+0.0i 1.0+0.0i 1.0+0.0i 1.0+0.0i 1.0+0.0i 1.0+0.0i)

### a constant transforms to an impulse

```x
(import x/num/fourier)
(Fourier ifft #(4 0 0 0))
```
---
    #(1.0+0.0i 1.0+0.0i 1.0+0.0i 1.0+0.0i)

### length 1 is the identity

```x
(import x/num/fourier)
(list (Fourier fft #(7)) (Fourier fft #(3+4i)))
```
---
    (#(7.0+0.0i) #(3.0+4.0i))

### a list is taken as a vector

```x
(import x/num/fourier)
(Fourier fft (list 1 2))
```
---
    #(3.0+0.0i -1.0+0.0i)

## Agreement with the definition

### radix-2 matches dft on complex input, n = 8

```x
(do (import x/num/fourier)
  (def near? (fn (_ a b)
    (< (Vector fold (fn (_ m x) (if (< m x) x m)) 0
         (Vector build (Vector length a)
           (fn (_ k) (Complex magnitude (- (Vector ref k a) (Vector ref k b))))))
       0.000000001)))
  (def v #(1 -2+1i 3.5 0+2i -1 4-3i 0.25 2))
  (near? (Fourier fft v) (Fourier dft v)))
```
---
    #t

### Bluestein matches dft for n = 3, 5, 6, 7, 12

```x
(do (import x/num/fourier)
  (def near? (fn (_ a b)
    (< (Vector fold (fn (_ m x) (if (< m x) x m)) 0
         (Vector build (Vector length a)
           (fn (_ k) (Complex magnitude (- (Vector ref k a) (Vector ref k b))))))
       0.000000001)))
  (def sig (fn (_ n) (Vector build n (fn (_ j) (Complex make (- (* j j) 3) (- 2 j))))))
  (List map (fn (_ n) (near? (Fourier fft (sig n)) (Fourier dft (sig n)))) (list 3 5 6 7 12)))
```
---
    (#t #t #t #t #t)

### the inverse matches idft for n = 6 and 8

```x
(do (import x/num/fourier)
  (def near? (fn (_ a b)
    (< (Vector fold (fn (_ m x) (if (< m x) x m)) 0
         (Vector build (Vector length a)
           (fn (_ k) (Complex magnitude (- (Vector ref k a) (Vector ref k b))))))
       0.000000001)))
  (def sig (fn (_ n) (Vector build n (fn (_ j) (Complex make (* 2 j) (- 5 j))))))
  (List map (fn (_ n) (near? (Fourier ifft (sig n)) (Fourier idft (sig n)))) (list 6 8)))
```
---
    (#t #t)

## Round trips

### inverse undoes forward on one plan, n = 16 and n = 10

```x
(do (import x/num/fourier)
  (def near? (fn (_ a b)
    (< (Vector fold (fn (_ m x) (if (< m x) x m)) 0
         (Vector build (Vector length a)
           (fn (_ k) (Complex magnitude (- (Vector ref k a) (Vector ref k b))))))
       0.000000001)))
  (List map (fn (_ n)
         (let ((p (Fourier plan n)) (v (Vector build n (fn (_ j) (- (* 3 j) 7)))))
           (near? (p inverse (p forward v)) v)))
       (list 16 10)))
```
---
    (#t #t)

### a plan is reused across inputs

```x
(import x/num/fourier)
(let ((p (Fourier plan 2)))
  (list (p forward #(1 2)) (p forward #(5 5)) (p size)))
```
---
    (#(3.0+0.0i -1.0+0.0i) #(10.0+0.0i 0.0+0.0i) 2)

## Split form in place

### forward! overwrites the two float vectors

```x
(import x/num/fourier)
(let ((re (Vector of 1.0 2.0 3.0 4.0)) (im (Vector of 0.0 0.0 0.0 0.0)))
  ((Fourier plan 4) forward! re im)
  (list re im))
```
---
    (#(10.0 -2.0 -2.0 -2.0) #(0.0 2.0 0.0 -2.0))

### inverse! returns them, on a Bluestein length

```x
(do (import x/num/fourier)
  (def re (Vector of 1.0 -2.0 0.5))
  (def im (Vector of 0.0 1.0 3.0))
  (def p (Fourier plan 3))
  (p inverse! re im)
  (p forward! re im)
  (list (< (Float abs (- (Vector ref 1 re) -2.0)) 0.000000001)
        (< (Float abs (- (Vector ref 2 im) 3.0)) 0.000000001)))
```
---
    (#t #t)

## Refusals

### a length below 1, a mismatched input, mismatched split vectors

```x
(import x/num/fourier)
(let ((p (Fourier plan 4)))
  (list (guard (e (Err label e)) (Fourier plan 0))
        (guard (e (Err label e)) (p forward #(1 2 3)))
        (guard (e (Err label e)) (p forward! (Vector of 1.0) (Vector of 1.0)))))
```
---
    ('value 'value 'value)
