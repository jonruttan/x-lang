# Neural: the operations a transformer is made of
# @weight 2

`Neural` works on tensors: softmax, gelu and layer-norm along the last
axis, the rows of an embedding table, and the causal mask. Where an answer
is not a value a double holds exactly, the case compares it with the value
worked out beforehand and answers whether every element is within a
millionth of a millionth of it, or a millionth for f32.

## softmax

### equal elements take equal shares

```x
(do (import x/num/neural)
  ((Neural softmax (Tensor from '(0 0))) ->list))
```
---
    (0.5 0.5)

### each element's exponential over their sum

```x
(do (import x/num/neural)
  (def nn-near (fn (go a b) (if (null? a) (null? b) (let ((d (- (first a) (first b)))) (if (< (* d d) 1.0e-24) (go (rest a) (rest b)) #f)))))
  (nn-near ((Neural softmax (Tensor from '(1 2 3))) ->list)
           '(0.09003057317038046 0.24472847105479764 0.6652409557748218)))
```
---
    #t

### large elements do not overflow

```x
(do (import x/num/neural)
  (def nn-near (fn (go a b) (if (null? a) (null? b) (let ((d (- (first a) (first b)))) (if (< (* d d) 1.0e-24) (go (rest a) (rest b)) #f)))))
  (nn-near ((Neural softmax (Tensor from '(1000 1000 999) 'f64)) ->list)
           '(0.4223187982515182 0.4223187982515182 0.15536240349696362)))
```
---
    #t

### each run of the last axis is taken alone

```x
(do (import x/num/neural)
  (def nn-near32 (fn (go a b) (if (null? a) (null? b) (let ((d (- (first a) (first b)))) (if (< (* d d) 1.0e-12) (go (rest a) (rest b)) #f)))))
  (def rows ((Neural softmax (Tensor from '((0 0) (1 2)) 'f32)) ->list))
  (list (first rows) (nn-near32 (first (rest rows)) '(0.2689414213699951 0.7310585786300049))))
```
---
    ((0.5 0.5) #t)

### an f32 operand answers f32, any other f64

```x
(do (import x/num/neural)
  (list ((Neural softmax (Tensor from '(1 2) 'f32)) encoding) ((Neural softmax (Tensor from '(1 2))) encoding)))
```
---
    ('f32 'f64)

### the operand is left as it was

```x
(do (import x/num/neural)
  (def t (Tensor from '(1.5 2.5)))
  (Neural softmax t)
  (t ->list))
```
---
    (1.5 2.5)

### a Matrix answers a Matrix

```x
(do (import x/num/neural) (import x/num/matrix)
  (instance-of? (Neural softmax (Matrix from '((1 2) (3 4)))) Matrix))
```
---
    #t

### a tensor of rank 0 raises a label value, and what is no tensor a label type

```x
(do (import x/num/neural)
  (list (guard (e (Err label e)) (Neural softmax (Tensor from 3)))
        (guard (e (Err label e)) (Neural softmax '(1 2)))))
```
---
    ('value 'type)

## gelu

### 0 answers 0

```x
(do (import x/num/neural)
  ((Neural gelu (Tensor from '(0 0))) ->list))
```
---
    (0.0 0.0)

### x times the normal's cumulative at x

```x
(do (import x/num/neural)
  (def nn-near (fn (go a b) (if (null? a) (null? b) (let ((d (- (first a) (first b)))) (if (< (* d d) 1.0e-24) (go (rest a) (rest b)) #f)))))
  (nn-near ((Neural gelu (Tensor from '(-1.0 0.0 1.0 2.5))) ->list)
           '(-0.15865525393145707 0.0 0.8413447460685429 2.4844758366855597)))
```
---
    #t

### the tanh form

```x
(do (import x/num/neural)
  (def nn-near (fn (go a b) (if (null? a) (null? b) (let ((d (- (first a) (first b)))) (if (< (* d d) 1.0e-24) (go (rest a) (rest b)) #f)))))
  (nn-near ((Neural gelu (Tensor from '(-1.0 0.0 1.0 2.5)) 'tanh) ->list)
           '(-0.1588080093917233 0.0 0.8411919906082768 2.484915733910001)))
```
---
    #t

### every element of every axis, in f32

```x
(do (import x/num/neural)
  (def nn-near32 (fn (go a b) (if (null? a) (null? b) (let ((d (- (first a) (first b)))) (if (< (* d d) 1.0e-12) (go (rest a) (rest b)) #f)))))
  (def g (Neural gelu (Tensor from '((-1.0 0.0) (1.0 2.5)) 'f32)))
  (list (g encoding) (g extent)
        (nn-near32 (first (g ->list)) '(-0.15865525393145707 0.0))
        (nn-near32 (first (rest (g ->list))) '(0.8413447460685429 2.4844758366855597))))
```
---
    ('f32 (2 2) #t #t)

### a form it does not have raises a label value

```x
(do (import x/num/neural)
  (guard (e (Err label e)) (Neural gelu (Tensor from '(1 2)) 'sine)))
```
---
    'value

## layer-norm

### a run of equal elements answers the bias

Every difference from the mean is 0.

```x
(do (import x/num/neural)
  ((Neural layer-norm (Tensor from '(1 1 1)) (Tensor from '(2 2 2)) (Tensor from '(5 6 7))) ->list))
```
---
    (5.0 6.0 7.0)

### mean 0 and deviation 1, with a gain of 1 and a bias of 0

```x
(do (import x/num/neural)
  (def nn-near (fn (go a b) (if (null? a) (null? b) (let ((d (- (first a) (first b)))) (if (< (* d d) 1.0e-24) (go (rest a) (rest b)) #f)))))
  (nn-near ((Neural layer-norm (Tensor from '(1.0 2.0 3.0 4.0)) (Tensor from '(1 1 1 1)) (Tensor from '(0 0 0 0))) ->list)
           '(-1.3416354199689269 -0.447211806656309 0.447211806656309 1.3416354199689269)))
```
---
    #t

### each run alone, scaled by the gain and moved by the bias, in f32

```x
(do (import x/num/neural)
  (def nn-near32 (fn (go a b) (if (null? a) (null? b) (let ((d (- (first a) (first b)))) (if (< (* d d) 1.0e-12) (go (rest a) (rest b)) #f)))))
  (def n (Neural layer-norm (Tensor from '((1.0 2.0 3.0 4.0) (4.0 3.0 2.0 1.0)) 'f32)
                            (Tensor from '(2 2 2 2)) (Tensor from '(0.5 0.5 0.5 0.5))))
  (list (n encoding)
        (nn-near32 (first (n ->list)) '(-2.1832708399378538 -0.394423613312618 1.394423613312618 3.1832708399378538))
        (nn-near32 (first (rest (n ->list))) '(3.1832708399378538 1.394423613312618 -0.394423613312618 -2.1832708399378538))))
```
---
    ('f32 #t #t)

### an epsilon of its own

The run 1, 3 has a mean of 2 and a variance of 1; with an epsilon of 1
the deviation is the root of 2.

```x
(do (import x/num/neural)
  (def nn-near (fn (go a b) (if (null? a) (null? b) (let ((d (- (first a) (first b)))) (if (< (* d d) 1.0e-24) (go (rest a) (rest b)) #f)))))
  (nn-near ((Neural layer-norm (Tensor from '(1.0 3.0)) (Tensor from '(1 1)) (Tensor from '(0 0)) 1.0) ->list)
           '(-0.7071067811865475 0.7071067811865475)))
```
---
    #t

### a gain of another length raises a label value

```x
(do (import x/num/neural)
  (guard (e (Err label e))
    (Neural layer-norm (Tensor from '(1.0 2.0 3.0)) (Tensor from '(1 1)) (Tensor from '(0 0 0)))))
```
---
    'value

## embed

### the rows the indexes pick, in their order

```x
(do (import x/num/neural)
  ((Neural embed (Tensor from '((1 2) (3 4) (5 6)) 'f64) '(2 0 2)) ->list))
```
---
    ((5.0 6.0) (1.0 2.0) (5.0 6.0))

### a negative index counts from the end, and the encoding is the table's

```x
(do (import x/num/neural)
  (def e (Neural embed (Tensor from '((1.5 2.5) (3.5 4.5) (5.5 6.5)) 'f32) '(-1 0)))
  (list (e encoding) (e ->list)))
```
---
    ('f32 ((5.5 6.5) (1.5 2.5)))

### a view's rows are picked as the view has them

```x
(do (import x/num/neural)
  ((Neural embed ((Tensor from '((1.5 2.5) (3.5 4.5)) 'f64) transpose) '(1)) ->list))
```
---
    ((2.5 4.5))

### no indexes answer no rows

```x
(do (import x/num/neural)
  ((Neural embed (Tensor from '((1.5 2.5) (3.5 4.5)) 'f64) '()) extent))
```
---
    (0 2)

### a row the table lacks raises a label value, and an index that is no integer a label type

```x
(do (import x/num/neural)
  (def table (Tensor from '((1.5 2.5) (3.5 4.5)) 'f64))
  (list (guard (e (Err label e)) (Neural embed table '(2)))
        (guard (e (Err label e)) (Neural embed table '(-3)))
        (guard (e (Err label e)) (Neural embed table '(0.5)))))
```
---
    ('value 'value 'type)

## causal-mask

### a softmax gives a row's later columns no share

```x
(do (import x/num/neural)
  ((Neural softmax (Neural causal-mask (Tensor from '((0 0) (0 0)) 'f64))) ->list))
```
---
    ((1.0 0.0) (0.5 0.5))

### the elements on and below the diagonal stay

```x
(do (import x/num/neural)
  (def m (Neural causal-mask (Tensor from '((1.5 2.5 3.5) (4.5 5.5 6.5) (7.5 8.5 9.5)) 'f64)))
  (list (m ref 0 0) (m ref 1 0) (m ref 1 1) (m ref 2 2) (Float inf? (m ref 0 1)) (Float inf? (m ref 1 2)) (< (m ref 0 2) 0)))
```
---
    (1.5 4.5 5.5 9.5 #t #t #t)

### every pair of last axes is masked, and the operand left as it was

```x
(do (import x/num/neural)
  (def t (Tensor zeros '(2 2 2) 'f32))
  (list ((Neural softmax (Neural causal-mask t)) ->list) (t ->list)))
```
---
    ((((1.0 0.0) (0.5 0.5)) ((1.0 0.0) (0.5 0.5))) (((0.0 0.0) (0.0 0.0)) ((0.0 0.0) (0.0 0.0))))

### a tensor of rank 1 raises a label value

```x
(do (import x/num/neural)
  (guard (e (Err label e)) (Neural causal-mask (Tensor from '(1.5 2.5)))))
```
---
    'value

## the compiled kernels

### the answers are the same once the kernels are compiled

jit! compiles every kernel where a JIT backend is and answers a list;
the answers before and after it agree to the bit either way.

```x
(do (import x/num/neural)
  (def run (fn (_ enc)
    (list ((Neural softmax (Tensor from '((1.0 2.0 3.0) (-4.0 0.5 2.5)) enc)) ->list)
          ((Neural gelu (Tensor from '(-1.0 0.0 1.0 2.5) enc)) ->list)
          ((Neural gelu (Tensor from '(-1.0 0.0 1.0 2.5) enc) 'tanh) ->list)
          ((Neural layer-norm (Tensor from '(1.0 2.0 3.0 4.5) enc) (Tensor from '(2 3 4 5)) (Tensor from '(0.5 0.5 1.5 1.5))) ->list))))
  (def before (list (run 'f64) (run 'f32)))
  (def names (Neural jit!))
  (list (if (null? names) #t (pair? names)) (equal? before (list (run 'f64) (run 'f32)))))
```
---
    (#t #t)
