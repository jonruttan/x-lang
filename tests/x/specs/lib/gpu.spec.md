# Gpu: Tensor arithmetic on the host's GPU
# @weight 2

`Gpu` runs the matrix product on the GPU in f32, through Metal on macOS
and Vulkan elsewhere.
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

### a caller's kernels run as steps, with a planned product among them

A step is a run of a kernel, a grid form, over buffers the caller keeps,
and a list of steps runs as one. Here a kernel doubles a held row, a planned product
multiplies it by the identity, and the kernel doubles the row again: the
product saw the row doubled once.

```x
(import x/num/gpu)
(if (Gpu available?)
  (let ((a (Gpu hold (Matrix from '((1 2))))) (b (Gpu hold (Matrix from '((1 0) (0 1)))))
        (form (lit (fn (_ a n) (if (< at-x (i32-ref n 0)) (f32-set! a at-x (f+ (f32-ref a at-x) (f32-ref a at-x)))))))
        (count (Gpu %words (list 2))))
    (let ((plan (Gpu %plan a b)))
      (let ((twice (Gpu %step (lit twice) form (list (Gpu %buffer-of a) count) 2 1)))
        (Gpu %steps-run (list twice (Gpu %plan-step plan) twice))
        (let ((r (list (a ->list) ((Gpu %plan-out plan) ->list))))
          (Gpu %plan-done plan #f)
          (Gpu %words-done count)
          (Gpu release a)
          (Gpu release b)
          r))))
  (list (lit ((4.0 8.0))) (lit ((2.0 4.0)))))
```
---
    (((4.0 8.0)) ((2.0 4.0)))

### a word a kernel wrote is read back

A buffer of words holds a kernel's dimensions, and also what a kernel
answers that is not a tensor: here a kernel writes the sum of two words
into a third.

```x
(import x/num/gpu)
(if (Gpu available?)
  (let ((form (lit (fn (_ w) (i32-set! w 2 (+ (i32-ref w 0) (i32-ref w 1))))))
        (w (Gpu %words (list 40 2 0))))
    (Gpu %steps-run (list (Gpu %step (lit sum) form (list w) 1 1)))
    (let ((r (list (Gpu %word w 2) (Gpu %word w 0))))
      (Gpu %words-done w)
      r))
  (list 42 40))
```
---
    (42 40)

### a team's members each take a share, and team-sum adds the shares up

A kernel that names a team is run by one at each grid point. Here a point
is a row of a 3 by 40 matrix: each member sums the elements at its own
place and every team's width after it, and the first member writes the
team's sum. A row is longer than a team, so a member has more than one
element.

```x
(import x/num/float/literal)
(import x/num/gpu)
(if (Gpu available?)
  (let ((a (Gpu hold (Matrix from (List map (fn (_ r) (List map (fn (_ c) (+ r 1)) (List range 0 40))) (List range 0 3)))))
        (out (Gpu hold (Tensor from '(0 0 0))))
        (form (lit (fn (_ a out n)
                     (let ((w (i32-ref n 0)))
                       (let ((sum (team-sum (let go ((j member) (s (i->f 0)))
                                              (if (< j w) (go (+ j team) (f+ s (f32-ref a (+ (* at-x w) j)))) s)))))
                         (if (= member 0) (f32-set! out at-x sum)))))))
        (width (Gpu %words (list 40))))
    (Gpu %steps-run (list (Gpu %step (lit rows) form (list (Gpu %buffer-of a) (Gpu %buffer-of out) width) 3 1)))
    (let ((r (out ->list)))
      (Gpu %words-done width)
      (Gpu release a)
      (Gpu release out)
      r))
  (lit (40.0 80.0 120.0)))
```
---
    (40.0 80.0 120.0)

### a loop's next values are worked out before any of its variables is set

A loop called with one of its own variables as another's next value takes
the value the variable had: here `was` follows `j` one step behind, and
the last `was` is 3.

```x
(import x/num/gpu)
(if (Gpu available?)
  (let ((w (Gpu %words (list 0)))
        (form (lit (fn (_ w) (i32-set! w 0 (let go ((j 0) (was 0)) (if (< j 4) (go (+ j 1) j) was)))))))
    (Gpu %steps-run (list (Gpu %step (lit behind) form (list w) 1 1)))
    (let ((r (Gpu %word w 0)))
      (Gpu %words-done w)
      r))
  3)
```
---
    3

### a kernel over a grid more than one point down

at-x is the point's place across and at-y its place down: here each
element of a 3 by 2 matrix is written 10 times its row plus its column.

```x
(import x/num/float/literal)
(import x/num/gpu)
(if (Gpu available?)
  (let ((a (Gpu hold (Matrix from '((0 0) (0 0) (0 0)))))
        (form (lit (fn (_ a) (f32-set! a (+ (* at-y 2) at-x) (i->f (+ (* at-y 10) at-x)))))))
    (Gpu %steps-run (list (Gpu %step (lit number) form (list (Gpu %buffer-of a)) 2 3)))
    (let ((r (a ->list)))
      (Gpu release a)
      r))
  (lit ((0.0 1.0) (10.0 11.0) (20.0 21.0))))
```
---
    ((0.0 1.0) (10.0 11.0) (20.0 21.0))

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
