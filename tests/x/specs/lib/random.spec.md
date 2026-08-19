# Random number generation (Random)

`Random` is a source of random integers with a pluggable entropy backend.
`(Random sw)` / `(Random sw seed)` is a fast, non-cryptographic xorshift PRNG
written in pure x-lang; `(Random hw)` reads the kernel CSPRNG from
`/dev/urandom` through the filesystem. Both expose the same interface, so
`int` / `range` / `choice` / `shuffle` / ... work identically on either.

These tests assert *properties* (bounds, reproducibility, permutation
invariants) rather than exact draws, so they hold regardless of the seed
sequence.

## Software PRNG

### int lands in [0, n)

```scheme
(import x/num/random)
(let ((r (Random sw 42))) (let ((x (r int 6))) (and (>= x 0) (< x 6))))
```
---
    #t

### the same seed reproduces the same stream

```scheme
(import x/num/random)
(= ((Random sw 7) int 1000000) ((Random sw 7) int 1000000))
```
---
    #t

### seed! rewinds the stream

```scheme
(import x/num/random)
(let ((r (Random sw 1)))
  (let ((a (r int 1000000)))
    (r seed! 1)
    (= a (r int 1000000))))
```
---
    #t

### range lands in [lo, hi)

```scheme
(import x/num/random)
(let ((x ((Random sw 3) range 10 20))) (and (>= x 10) (< x 20)))
```
---
    #t

### between is inclusive -- a singleton interval is fixed

```scheme
(import x/num/random)
((Random sw 99) between 5 5)
```
---
    5

### bytes returns the requested count

```scheme
(import x/num/random)
(List length ((Random sw 8) bytes 5))
```
---
    5

### each byte is in [0, 256)

```scheme
(import x/num/random)
(let ((b (List ref 0 ((Random sw 8) bytes 1)))) (and (>= b 0) (< b 256)))
```
---
    #t

### choice returns a member of the list

```scheme
(import x/num/random)
(let ((xs (list 10 20 30)))
  (if (List includes? ((Random sw 5) choice xs) xs) #t #f))
```
---
    #t

### shuffle is a permutation (List length and sum preserved)

```scheme
(import x/num/random)
(let ((s ((Random sw 5) shuffle (list 1 2 3 4 5))))
  (and (= (List length s) 5)
       (= (List fold (fn (_ a x) (+ a x)) 0 s) 15)))
```
---
    #t

## Hardware RNG (/dev/urandom)

### hw int lands in [0, n)

```scheme
(import x/num/random)
(let ((x ((Random hw) int 100))) (and (>= x 0) (< x 100)))
```
---
    #t

### hw yields the requested number of bytes

```scheme
(import x/num/random)
(List length ((Random hw) bytes 8))
```
---
    8

## determinism

### same seed, same stream (rejection sampling included)

```scheme
(do (import x/num/random)
  (let ((a (Random sw 7)) (b (Random sw 7)))
    (equal? (a bytes 8) (b bytes 8))))
```
---
    #t

## float and sample (#363)

### float lands in [0, 1) and is a float

```scheme
(do (import x/num/random) (import x/num/float)
  (let ((r (Random sw 42)))
    (let ((f (r float)))
      (list (Float float? f)
            (Float < (Float from-int -1) f)
            (Float < f (Float from-int 1))))))
```
---
    (#t #t #t)

### float is reproducible under a seed

```scheme
(do (import x/num/random) (import x/num/float)
  (Float = ((Random sw 7) float) ((Random sw 7) float)))
```
---
    #t

### sample draws k distinct members, k=0 draws none

```scheme
(do (import x/num/random)
  (let ((drawn ((Random sw 5) sample 3 (list 1 2 3 4 5))))
    (list (List length drawn)
          (List all? (fn (_ x) (List includes? x (list 1 2 3 4 5))) drawn)
          (= (List length (List distinct drawn)) 3)
          ((Random sw 5) sample 0 (list 1 2)))))
```
---
    (3 #t #t ())

### sample beyond the population raises 'value

```scheme
(do (import x/num/random)
  (list (guard (e (Err kind-of e)) ((Random sw 1) sample 3 (list 1 2)))))
```
---
    ('value)
