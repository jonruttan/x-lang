# models fitted to data (Model, Fit)
# @weight 2

`(Model linear)` is the linear model, and `(m fit x y)` answers a `Fit`:
its coefficients, intercept, fitted values, residuals and coefficient of
determination, and the model's value at new rows. The model is unchanged
by a fit. The cases fit data a line or a plane passes through, so the
answers are whole, or compare within a rounding.

## The linear model

### one predictor: the intercept and the slope of the line

```x
(import x/num/model)
(let ((f ((Model linear) fit '(1 2 3) '(3 5 7))))
  (list (f intercept) ((f coefficients) ->list)))
```
---
    (1.0 (2.0))

### several predictors: a slope for each column

```x
(import x/num/model)
(let ((f ((Model linear) fit '((1 0) (0 1) (1 1) (2 1)) '(3 4 6 8))))
  (list (f intercept) ((f coefficients) ->list)))
```
---
    (1.0 (2.0 3.0))

### the least-squares line through points no line passes through

```x
(import x/num/float/literal)
(import x/num/model)
(let ((f ((Model linear) fit '(1 2 3 4 5) '(2.2 4.1 6.2 7.9 10.1)))
      (near (fn (_ a b) (let ((d (- a b))) (< (* d d) 1.0e-18)))))
  (list (near ((f coefficients) ref 0) 1.96) (near (f intercept) 0.22)))
```
---
    (#t #t)

### fitted values and residuals, an element for each observation

```x
(import x/num/model)
(let ((f ((Model linear) fit '(0 1 2) '(0 0 3))))
  (list ((f fitted) ->list) ((f residuals) ->list)))
```
---
    ((-0.5 1.0 2.5) (0.5 -1.0 0.5))

### determination is 1 less the residuals' share of the variation

```x
(import x/num/model)
(list (((Model linear) fit '(0 1 2) '(0 0 3)) determination)
      (((Model linear) fit '(1 2 3) '(3 5 7)) determination))
```
---
    (0.75 1.0)

### predict answers the model's value at new rows

```x
(import x/num/model)
(list ((((Model linear) fit '(1 2 3) '(3 5 7)) predict '(10 20)) ->list)
      ((((Model linear) fit '((1 0) (0 1) (1 1) (2 1)) '(3 4 6 8)) predict '((1 1) (0 0))) ->list))
```
---
    ((21.0 41.0) (6.0 1.0))

## Through the origin

### 'origin fits no intercept

```x
(import x/num/model)
(let ((f ((Model linear 'origin) fit '(1 2 3) '(2 4 6))))
  (list (f intercept) ((f coefficients) ->list) ((f predict '(5)) ->list)))
```
---
    (0.0 (2.0) (10.0))

### its determination takes the response's variation about 0

```x
(import x/num/model)
(let ((f ((Model linear 'origin) fit '(1 1) '(1 3))))
  (list ((f coefficients) ->list) (f determination)))
```
---
    ((2.0) 0.8)

## Judging the coefficients

### freedom is the observations less the terms fitted

```x
(import x/num/model)
(list (((Model linear) fit '(0 1 2 3) '(1 3 2 5)) freedom)
      (((Model linear 'origin) fit '(1 2 3) '(2 4 7)) freedom)
      (((Model linear) fit '((1 0) (0 1) (1 1) (2 1) (3 5)) '(3 4 6 8 9)) freedom)
      (((Model linear) fit '(1 2) '(3 5)) freedom))
```
---
    (2 2 2 0)

### the residuals' deviation, and a slope's standard error, statistic and significance

```x
(import x/num/float/literal)
(import x/num/model)
(let ((f ((Model linear) fit '(0 1 2) '(0 0 3)))
      (near (fn (_ a b) (let ((d (- a b))) (< (* d d) 1.0e-24)))))
  (list (near (* (f residual-deviation) (f residual-deviation)) 1.5)
        (near (* ((f standard-errors) ref 0) ((f standard-errors) ref 0)) 0.75)
        (near (* ((f statistics) ref 0) ((f statistics) ref 0)) 3.0)
        (near (* 3 ((f significance) ref 0)) 1.0)))
```
---
    (#t #t #t #t)

### a line through scattered points, against the values worked by hand

```x
(import x/num/float/literal)
(import x/num/model)
(let ((f ((Model linear) fit '(1 2 3 4 5) '(2.2 4.1 6.2 7.9 10.1)))
      (near (fn (_ a b) (let ((d (- a b))) (< (* d d) 1.0e-16)))))
  (list (near (f residual-deviation) 0.1211060142)
        (near ((f standard-errors) ref 0) 0.0382970843)
        (near (* ((f statistics) ref 0) ((f statistics) ref 0)) 2619.2727272727)
        (< ((f significance) ref 0) 0.001)))
```
---
    (#t #t #t #t)

### an element for each predictor, the intercept left out

```x
(import x/num/model)
(let ((f ((Model linear) fit '((1 0) (0 1) (1 1) (2 1) (3 5)) '(3 4 6 8 9)))
      (g ((Model linear 'origin) fit '(1 2 3) '(2 4 7))))
  (list ((f coefficients) size) ((f standard-errors) size) ((f statistics) size) ((f significance) size)
        ((g standard-errors) size)))
```
---
    (2 2 2 2 1)

### a predictor that matters has a small significance, one that does not a large one

```x
(import x/num/float/literal)
(import x/num/model)
(let ((f ((Model linear) fit '((1 1) (2 -1) (3 -1) (4 1) (5 1) (6 -1)) '(2.1 3.9 6.2 7.8 10.1 11.9))))
  (list (< ((f significance) ref 0) 0.001) (< 0.1 ((f significance) ref 1))))
```
---
    (#t #t)

### other libraries' words find them

```x
(import x/num/model)
(list ((Doc entry 'Fit/significance) known-as)
      ((Doc entry 'Fit/statistics) known-as)
      ((Doc entry 'Fit/residual-deviation) known-as))
```
---
    (("p-value" "Pr(>|t|)") ("t value" "t statistic" "test statistic") ("residual standard error" "sigma"))

## The model and the data

### a fit leaves the model unchanged: one model fits many sets of data

```x
(import x/num/model)
(let ((m (Model linear)))
  (list ((m fit '(1 2 3) '(3 5 7)) intercept)
        ((m fit '(1 2 3) '(0 1 2)) intercept)
        ((m fit '(1 2 3) '(3 5 7)) intercept)))
```
---
    (1.0 -1.0 1.0)

### the predictors and the response may be Tensors

```x
(import x/num/model) (import x/num/tensor) (import x/num/matrix)
(let ((y (Tensor from '(3 4 6 8))))
  (list (((Model linear) fit (Matrix from '((1 0) (0 1) (1 1) (2 1))) y) intercept)
        ((((Model linear) fit (Tensor from '(1 2 3)) (Tensor from '(3 5 7))) coefficients) ->list)))
```
---
    (1.0 (2.0))

## Refusals

### rows that do not match the response, columns that do not match the fit, and an unknown option

```x
(import x/num/model)
(list (guard (e (Err label e)) ((Model linear) fit '(1 2 3) '(1 2)))
      (guard (e (Err label e)) (((Model linear) fit '(1 2 3) '(3 5 7)) predict '((1 2))))
      (guard (e (Err label e)) (Model linear 'slope)))
```
---
    ('value 'value 'value)

## Other names

### other libraries' words find the model and the determination

```x
(import x/num/model)
(list ((Doc entry 'Model/linear) known-as)
      ((Doc entry 'Fit/determination) known-as))
```
---
    (("lm" "linear regression" "ordinary least squares" "OLS") ("R-squared" "r2" "coefficient of determination"))

## The doc examples that round

### each answers what its doc shows

```x
(import x/num/model)
(let ((f ((Model linear) fit '(0 1 2) '(0 0 3))))
  (list (Float round (Float * 1000 (f residual-deviation)))
        (Float round (Float * 1000 ((f standard-errors) ref 0)))
        (Float round (Float * 1000 ((f statistics) ref 0)))
        (Float round (Float * 1000 ((f significance) ref 0)))))
```
---
    (1225.0 866.0 1732.0 333.0)
