# n-dimensional arrays (Tensor)
# @weight 2

`Tensor` packs f64 or i64 elements in bytes under an extent and strides.
Transpose, slice and reshape answer views over the same bytes; the
element-wise operations broadcast; the arithmetic runs in word-form kernels
that compile once they have run long enough, and answer the same either way.

An i64 element fills one word only on an 8-byte word. On a 4-byte word
integers make f64 and i64 is refused, so the cases outside the i64 section
ask for f64 and answer the same on either word, and each i64 case answers
on a 4-byte word only when i64 is refused there.

## Making tensors

### from nested lists, the extent read off the nesting

```x
(import x/num/tensor)
((Tensor from '((1 2 3) (4 5 6))) extent)
```
---
    (2 3)

### a non-integer element makes f64

```x
(import x/num/tensor)
((Tensor from '(1 2.5)) ->list)
```
---
    (1.0 2.5)

### an encoding can be asked for

```x
(import x/num/tensor)
((Tensor from '(1 2) 'f64) ->list)
```
---
    (1.0 2.0)

### from vectors as well as lists

```x
(import x/num/tensor)
((Tensor from #(#(1 2) #(3 4)) 'f64) ->list)
```
---
    ((1.0 2.0) (3.0 4.0))

### zeros and fill

```x
(import x/num/tensor)
(list ((Tensor zeros '(2 2)) ->list) ((Tensor fill '(2 3) 7.5) ->list))
```
---
    (((0.0 0.0) (0.0 0.0)) ((7.5 7.5 7.5) (7.5 7.5 7.5)))

### range

```x
(import x/num/tensor)
((Tensor range 3 'f64) ->list)
```
---
    (0.0 1.0 2.0)

### ragged lists are refused

```x
(import x/num/tensor)
(guard (e (Err label e)) (Tensor from '((1 2) (3))))
```
---
    'value

### an unknown encoding is refused

```x
(import x/num/tensor)
(guard (e (Err label e)) (Tensor zeros 2 'u3))
```
---
    'value

## Elements

### ref, negative indexes from the end

```x
(import x/num/tensor)
(let ((t (Tensor from '((1 2) (3 4)) 'f64)))
  (list (t ref 1 0) (t ref -1 -1)))
```
---
    (3.0 4.0)

### set! stores and answers the tensor

```x
(import x/num/tensor)
(((Tensor zeros 3) set! 1 9) ->list)
```
---
    (0.0 9.0 0.0)

### an index past the axis is refused

```x
(import x/num/tensor)
(guard (e (Err label e)) ((Tensor range 3 'f64) ref 3))
```
---
    'value

## Views

### transpose

```x
(import x/num/tensor)
(let ((t ((Tensor from '((1 2 3) (4 5 6)) 'f64) transpose)))
  (list (t ->list) (t strides) (t contiguous?)))
```
---
    (((1.0 4.0) (2.0 5.0) (3.0 6.0)) (1 3) #f)

### slice of the inner axis

```x
(import x/num/tensor)
(((Tensor from '((1 2 3) (4 5 6)) 'f64) slice 1 1 3) ->list)
```
---
    ((2.0 3.0) (5.0 6.0))

### a view shares its bytes

```x
(import x/num/tensor)
(let ((t (Tensor range 6 'f64)))
  ((t slice 0 2 4) set! 0 99)
  (t ->list))
```
---
    (0.0 1.0 99.0 3.0 4.0 5.0)

### reshape of a contiguous tensor

```x
(import x/num/tensor)
(((Tensor range 6 'f64) reshape '(2 3)) ->list)
```
---
    ((0.0 1.0 2.0) (3.0 4.0 5.0))

### reshape of a transpose copies first

```x
(import x/num/tensor)
(((((Tensor range 6 'f64) reshape '(2 3)) transpose) reshape 6) ->list)
```
---
    (0.0 3.0 1.0 4.0 2.0 5.0)

### a reshape to a different size is refused

```x
(import x/num/tensor)
(guard (e (Err label e)) ((Tensor range 6 'f64) reshape '(4 2)))
```
---
    'value

## Arithmetic

### element-wise with a number

```x
(import x/num/tensor)
(list (((Tensor from '(1 2 3) 'f64) add 10) ->list) (((Tensor from '(5 7) 'f64) sub 2) ->list))
```
---
    ((11.0 12.0 13.0) (3.0 5.0))

### element-wise with a tensor

```x
(import x/num/tensor)
(((Tensor from '(1 2 3) 'f64) mul (Tensor from '(4 5 6) 'f64)) ->list)
```
---
    (4.0 10.0 18.0)

### a row broadcasts over every row

```x
(import x/num/tensor)
(((Tensor from '((1 2) (3 4)) 'f64) add (Tensor from '(10 20) 'f64)) ->list)
```
---
    ((11.0 22.0) (13.0 24.0))

### a column broadcasts over every column

```x
(import x/num/tensor)
(((Tensor from '((1 2) (3 4)) 'f64) add (Tensor from '((10) (20)) 'f64)) ->list)
```
---
    ((11.0 12.0) (23.0 24.0))

### div is always f64

```x
(import x/num/tensor)
(((Tensor from '(1 2 3)) div 2) ->list)
```
---
    (0.5 1.0 1.5)

### min and max

```x
(import x/num/tensor)
(let ((t (Tensor from '(1 5 3) 'f64)))
  (list ((t min 2) ->list) ((t max 2) ->list)))
```
---
    ((1.0 2.0 2.0) (2.0 5.0 3.0))

### arithmetic on a strided view

```x
(import x/num/tensor)
(let ((t (Tensor from '((1 2) (3 4)) 'f64)))
  (((t transpose) sub t) ->list))
```
---
    ((0.0 1.0) (-1.0 0.0))

### extents that do not broadcast are refused

```x
(import x/num/tensor)
(guard (e (Err label e)) ((Tensor range 3 'f64) add (Tensor range 2 'f64)))
```
---
    'value

## Reductions

### sum, least, greatest

```x
(import x/num/tensor)
(let ((t (Tensor from '((3 -1) (2 4)) 'f64)))
  (list (t sum) (t least) (t greatest)))
```
---
    (8.0 -1.0 4.0)

### the mean

```x
(import x/num/tensor)
((Tensor from '(1 2 3 4)) mean)
```
---
    2.5

### a reduction over a strided view

```x
(import x/num/tensor)
(((Tensor from '((1 2 3) (4 5 6)) 'f64) slice 1 1 2) sum)
```
---
    7.0

### a long run goes through the budgeted pure kernel

```x
(import x/num/tensor)
((Tensor range 1000 'f64) sum)
```
---
    499500.0

### the sum of no elements is 0

```x
(import x/num/tensor)
((Tensor zeros 0) sum)
```
---
    0.0

## Statistics

### variance divides by the count less 1, or less the correction given

```x
(import x/num/tensor)
(let ((t (Tensor from '(2 4 4 4 5 5 7 9) 'f64)))
  (list (t variance 0) (t variance 1) (t variance)))
```
---
    (4.0 4.57142857142857 4.57142857142857)

### deviation is the square root of the variance

```x
(import x/num/tensor)
(let ((t (Tensor from '((2 4 4 4) (5 5 7 9)) 'f64)))
  (list (t deviation 0) ((Tensor from '(1 3) 'f64) deviation)))
```
---
    (2.0 1.4142135623731)

### a c128 variance sums the squared magnitudes

```x
(import x/num/tensor)
(import x/num/complex)
((Tensor from (list (Complex make 1 1) (Complex make -1 -1))) variance 0)
```
---
    2.0

### a variance needs more elements than the correction

```x
(import x/num/tensor)
(list (guard (e (Err label e)) ((Tensor from '(5) 'f64) variance))
      ((Tensor from '(5) 'f64) variance 0))
```
---
    ('value 0.0)

### quantile interpolates between the sorted elements

```x
(import x/num/tensor)
(let ((t (Tensor from '(4 1 3 2) 'f64)))
  (list (t quantile 0) (t quantile 0.25) (t quantile 0.5) (t quantile 1)))
```
---
    (1.0 1.75 2.5 4.0)

### median of an odd and an even count, and over a matrix's every element

```x
(import x/num/tensor)
(list ((Tensor from '(3 1 4 1 5) 'f64) median) ((Tensor from '(1 2 3 4) 'f64) median)
      ((Tensor from '((9 1) (5 3)) 'f64) median))
```
---
    (3.0 2.5 4.0)

### quantile refuses a q outside 0 to 1, no elements and complex numbers

```x
(import x/num/tensor)
(import x/num/complex)
(List map (fn (_ thunk) (guard (e (Err label e)) (thunk)))
  (list (fn (_) ((Tensor from '(1 2) 'f64) quantile 2))
        (fn (_) ((Tensor zeros '(0) 'f64) median))
        (fn (_) ((Tensor from (list (Complex make 0 1))) median))))
```
---
    ('value 'value 'value)

## i64

### integers make i64 on an 8-byte word and f64 on a 4-byte word

```x
(import x/num/tensor)
(eq? ((Tensor from '(1 2)) encoding) (if (= %word-size 8) 'i64 'f64))
```
---
    #t

### i64 is refused on a 4-byte word

```x
(import x/num/tensor)
(if (= %word-size 8) 'value (guard (e (Err label e)) (Tensor zeros 1 'i64)))
```
---
    'value

### i64 arithmetic stays i64

```x
(import x/num/tensor)
(if (< %word-size 8) (lit ((11 22) (13 24)))
  (((Tensor from '((1 2) (3 4))) add (Tensor from '(10 20))) ->list))
```
---
    ((11 22) (13 24))

### i64 reductions answer integers

```x
(import x/num/tensor)
(if (< %word-size 8) (lit (8 -1 4 0))
  (let ((t (Tensor from '((3 -1) (2 4)))))
    (list (t sum) (t least) (t greatest) ((Tensor zeros 0 'i64) sum))))
```
---
    (8 -1 4 0)

### as converts to i64, truncating toward zero

```x
(import x/num/tensor)
(if (< %word-size 8) (lit (2 -2))
  (((Tensor from '(2.5 -2.5)) as 'i64) ->list))
```
---
    (2 -2)

## c128

### a complex element makes a c128 tensor

```x
(import x/num/tensor)
(import x/num/complex)
(let ((t (Tensor from (list 1 (Complex make 0 2) 3.5))))
  (list (t encoding) (t ->list) (t ref 1) ((Tensor zeros 2 'c128) ->list)))
```
---
    ('c128 (1.0+0.0i 0.0+2.0i 3.5+0.0i) 0.0+2.0i (0.0+0.0i 0.0+0.0i))

### the real and imaginary parts are views

```x
(import x/num/tensor)
(let ((t (Tensor complex (Tensor from '((1 2) (3 4))) (Tensor from '(10 20)))))
  (let ((re (t real)) (im (t imaginary)))
    (re set! 0 1 9)
    (list (re encoding) (re ->list) (im ->list) (t ref 0 1) ((t transpose) ->list))))
```
---
    ('f64 ((1.0 9.0) (3.0 4.0)) ((10.0 20.0) (10.0 20.0)) 9.0+20.0i ((1.0+10.0i 3.0+10.0i) (9.0+20.0i 4.0+20.0i)))

### the arithmetic

```x
(import x/num/tensor)
(import x/num/complex)
(let ((a (Tensor from (list (Complex make 1 2) (Complex make 3 -1))))
      (b (Tensor from (list (Complex make 3 4) (Complex make 0 2)))))
  (list ((a add b) ->list) ((a sub b) ->list) ((a mul b) ->list) ((a div b) ->list)))
```
---
    ((4.0+6.0i 3.0+1.0i) (-2.0-2.0i 3.0-3.0i) (-5.0+10.0i 2.0+6.0i) (0.44+0.08i -0.5-1.5i))

### reals and complex numbers mix to c128

```x
(import x/num/tensor)
(import x/num/complex)
(list (((Tensor from '(1 2)) add (Complex make 0 1)) ->list)
      (((Tensor from '(1.5 2)) mul (Tensor from (list (Complex make 0 1)))) ->list)
      (((Tensor from '(1 2) 'f64) as 'c128) encoding))
```
---
    ((1.0+1.0i 2.0+1.0i) (0.0+1.5i 0.0+2.0i) 'c128)

### sum, mean and conjugate

```x
(import x/num/tensor)
(let ((t (Tensor complex (Tensor from '(1 2 3)) (Tensor from '(4 -5 7)))))
  (list (t sum) (t mean) ((t conjugate) ->list) ((Tensor zeros 0 'c128) sum)))
```
---
    (6.0+6.0i 2.0+2.0i (1.0-4.0i 2.0+5.0i 3.0-7.0i) 0.0+0.0i)

### c128 has no order and no real copy

```x
(import x/num/tensor)
(import x/num/complex)
(let ((t (Tensor from (list (Complex make 1 2)))))
  (list (guard (e (Err label e)) (t least))
        (guard (e (Err label e)) (t min 0))
        (guard (e (Err label e)) (t as 'f64))
        (guard (e (Err label e)) ((Tensor zeros 1) set! 0 (Complex make 1 1)))))
```
---
    ('value 'value 'value 'type)

## Compiled kernels

### a compiled kernel answers what the pure one does

```x
(import x/num/tensor)
(let ((a (Tensor from '((1.5 2) (3 4)))) (b (Tensor from '(0.25 -1))))
  (let ((before ((a add b) ->list)))
    (Tensor jit!)
    (equal? before ((a add b) ->list))))
```
---
    #t

### jit! answers the kernels running compiled

```x
(import x/num/tensor)
(Tensor jit!)
(List all? symbol? (Tensor compiled))
```
---
    #t

### the compiled c128 kernels answer what the pure ones do

```x
(import x/num/tensor)
(import x/num/complex)
(let ((a (Tensor from (list (Complex make 1 2) (Complex make 3 -1) 0.5)))
      (b (Tensor from (list (Complex make 3 4) (Complex make 0 2) (Complex make -2 0.25)))))
  (let ((run (fn (_) (list ((a add b) ->list) ((a mul b) ->list) ((a div b) ->list) (a sum)
                          (((Tensor from '(1.5 2)) as 'c128) ->list)))))
    (let ((before (run)))
      (Tensor jit!)
      (equal? before (run)))))
```
---
    #t
