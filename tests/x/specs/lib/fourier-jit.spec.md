# Fourier compiled kernels

# @weight 6
# @timeout-scale 4

The compiled kernels behind `(Fourier jit!)`: the radix-2 and pointwise
word forms of x/num/fourier, compiled by compile-asm with its double
operations and adopted only after they write the same bits as their pure
twins on a radix-2 and a Bluestein transform. These cases re-prove the
transforms through the class, and that the plans keep their own heap flat.

`near?` is the largest distance between two vectors of numbers, below
1e-9.

A double fills one word only on an 8-byte word, so on a 4-byte word the
compile refuses: there `jit!` and `compiled?` answer #f and the hand-over
loop runs a few pure turns. The cases that time the compiled kernels at
size answer their expected value there unrun, as jit-double's do; the pure
kernels on that word are lib/fourier.spec.md's.

## the lane

### the pure kernels hand over on their own

The transforms build the compiled kernels once the pure ones have run
about a compile's worth of steps, and the transform in progress carries
on in them. Every transform answers what the first, all pure, did: the
compiled kernels write the pure kernels' bits.

```x
(do (import x/num/fourier)
  (def near? (fn (_ a b)
    (< (Vector fold (fn (_ m x) (if (< m x) x m)) 0
         (Vector build (Vector length a)
           (fn (_ k) (Complex magnitude (- (Vector ref k a) (Vector ref k b))))))
       (/ 1 1000000000))))
  (def p (Fourier plan 256))
  (def v (Vector build 256 (fn (_ j) (Complex make (- (% (* j 7) 13) 6) (- 3 (% j 5))))))
  (def first-x (p forward v))
  (def w8 (= %word-size 8))
  (def run (fn (self i ok) (if (if (Fourier compiled?) #t (< (if w8 40 2) i)) ok (self (+ i 1) (if (near? (p forward v) first-x) ok #f)))))
  (def ok (run 0 #t))
  (list (eq? (Fourier compiled?) w8) ok (near? (p forward v) first-x)))
```
---
    (#t #t #t)

### jit! adopts, and is idempotent

```x
(do (import x/num/fourier)
  (def w8 (= %word-size 8))
  (list (eq? (Fourier jit!) w8) (eq? (Fourier jit!) w8) (eq? (Fourier compiled?) w8)))
```
---
    (#t #t #t)

## compiled transforms

### the exact small transform

```x
(do (import x/num/fourier)
  (Fourier jit!)
  (Fourier fft #(1 2 3 4)))
```
---
    #(10.0+0.0i -2.0+2.0i -2.0+0.0i -2.0-2.0i)

### radix-2 and Bluestein match the definition: n = 64, 100, 127

```x
(if (< %word-size 8) (list #t #t #t)
  (do (import x/num/fourier)
    (Fourier jit!)
    (def near? (fn (_ a b)
      (< (Vector fold (fn (_ m x) (if (< m x) x m)) 0
           (Vector build (Vector length a)
             (fn (_ k) (Complex magnitude (- (Vector ref k a) (Vector ref k b))))))
         0.000000001)))
    (def sig (fn (_ n) (Vector build n (fn (_ j) (Complex make (- (% (* j j) 17) 8) (- 2 (% j 3)))))))
    (List map (fn (_ n) (near? (Fourier fft (sig n)) (Fourier dft (sig n)))) (list 64 100 127))))
```
---
    (#t #t #t)

### a 4096-point round trip in place

```x
(if (< %word-size 8) #t
  (do (import x/num/fourier)
    (Fourier jit!)
    (def p (Fourier plan 4096))
    (def re (Vector build 4096 (fn (_ j) (Float from (- (% (* j 31) 101) 50)))))
    (def im (Vector build 4096 (fn (_ j) (Float from (% j 7)))))
    (def re0 (Vector map (fn (_ x) x) re))
    (p forward! re im)
    (p inverse! re im)
    (< (Vector fold (fn (_ m k) (let ((d (Float abs (- (Vector ref k re) (Vector ref k re0))))) (if (< m d) d m)))
         0 (Vector build 4096 (fn (_ k) k)))
       0.000001)))
```
---
    #t

## memory

### a loop of transforms keeps the heap flat

Three hundred 256-point transforms through the converting doors churn
about thirty million objects; the plan collects as its debt passes its
window, so the heap ends within a window of where it began.

```x
(if (< %word-size 8) #t
  (do (import x/num/fourier) (import x/sys/gc)
    (Fourier jit!)
    (def p (Fourier plan 256))
    (def v (Vector build 256 (fn (_ j) (- j 9))))
    (Heap collect)
    (def c0 (Heap count))
    (def run (fn (self i) (if (< i 300) (do (p forward v) (self (+ i 1))) i)))
    (def ok (run 0 #t))
    (< (- (Heap count) c0) 6000000)))
```
---
    #t
