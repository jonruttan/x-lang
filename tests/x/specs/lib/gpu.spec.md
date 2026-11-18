# Gpu: Tensor arithmetic on the host's GPU
# @weight 2

`Gpu` runs the matrix product on the GPU in f32, through Metal on macOS.
Each case asks `(Gpu available?)` first and, on a host with no GPU,
answers what the GPU would have: the file passes everywhere and tests the
GPU where there is one. The numbers are small integers and halves, whose
sums single precision holds exactly, so every answer is the same to the
bit as the CPU's.

## the device

### available? answers a boolean on any host

```x
(import x/num/gpu)
(boolean? (Gpu available?))
```
---
    #t

### with no GPU, product raises a label io

```x
(import x/num/gpu)
(if (Gpu available?) (lit io)
  (guard (e (Err label e)) (Gpu product (Matrix from '((1 2) (3 4))) (Matrix from '((1 0) (0 1))))))
```
---
    'io

## the product

### two matrices: the result is an f32 Matrix

```x
(import x/num/gpu)
(if (Gpu available?)
  (let ((p (Gpu product (Matrix from '((1 2) (3 4)) 'f32) (Matrix from '((0 1) (1 0)) 'f32))))
    (list (p encoding) (p ->list) (instance-of? p Matrix)))
  (lit (f32 ((2.0 1.0) (4.0 3.0)) #t)))
```
---
    ('f32 ((2.0 1.0) (4.0 3.0)) #t)

### rows and columns that differ: 2 by 3 times 3 by 2

```x
(import x/num/gpu)
(if (Gpu available?)
  (let ((m (Matrix from '((1 2 3) (4 5 6)) 'f32)))
    ((Gpu product m (Matrix from '((1 0.5) (0 1) (2 0)) 'f32)) ->list))
  (lit ((7.0 2.5) (16.0 7.0))))
```
---
    ((7.0 2.5) (16.0 7.0))

### a rank-1 other is a column, and the product a rank-1 Tensor

```x
(import x/num/gpu)
(if (Gpu available?)
  (let ((p (Gpu product (Matrix from '((1 2) (3 4)) 'f32) (Tensor from '(1 1) 'f32))))
    (list (p ->list) (instance-of? p Matrix)))
  (lit ((3.0 7.0) #f)))
```
---
    ((3.0 7.0) #f)

### operands of another encoding are cast to f32

```x
(import x/num/gpu)
(if (Gpu available?)
  (let ((p (Gpu product (Matrix from '((1 2) (3 4))) (Matrix from '((0.5 0) (0 0.5)) 'f64))))
    (list (p encoding) (p ->list)))
  (lit (f32 ((0.5 1.0) (1.5 2.0)))))
```
---
    ('f32 ((0.5 1.0) (1.5 2.0)))

### a view is read through its strides: a transpose and a slice

```x
(import x/num/gpu)
(if (Gpu available?)
  (let ((m (Matrix from '((1 2 3) (4 5 6)) 'f32)))
    (list ((Gpu product m (m transpose)) ->list)
          ((Gpu product (m slice 1 0 2) (m slice 1 1 3)) ->list)))
  (lit (((14.0 32.0) (32.0 77.0)) ((12.0 15.0) (33.0 42.0)))))
```
---
    (((14.0 32.0) (32.0 77.0)) ((12.0 15.0) (33.0 42.0)))

### it answers what Matrix's product does on the same numbers

```x
(import x/num/gpu)
(if (Gpu available?)
  (let ((a (Matrix from '((1 2 3) (4 5 6) (7 8 9)) 'f32)) (b (Matrix from '((0.5 1 0) (2 0 1) (1 1 1)) 'f32)))
    (equal? ((Gpu product a b) ->list) ((a product b) ->list)))
  #t)
```
---
    #t

### a larger product: 64 by 64 of ones is 64 everywhere

```x
(import x/num/gpu)
(if (Gpu available?)
  (let ((m (Matrix fill '(64 64) 1 'f32)))
    (let ((p (Gpu product m m)))
      (list (p extent) (p ref 0 0) (p ref -1 -1) (p sum))))
  (lit ((64 64) 64.0 64.0 262144.0)))
```
---
    ((64 64) 64.0 64.0 262144.0)

### a product with no rows, or summed over nothing, is zeros

```x
(import x/num/gpu)
(if (Gpu available?)
  (list ((Gpu product (Matrix zeros '(0 3) 'f32) (Matrix zeros '(3 2) 'f32)) extent)
        ((Gpu product (Matrix zeros '(2 0) 'f32) (Matrix zeros '(0 2) 'f32)) ->list))
  (lit ((0 2) ((0.0 0.0) (0.0 0.0)))))
```
---
    ((0 2) ((0.0 0.0) (0.0 0.0)))

### the kernel is compiled again after it is forgotten, as after a state image

```x
(import x/num/gpu)
(if (Gpu available?)
  (let ((a (Matrix from '((1 2) (3 4)) 'f32)))
    (Gpu product a a)
    (Gpu %forget!)
    ((Gpu product a a) ->list))
  (lit ((7.0 10.0) (15.0 22.0))))
```
---
    ((7.0 10.0) (15.0 22.0))

## refusals

### extents that do not fit are refused

```x
(import x/num/gpu)
(if (Gpu available?)
  (list (guard (e (Err label e)) (Gpu product (Matrix from '((1 2) (3 4))) (Matrix from '((1 2 3)))))
        (guard (e (Err label e)) (Gpu product (Tensor from '(1 2)) (Matrix from '((1 2))))))
  (lit (value value)))
```
---
    ('value 'value)
