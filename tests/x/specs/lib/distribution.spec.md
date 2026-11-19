# probability distributions (Distribution)
# @weight 4

A distribution is a value made by a constructor of the Distribution class
with its parameters, answering its density, cumulative, survival and
quantile, mean, variance and deviation, each a Float. The expected values
are those of SciPy's `scipy.stats` to the digits printed.

## The normal distribution

### every constructor answers a Distribution

```x
(import x/num/distribution)
(List map (fn (_ d) (instance-of? d Distribution))
  (list (Distribution normal) (Distribution uniform) (Distribution exponential) (Distribution gamma 2)
        (Distribution chi-squared 3) (Distribution standardized-mean 5) (Distribution variance-ratio 3 10)))
```
---
    (#t #t #t #t #t #t #t)

### density, cumulative and survival of the standard normal

```x
(import x/num/distribution)
(let ((n (Distribution normal)))
  (list (n density 0) (n cumulative 1.96) (n survival 1.96) (n cumulative 0) (n cumulative -3)))
```
---
    (0.398942280401433 0.97500210485178 0.0249978951482204 0.5 0.0013498980316301)

### quantiles in the centre and both tails

```x
(import x/num/distribution)
(let ((n (Distribution normal 0 1)))
  (List map (fn (_ p) (n quantile p)) '(0.5 0.975 0.025 0.001 0.999 0.000001 0.999999)))
```
---
    (0.0 1.95996398454005 -1.95996398454005 -3.09023230616781 3.09023230616781 -4.7534243088229 4.75342430881709)

### the cumulative of the quantile is p

```x
(import x/num/distribution)
(let ((n (Distribution normal)))
  (List map (fn (_ p) (n cumulative (n quantile p))) '(0.1 0.3 0.7 0.9 0.02 0.98 0.0001)))
```
---
    (0.1 0.3 0.7 0.9 0.02 0.98 0.0001)

### a mean and deviation shift and scale it

```x
(import x/num/distribution)
(let ((n (Distribution normal 10 2)))
  (list (n quantile 0.5) (n cumulative 12) (n density 10) (n mean) (n variance) (n deviation)))
```
---
    (10.0 0.841344746068543 0.199471140200716 10.0 4.0 2.0)

### p 0 and 1 answer minus and plus infinity

```x
(import x/num/distribution)
(let ((n (Distribution normal))) (list (n quantile 0) (n quantile 1)))
```
---
    (-inf inf)

## The uniform distribution

### density, cumulative, survival and quantile

```x
(import x/num/distribution)
(let ((u (Distribution uniform 0 4)))
  (list (u density 1) (u density 5) (u cumulative -1) (u cumulative 3) (u cumulative 9)
        (u survival 3) (u quantile 0.5)))
```
---
    (0.25 0.0 0.0 0.75 1.0 0.25 2.0)

### mean, variance and deviation, and the default bounds

```x
(import x/num/distribution)
(list ((Distribution uniform 2 6) mean) ((Distribution uniform 0 6) variance) ((Distribution uniform 0 12) deviation)
      ((Distribution uniform) mean))
```
---
    (4.0 3.0 3.46410161513775 0.5)

## The exponential distribution

### density, cumulative, survival and quantile

```x
(import x/num/distribution)
(let ((e (Distribution exponential 2)))
  (list (e density 0) (e density -1) (e cumulative 1) (e survival 1) (e quantile 0.5) (e quantile 0) (e quantile 1)))
```
---
    (2.0 0.0 0.864664716763387 0.135335283236613 0.346573590279973 0.0 inf)

### mean, variance and deviation

```x
(import x/num/distribution)
(let ((e (Distribution exponential 2))) (list (e mean) (e variance) (e deviation) ((Distribution exponential) mean)))
```
---
    (0.5 0.25 0.5 1.0)

## The gamma distribution

### density, cumulative and survival of a shape and a rate

```x
(import x/num/distribution)
(let ((g (Distribution gamma 2 3)))
  (list (g density 0.5) (g cumulative 0.5) (g survival 0.5) (g cumulative 3) (g survival 3) (g cumulative -1)))
```
---
    (1.00408572066793 0.442174599628925 0.557825400371075 0.998765901959133 0.0012340980408668 0.0)

### quantiles in the centre and both tails

```x
(import x/num/distribution)
(let ((g (Distribution gamma 2 3)))
  (list (g quantile 0.5) (g quantile 0.975) (g quantile 0.001) (g quantile 0) (g quantile 1)))
```
---
    (0.55944899667222 1.8572144636463 0.0151340059231632 0.0 inf)

### mean, variance and deviation, and the default rate

```x
(import x/num/distribution)
(let ((g (Distribution gamma 2 3)))
  (list (g mean) (g variance) (g deviation) ((Distribution gamma 2) mean)))
```
---
    (0.666666666666667 0.222222222222222 0.471404520791032 2.0)

### a shape below 1: an infinite density at 0, and a quantile near 0

```x
(import x/num/distribution)
(let ((g (Distribution gamma 0.5)))
  (list (g density 0) (g density 0.1) (g cumulative 0.1) (g survival 20) (g quantile 0.01) (g quantile 0.99)
        (g quantile 1.0e-10)))
```
---
    (inf 1.61434225871536 0.345279153981423 2.53962858947086e-10 7.8543928954851e-05 3.31744830051061 7.85398163397448e-21)

### a large shape

```x
(import x/num/distribution)
(let ((g (Distribution gamma 100 2)))
  (list (g cumulative 50) (g survival 70) (g quantile 0.5) (g quantile 0.999)))
```
---
    (0.513298798279131 0.000161057174712541 49.8334324596584 66.8851319556892)

### shape 1 is the exponential

```x
(import x/num/distribution)
(import x/num/float f-sub f-lt)
(def %close? (fn (_ a b) (let ((d (f-sub a b))) (if (f-lt d 1.0e-12) (f-lt -1.0e-12 d) #f))))
(let ((g (Distribution gamma 1 2)) (e (Distribution exponential 2)))
  (List map (fn (_ x) (%close? (g cumulative x) (e cumulative x))) '(0.1 0.5 1 3)))
```
---
    (#t #t #t #t)

## The chi-squared distribution

### density, cumulative, survival and quantile

```x
(import x/num/distribution)
(let ((c (Distribution chi-squared 3)))
  (list (c density 1) (c cumulative 1) (c survival 7.815) (c quantile 0.95) (c quantile 0.05)))
```
---
    (0.241970724519143 0.198748043098799 0.0499939029748839 7.81472790325118 0.351846317749271)

### its mean is its freedom and its variance twice that

```x
(import x/num/distribution)
(let ((c (Distribution chi-squared 3))) (list (c mean) (c variance)))
```
---
    (3.0 6.0)

### one degree of freedom is a squared standard normal

```x
(import x/num/distribution)
(let ((c (Distribution chi-squared 1)))
  (list (c quantile 0.95) (c survival 30)))
```
---
    (3.84145882069413 4.3204630578275e-08)

## The standardized mean's distribution

### density, cumulative and survival, even about 0

```x
(import x/num/distribution)
(let ((t (Distribution standardized-mean 5)))
  (list (t density 0) (t density 2) (t cumulative 0) (t cumulative 2) (t cumulative -2) (t survival 2)
        (t survival 40)))
```
---
    (0.379606689822494 0.0650903103262165 0.5 0.949030260585071 0.0509697394149292 0.0509697394149292 9.20598108588648e-08)

### quantiles on both sides of 0

```x
(import x/num/distribution)
(let ((t (Distribution standardized-mean 5)))
  (list (t quantile 0.975) (t quantile 0.025) (t quantile 0.5) (t quantile 1.0e-6) (t quantile 0) (t quantile 1)))
```
---
    (2.57058183563632 -2.57058183563632 0.0 -24.771029720516 -inf inf)

### it nears the normal as the freedom grows

```x
(import x/num/distribution)
(let ((t (Distribution standardized-mean 30)))
  (list (t quantile 0.975) (t survival 10)))
```
---
    (2.04227245630124 2.28762570411481e-11)

### the mean and variance exist only above 1 and 2 degrees of freedom

```x
(import x/num/distribution)
(list ((Distribution standardized-mean 5) mean) ((Distribution standardized-mean 5) variance)
      ((Distribution standardized-mean 1.5) variance) ((Distribution standardized-mean 1) mean)
      ((Distribution standardized-mean 1) variance))
```
---
    (0.0 1.66666666666667 inf inf nan)

### one degree of freedom: the quantile at 3/4 is 1

```x
(import x/num/distribution)
(let ((t (Distribution standardized-mean 1)))
  (list (t cumulative 1) (t quantile 0.75) (t quantile 0.999)))
```
---
    (0.75 1.0 318.30883898555)

## The variance ratio's distribution

### density, cumulative and survival

```x
(import x/num/distribution)
(let ((f (Distribution variance-ratio 3 10)))
  (list (f density 1) (f cumulative 1) (f survival 1) (f survival 50) (f cumulative -1)))
```
---
    (0.404122811488563 0.567662796978303 0.432337203021697 2.51347041838405e-06 0.0)

### quantiles

```x
(import x/num/distribution)
(let ((f (Distribution variance-ratio 3 10)))
  (list (f quantile 0.95) (f quantile 0.05) (f quantile 0) (f quantile 1)))
```
---
    (3.70826481904684 0.113823594258647 0.0 inf)

### mean and variance, where they exist

```x
(import x/num/distribution)
(list ((Distribution variance-ratio 3 10) mean) ((Distribution variance-ratio 3 10) variance)
      ((Distribution variance-ratio 2 4) mean) ((Distribution variance-ratio 2 4) variance)
      ((Distribution variance-ratio 1 2) mean) ((Distribution variance-ratio 1 2) variance))
```
---
    (1.25 1.90972222222222 2.0 inf inf inf)

### the density at 0 turns on the upper freedom

```x
(import x/num/distribution)
(list ((Distribution variance-ratio 1 3) density 0) ((Distribution variance-ratio 2 4) density 0)
      ((Distribution variance-ratio 3 10) density 0))
```
---
    (inf 1.0 0.0)

## The shared quantile search

### the cumulative of the quantile is p

```x
(import x/num/distribution)
(import x/num/float float-of)
(List map
  (fn (_ d)
    (List all? (fn (_ p) (%close? (d cumulative (d quantile p)) (float-of p))) '(0.001 0.1 0.5 0.9 0.999)))
  (list (Distribution gamma 2 3) (Distribution gamma 0.5) (Distribution chi-squared 3)
        (Distribution standardized-mean 5) (Distribution standardized-mean 1) (Distribution variance-ratio 3 10)))
```
---
    (#t #t #t #t #t #t)

## Refusals

### a parameter out of range, and a p outside 0 to 1

```x
(import x/num/distribution)
(List map (fn (_ thunk) (guard (x (Err label x)) (thunk)))
  (list (fn (_) (Distribution normal 0 0)) (fn (_) (Distribution uniform 2 2)) (fn (_) (Distribution exponential -1))
        (fn (_) ((Distribution normal) quantile 2)) (fn (_) ((Distribution uniform) quantile -0.5))
        (fn (_) ((Distribution exponential) quantile 1.5))
        (fn (_) (Distribution gamma 0)) (fn (_) (Distribution gamma 2 0))
        (fn (_) (Distribution chi-squared 0)) (fn (_) (Distribution standardized-mean -1))
        (fn (_) (Distribution variance-ratio 0 1)) (fn (_) (Distribution variance-ratio 1 0))
        (fn (_) ((Distribution standardized-mean 5) quantile 2))))
```
---
    ('value 'value 'value 'value 'value 'value 'value 'value 'value 'value 'value 'value 'value)

## Variates

### a variate is the quantile of the source's uniform value, the same for the same seed

```x
(import x/num/distribution) (import x/num/random)
(let ((d (Distribution exponential 2)))
  (list (= (d variate (Random sw 7)) (d quantile ((Random sw 7) float)))
        (= (d variate (Random sw 7)) (d variate (Random sw 7)))))
```
---
    (#t #t)

### a count answers an f64 Tensor of the values in the order single variates come

```x
(import x/num/distribution) (import x/num/random) (import x/num/tensor)
(let ((d (Distribution normal 10 2)) (a (Random sw 3)) (b (Random sw 3)))
  (let ((t (d variate a 3)))
    (let ((l (t ->list)))
      (list (t extent) (t encoding)
            (= (List ref 0 l) (d variate b))
            (= (List ref 1 l) (d variate b))
            (= (List ref 2 l) (d variate b))))))
```
---
    ((3) 'f64 #t #t #t)

### the values lie where the distribution does, about its mean

```x
(import x/num/distribution) (import x/num/random) (import x/num/tensor)
(let ((u ((Distribution uniform 2 6) variate (Random sw 1) 200))
      (n ((Distribution normal 10 2) variate (Random sw 1) 400)))
  (list (<= 2 (u least)) (< (u greatest) 6)
        (< 9.5 (n mean)) (< (n mean) 10.5)))
```
---
    (#t #t #t #t)

### a distribution with no closed quantile answers through the search

```x
(import x/num/distribution) (import x/num/random)
(let ((x ((Distribution gamma 2 4) variate (Random sw 5))))
  (list (< 0 x) (< x 10)))
```
---
    (#t #t)

### a count below 1 is refused

```x
(import x/num/distribution) (import x/num/random)
(guard (e (Err label e)) ((Distribution normal) variate (Random sw 1) 0))
```
---
    'value

### other libraries' words find it

```x
(import x/num/distribution)
((Doc entry 'Distribution/variate) known-as)
```
---
    ("rvs" "sample" "draw" "simulate")

## Other names

### the names statistics texts use find the constructors

```x
(import x/sys/posix) (import x/sys/file) (import x/sys/stream)
(def distribution-found ())
(let ((tmp (File temp "/tmp/x-distribution-known-")))
  (File close (first tmp))
  (Stream with-file (rest tmp)
    (fn (_) (set! distribution-found (list (apropos "student") (apropos "F distribution")))))
  (File unlink (rest tmp)))
distribution-found
```
---
    (('Distribution/standardized-mean) ('Distribution/variance-ratio))

### the methods carry the names other libraries use

```x
(import x/num/distribution)
(list ((Doc entry 'Distribution/cumulative) known-as)
      ((Doc entry 'Distribution/quantile) known-as)
      ((Doc entry 'Distribution/deviation) known-as))
```
---
    (("CDF") ("inverse CDF" "ppf") ("standard deviation" "std"))
