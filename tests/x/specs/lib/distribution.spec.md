# probability distributions (Normal, Uniform, Exponential)

A distribution is a value made with its parameters, answering its density,
cumulative, survival and quantile, mean, variance and deviation, each a
Float. The expected values are those of Python's `statistics.NormalDist`
and `math` to the digits printed.

## The normal distribution

### a distribution is a value of its class

A block reads whole before it runs, so a float literal reads as a float
only in a block after the one whose import loads the float reader; this
case loads it.

```x
(import x/num/distribution)
(List map class-name (list (Normal make) (Uniform make) (Exponential make)))
```
---
    ('Normal 'Uniform 'Exponential)

### density, cumulative and survival of the standard normal

```x
(import x/num/distribution)
(let ((n (Normal make)))
  (list (n density 0) (n cumulative 1.96) (n survival 1.96) (n cumulative 0) (n cumulative -3)))
```
---
    (0.398942280401433 0.97500210485178 0.0249978951482204 0.5 0.0013498980316301)

### quantiles in the centre and both tails

```x
(import x/num/distribution)
(let ((n (Normal make 0 1)))
  (List map (fn (_ p) (n quantile p)) '(0.5 0.975 0.025 0.001 0.999 0.000001 0.999999)))
```
---
    (0.0 1.95996398454005 -1.95996398454005 -3.09023230616781 3.09023230616781 -4.7534243088229 4.75342430881709)

### the cumulative of the quantile is p

```x
(import x/num/distribution)
(let ((n (Normal make)))
  (List map (fn (_ p) (n cumulative (n quantile p))) '(0.1 0.3 0.7 0.9 0.02 0.98 0.0001)))
```
---
    (0.1 0.3 0.7 0.9 0.02 0.98 0.0001)

### a mean and deviation shift and scale it

```x
(import x/num/distribution)
(let ((n (Normal make 10 2)))
  (list (n quantile 0.5) (n cumulative 12) (n density 10) (n mean) (n variance) (n deviation)))
```
---
    (10.0 0.841344746068543 0.199471140200716 10.0 4.0 2.0)

### p 0 and 1 answer minus and plus infinity

```x
(import x/num/distribution)
(let ((n (Normal make))) (list (n quantile 0) (n quantile 1)))
```
---
    (-inf inf)

## The uniform distribution

### density, cumulative, survival and quantile

```x
(import x/num/distribution)
(let ((u (Uniform make 0 4)))
  (list (u density 1) (u density 5) (u cumulative -1) (u cumulative 3) (u cumulative 9)
        (u survival 3) (u quantile 0.5)))
```
---
    (0.25 0.0 0.0 0.75 1.0 0.25 2.0)

### mean, variance and deviation, and the default bounds

```x
(import x/num/distribution)
(list ((Uniform make 2 6) mean) ((Uniform make 0 6) variance) ((Uniform make 0 12) deviation)
      ((Uniform make) mean))
```
---
    (4.0 3.0 3.46410161513775 0.5)

## The exponential distribution

### density, cumulative, survival and quantile

```x
(import x/num/distribution)
(let ((e (Exponential make 2)))
  (list (e density 0) (e density -1) (e cumulative 1) (e survival 1) (e quantile 0.5) (e quantile 0) (e quantile 1)))
```
---
    (2.0 0.0 0.864664716763387 0.135335283236613 0.346573590279973 0.0 inf)

### mean, variance and deviation

```x
(import x/num/distribution)
(let ((e (Exponential make 2))) (list (e mean) (e variance) (e deviation) ((Exponential make) mean)))
```
---
    (0.5 0.25 0.5 1.0)

## Refusals

### a parameter out of range, and a p outside 0 to 1

```x
(import x/num/distribution)
(List map (fn (_ thunk) (guard (x (Err label x)) (thunk)))
  (list (fn (_) (Normal make 0 0)) (fn (_) (Uniform make 2 2)) (fn (_) (Exponential make -1))
        (fn (_) ((Normal make) quantile 2)) (fn (_) ((Uniform make) quantile -0.5))
        (fn (_) ((Exponential make) quantile 1.5))))
```
---
    ('value 'value 'value 'value 'value 'value)
