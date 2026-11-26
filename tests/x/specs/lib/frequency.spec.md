# Discrete Fourier transform (Frequency)
# @weight 2

`Frequency` plans a transform of one length: radix-2 for a power of two,
Bluestein's algorithm for every other length. `fft` / `ifft` make a plan
per call; `dft` / `idft` are the O(n^2) definition the fast paths are
checked against.

Where rounding enters, the cases compare within a tolerance: `near?` is the
largest distance between two vectors of numbers, below 1e-9.

## Exact small transforms

### a power of two, radix-2

```x
(import x/num/frequency)
(Frequency fft #(1 2 3 4))
```
---
    #(10.0+0.0i -2.0+2.0i -2.0+0.0i -2.0-2.0i)

### the definition gives the same

```x
(import x/num/frequency)
(Frequency dft #(1 2 3 4))
```
---
    #(10.0+0.0i -2.0+2.0i -2.0+0.0i -2.0-2.0i)

### an impulse transforms to a constant

```x
(import x/num/frequency)
(Frequency fft #(1 0 0 0 0 0 0 0))
```
---
    #(1.0+0.0i 1.0+0.0i 1.0+0.0i 1.0+0.0i 1.0+0.0i 1.0+0.0i 1.0+0.0i 1.0+0.0i)

### a constant transforms to an impulse

```x
(import x/num/frequency)
(Frequency ifft #(4 0 0 0))
```
---
    #(1.0+0.0i 1.0+0.0i 1.0+0.0i 1.0+0.0i)

### length 1 is the identity

```x
(import x/num/complex/literal)
(import x/num/frequency)
(list (Frequency fft #(7)) (Frequency fft #(3+4i)))
```
---
    (#(7.0+0.0i) #(3.0+4.0i))

### a list is taken as a vector

```x
(import x/num/frequency)
(Frequency fft (list 1 2))
```
---
    #(3.0+0.0i -1.0+0.0i)

## Agreement with the definition

### radix-2 matches dft on complex input, n = 8

```x
(import x/num/float/literal)
(import x/num/complex/literal)
(do (import x/num/frequency)
  (def near? (fn (_ a b)
    (< (Vector fold (fn (_ m x) (if (< m x) x m)) 0
         (Vector build (Vector length a)
           (fn (_ k) (Complex magnitude (- (Vector ref k a) (Vector ref k b))))))
       0.000000001)))
  (def v #(1 -2+1i 3.5 0+2i -1 4-3i 0.25 2))
  (near? (Frequency fft v) (Frequency dft v)))
```
---
    #t

### Bluestein matches dft for n = 3, 5, 6, 7, 12

```x
(import x/num/float/literal)
(do (import x/num/frequency)
  (def near? (fn (_ a b)
    (< (Vector fold (fn (_ m x) (if (< m x) x m)) 0
         (Vector build (Vector length a)
           (fn (_ k) (Complex magnitude (- (Vector ref k a) (Vector ref k b))))))
       0.000000001)))
  (def sig (fn (_ n) (Vector build n (fn (_ j) (Complex make (- (* j j) 3) (- 2 j))))))
  (List map (fn (_ n) (near? (Frequency fft (sig n)) (Frequency dft (sig n)))) (list 3 5 6 7 12)))
```
---
    (#t #t #t #t #t)

### the inverse matches idft for n = 6 and 8

```x
(import x/num/float/literal)
(do (import x/num/frequency)
  (def near? (fn (_ a b)
    (< (Vector fold (fn (_ m x) (if (< m x) x m)) 0
         (Vector build (Vector length a)
           (fn (_ k) (Complex magnitude (- (Vector ref k a) (Vector ref k b))))))
       0.000000001)))
  (def sig (fn (_ n) (Vector build n (fn (_ j) (Complex make (* 2 j) (- 5 j))))))
  (List map (fn (_ n) (near? (Frequency ifft (sig n)) (Frequency idft (sig n)))) (list 6 8)))
```
---
    (#t #t)

## Round trips

### inverse undoes forward on one plan, n = 16 and n = 10

```x
(import x/num/float/literal)
(do (import x/num/frequency)
  (def near? (fn (_ a b)
    (< (Vector fold (fn (_ m x) (if (< m x) x m)) 0
         (Vector build (Vector length a)
           (fn (_ k) (Complex magnitude (- (Vector ref k a) (Vector ref k b))))))
       0.000000001)))
  (List map (fn (_ n)
         (let ((p (Frequency plan n)) (v (Vector build n (fn (_ j) (- (* 3 j) 7)))))
           (near? (p inverse (p forward v)) v)))
       (list 16 10)))
```
---
    (#t #t)

### a plan is reused across inputs

```x
(import x/num/frequency)
(let ((p (Frequency plan 2)))
  (list (p forward #(1 2)) (p forward #(5 5)) (p size)))
```
---
    (#(3.0+0.0i -1.0+0.0i) #(10.0+0.0i 0.0+0.0i) 2)

## Split form in place

### forward! overwrites the two float vectors

```x
(import x/num/float/literal)
(import x/num/frequency)
(let ((re (Vector of 1.0 2.0 3.0 4.0)) (im (Vector of 0.0 0.0 0.0 0.0)))
  ((Frequency plan 4) forward! re im)
  (list re im))
```
---
    (#(10.0 -2.0 -2.0 -2.0) #(0.0 2.0 0.0 -2.0))

### inverse! returns them, on a Bluestein length

```x
(import x/num/float/literal)
(do (import x/num/frequency)
  (def re (Vector of 1.0 -2.0 0.5))
  (def im (Vector of 0.0 1.0 3.0))
  (def p (Frequency plan 3))
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
(import x/num/float/literal)
(import x/num/frequency)
(let ((p (Frequency plan 4)))
  (list (guard (e (Err label e)) (Frequency plan 0))
        (guard (e (Err label e)) (p forward #(1 2 3)))
        (guard (e (Err label e)) (p forward! (Vector of 1.0) (Vector of 1.0)))))
```
---
    ('value 'value 'value)

## The spectrum of frames

`spectrum!` reads signed 16-bit little-endian stereo frames, a mixer's
block, in place. `frames` makes a region of N frames from a function of the
frame giving (LEFT . RIGHT), and `tone` is a sine of K cycles over 256
frames. With h = 129, eight bands of a 256-point plan have the edges
1 2 3 6 11 20 38 70 129, the floor of h^(b/8) at least one past the last,
so bin 16 is in band 4, bins 11 to 19.

### a sine's power is in the band that holds its bin

```x
(do (import x/num/frequency) (import x/num/float pi)
  (import x/core/doors ptr-set! str->ptr str-make int& int>>)
  (def frames (fn (_ n f)
    (def r (str-make (* 4 n)))
    (def put (fn (_ at v) (ptr-set! (str->ptr r) at (int& v 255) 1) (ptr-set! (str->ptr r) (+ at 1) (int& (int>> v 8) 255) 1)))
    ((fn (self j) (when (< j n) (do (put (* 4 j) (first (f j))) (put (+ 2 (* 4 j)) (rest (f j))) (self (+ j 1))))) 0)
    r))
  (def tone (fn (_ k j) (Float ->int (* 8000 (Float sin (/ (* 2 pi k j) 256))))))
  (def out ((Frequency plan 256) spectrum! (frames 256 (fn (_ j) (pair (tone 16 j) 0))) 256 'left (Vector make 8 ())))
  (Vector fold (fn (_ m k) (if (< (Vector ref m out) (Vector ref k out)) k m)) 0 (Vector build 8 (fn (_ k) k))))
```
---
    4

### a channel is read alone, and both adds the two

The right channel of a sound only on the left is silent. The same sine in
both channels is twice the amplitude of one, so four times its power: the
doubling is exact in doubles, through the window and the transform.

```x
(do (import x/num/frequency) (import x/num/float pi)
  (import x/core/doors ptr-set! str->ptr str-make int& int>>)
  (def frames (fn (_ n f)
    (def r (str-make (* 4 n)))
    (def put (fn (_ at v) (ptr-set! (str->ptr r) at (int& v 255) 1) (ptr-set! (str->ptr r) (+ at 1) (int& (int>> v 8) 255) 1)))
    ((fn (self j) (when (< j n) (do (put (* 4 j) (first (f j))) (put (+ 2 (* 4 j)) (rest (f j))) (self (+ j 1))))) 0)
    r))
  (def tone (fn (_ k j) (Float ->int (* 8000 (Float sin (/ (* 2 pi k j) 256))))))
  (def p (Frequency plan 256))
  (def left (frames 256 (fn (_ j) (pair (tone 16 j) 0))))
  (def same (frames 256 (fn (_ j) (pair (tone 16 j) (tone 16 j)))))
  (def right (p spectrum! left 256 'right (Vector make 8 ())))
  (def one (Vector ref 4 (p spectrum! left 256 'left (Vector make 8 ()))))
  (def two (Vector ref 4 (p spectrum! same 256 'both (Vector make 8 ()))))
  (list (Vector fold (fn (_ ok x) (if ok (= x 0) #f)) #t right) (/ two one)))
```
---
    (#t 4.0)

### fewer frames than the plan's length are padded, and nothing past them is read

```x
(do (import x/num/frequency) (import x/num/float pi)
  (import x/core/doors ptr-set! str->ptr str-make int& int>>)
  (def frames (fn (_ n f)
    (def r (str-make (* 4 n)))
    (def put (fn (_ at v) (ptr-set! (str->ptr r) at (int& v 255) 1) (ptr-set! (str->ptr r) (+ at 1) (int& (int>> v 8) 255) 1)))
    ((fn (self j) (when (< j n) (do (put (* 4 j) (first (f j))) (put (+ 2 (* 4 j)) (rest (f j))) (self (+ j 1))))) 0)
    r))
  (def tone (fn (_ k j) (Float ->int (* 8000 (Float sin (/ (* 2 pi k j) 256))))))
  (def p (Frequency plan 256))
  (def quiet (frames 256 (fn (_ j) (if (< j 128) (pair (tone 5 j) 0) (pair 0 0)))))
  (def loud (frames 256 (fn (_ j) (if (< j 128) (pair (tone 5 j) 0) (pair 30000 -30000)))))
  (equal? (p spectrum! quiet 128 'left (Vector make 8 ())) (p spectrum! loud 128 'left (Vector make 8 ()))))
```
---
    #t

### a count, a channel or a band count the plan cannot take is refused

```x
(do (import x/num/frequency) (import x/core/doors str-make)
  (def p (Frequency plan 8))
  (def r (str-make 64))
  (list (guard (e (Err label e)) (p spectrum! r 9 'left (Vector make 2 ())))
        (guard (e (Err label e)) (p spectrum! r 0 'left (Vector make 2 ())))
        (guard (e (Err label e)) (p spectrum! r 8 'middle (Vector make 2 ())))
        (guard (e (Err label e)) (p spectrum! r 8 'left (Vector make 5 ())))))
```
---
    ('value 'value 'value 'value)

## Memory

### the pure kernels collect their own garbage

Six 256-point transforms on the pure kernels churn about eight million
objects; the plan collects as its debt passes its window, so the heap
ends within a window of where it began.

```x
(do (import x/num/frequency) (import x/sys/gc)
  (def p (Frequency plan 256))
  (def v (Vector build 256 (fn (_ j) (- j 9))))
  (Heap collect)
  (def c0 (Heap count))
  (def run (fn (self i) (if (< i 6) (do (p forward v) (self (+ i 1))) i)))
  (run 0)
  (list (Frequency compiled?) (< (- (Heap count) c0) 6000000)))
```
---
    (#f #t)

## Other names

### the class carries the names texts use

```x
(import x/num/frequency)
((Doc entry 'Frequency) known-as)
```
---
    ("Fourier transform" "FFT" "DFT")
