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
(import x/num/float/literal)
(import x/num/gpu)
(if (Gpu available?)
  (let ((p (Gpu product (Matrix from '((1 2) (3 4)) 'f32) (Matrix from '((0 1) (1 0)) 'f32))))
    (list (p encoding) (p ->list) (instance-of? p Matrix)))
  (list (lit f32) (lit ((2.0 1.0) (4.0 3.0))) #t))
```
---
    ('f32 ((2.0 1.0) (4.0 3.0)) #t)

### rows and columns that differ: 2 by 3 times 3 by 2

```x
(import x/num/float/literal)
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
(import x/num/float/literal)
(import x/num/gpu)
(if (Gpu available?)
  (let ((p (Gpu product (Matrix from '((1 2) (3 4)) 'f32) (Tensor from '(1 1) 'f32))))
    (list (p ->list) (instance-of? p Matrix)))
  (list (lit (3.0 7.0)) #f))
```
---
    ((3.0 7.0) #f)

### operands of another encoding are cast to f32

```x
(import x/num/float/literal)
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
(import x/num/float/literal)
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
(import x/num/float/literal)
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
(import x/num/float/literal)
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
(import x/num/float/literal)
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
(import x/num/float/literal)
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

## held tensors

A held tensor's bytes are in a buffer the GPU shares. It is a Tensor like
any other, and product reads it, and answers one, with no copy.

### hold answers an f32 copy of the same class, and held? tells it from an ordinary tensor

```x
(import x/num/float/literal)
(import x/num/gpu)
(if (Gpu available?)
  (let ((h (Gpu hold (Matrix from '((1 2) (3 4))))))
    (let ((r (list (h encoding) (h ->list) (Gpu held? h) (instance-of? h Matrix) (Gpu held? (Matrix from '((1)))))))
      (Gpu release h)
      r))
  (list (lit f32) (lit ((1.0 2.0) (3.0 4.0))) #t #t #f))
```
---
    ('f32 ((1.0 2.0) (3.0 4.0)) #t #t #f)

### Tensor's operations work on a held tensor, and their results are ordinary

```x
(import x/num/float/literal)
(import x/num/gpu)
(if (Gpu available?)
  (let ((h (Gpu hold (Matrix from '((1 2) (3 4))))))
    (let ((r (list ((h add 1) ->list) (Gpu held? (h add 1)) (h sum) (h min))))
      (Gpu release h)
      r))
  (list (lit ((2.0 3.0) (4.0 5.0))) #f 10.0 1.0))
```
---
    (((2.0 3.0) (4.0 5.0)) #f 10.0 1.0)

### a view of a held tensor shares its buffer

```x
(import x/num/float/literal)
(import x/num/gpu)
(if (Gpu available?)
  (let ((h (Gpu hold (Matrix from '((1 2) (3 4))))))
    (h set! 0 1 9)
    (let ((r (list (Gpu held? (h transpose)) ((h transpose) ->list))))
      (Gpu release h)
      r))
  (list #t (lit ((1.0 3.0) (9.0 4.0)))))
```
---
    (#t ((1.0 3.0) (9.0 4.0)))

### a product of held tensors is held, and a chain of products stays on the GPU

```x
(import x/num/float/literal)
(import x/num/gpu)
(if (Gpu available?)
  (let ((a (Gpu hold (Matrix from '((1 2) (3 4))))))
    (let ((p (Gpu product a a)))
      (let ((q (Gpu product p (a transpose))))
        (let ((r (list (Gpu held? p) (p ->list) (Gpu held? q) (q ->list) (instance-of? q Matrix))))
          (List for-each (fn (_ t) (Gpu release t)) (list a p q))
          r))))
  (list #t (lit ((7.0 10.0) (15.0 22.0))) #t (lit ((27.0 61.0) (59.0 133.0))) #t))
```
---
    (#t ((7.0 10.0) (15.0 22.0)) #t ((27.0 61.0) (59.0 133.0)) #t)

### a held view is read where it lies: a slice against a column, and an ordinary matrix against a held transpose

```x
(import x/num/float/literal)
(import x/num/gpu)
(if (Gpu available?)
  (let ((m (Gpu hold (Matrix from '((1 2 3) (4 5 6))))))
    (let ((p (Gpu product (m slice 1 1 3) (Tensor from '(1 10))))
          (q (Gpu product (Matrix from '((1 2) (3 4))) ((m transpose) slice 0 0 2))))
      (let ((r (list (p ->list) (Gpu held? p) (q ->list) (Gpu held? q))))
        (List for-each (fn (_ t) (Gpu release t)) (list m p q))
        r)))
  (list (lit (32.0 65.0)) #t (lit ((5.0 14.0) (11.0 32.0))) #t))
```
---
    ((32.0 65.0) #t ((5.0 14.0) (11.0 32.0)) #t)

### a planned product is run again for what its operands then hold

A plan keeps a product's buffers and dimensions, so a second run makes
nothing: the result is written where the first was.

```x
(import x/num/float/literal)
(import x/num/gpu)
(if (Gpu available?)
  (let ((a (Gpu hold (Matrix from '((1 2))))) (b (Gpu hold (Matrix from '((1 0) (0 1))))))
    (let ((plan (Gpu %plan a b)))
      (let ((out (Gpu %plan-out plan)))
        (Gpu %plan-run plan)
        (let ((once (out ->list)))
          (a set! 0 0 5)
          (Gpu %plan-run plan)
          (let ((r (list once (out ->list) (Gpu held? out))))
            (Gpu %plan-done plan #f)
            (Gpu release a)
            (Gpu release b)
            r)))))
  (list (lit ((1.0 2.0))) (lit ((5.0 2.0))) #t))
```
---
    (((1.0 2.0)) ((5.0 2.0)) #t)

### two ordinary operands answer an ordinary matrix

```x
(import x/num/gpu)
(if (Gpu available?)
  (Gpu held? (Gpu product (Matrix from '((1 2) (3 4))) (Matrix from '((1 0) (0 1)))))
  #f)
```
---
    #f

### after release the tensor and its views raise a label state, and a second release does nothing

```x
(import x/num/gpu)
(if (Gpu available?)
  (let ((h (Gpu hold (Matrix from '((1 2) (3 4))))))
    (let ((v (h transpose)))
      (Gpu release h)
      (list (guard (e (Err label e)) (h ->list)) (guard (e (Err label e)) (v sum))
            (guard (e (Err label e)) (Gpu product v v)) (Gpu release h))))
  (lit (state state state ())))
```
---
    ('state 'state 'state ())

### releasing an ordinary tensor does nothing

```x
(import x/num/float/literal)
(import x/num/gpu)
(let ((t (Tensor from '(1.5 2.5))))
  (list (Gpu release t) (Gpu held? t) (t ->list)))
```
---
    (() #f (1.5 2.5))

### with no GPU, hold raises a label io

```x
(import x/num/gpu)
(if (Gpu available?) (lit io)
  (guard (e (Err label e)) (Gpu hold (Tensor from '(1 2)))))
```
---
    'io

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
