# n-dimensional arrays (Tensor)
# @weight 2

`Tensor` packs f64, f32, i64 or c128 elements in bytes under an extent and
strides.
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

### div of integers is f64

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

## Comparisons

### the six comparisons answer masks of 1.0 and 0.0

```x
(import x/num/tensor)
(let ((t (Tensor from '(1 5 3) 'f64)))
  (List map (fn (_ m) (m ->list))
    (list (t less 3) (t greater 3) (t at-most 3) (t at-least 3) (t equal 3) (t differ 3))))
```
---
    ((1.0 0.0 0.0) (0.0 1.0 0.0) (1.0 0.0 1.0) (0.0 1.0 1.0) (0.0 0.0 1.0) (1.0 1.0 0.0))

### a comparison broadcasts, reads a strided view, and answers f64 whatever it compares

```x
(import x/num/tensor)
(let ((t (Tensor from '((1 2) (3 4)) 'f64)))
  (list ((t less (Tensor from '(2 4) 'f64)) ->list)
        (((t transpose) greater 2) ->list)
        (((Tensor from '(1 2) 'f32) less 2) encoding)
        (((Tensor from '(1 2)) at-least (Tensor from '(2 2))) ->list)))
```
---
    (((1.0 1.0) (0.0 0.0)) ((0.0 1.0) (0.0 1.0)) 'f64 (0.0 1.0))

### a NaN is less than, at most and equal to nothing, and differs from everything

```x
(import x/num/tensor)
(let ((n ((Tensor from '(0 1) 'f64) div (Tensor from '(0 1) 'f64))))
  (List map (fn (_ m) (m ->list))
    (list (n less 2) (n greater 0) (n at-most n) (n at-least n) (n equal n) (n differ n))))
```
---
    ((0.0 1.0) (0.0 1.0) (0.0 1.0) (0.0 1.0) (0.0 1.0) (1.0 0.0))

### complex numbers are not compared

```x
(import x/num/tensor)
(let ((z (Tensor complex (Tensor from '(1 2)) (Tensor from '(3 4)))))
  (list (guard (e (Err label e)) (z equal z)) (guard (e (Err label e)) ((Tensor from '(1 2) 'f64) less z))))
```
---
    ('value 'value)

### the masks are the same once the kernels are compiled

```x
(import x/num/tensor)
(let ((a (Tensor from '((1.5 2) (3 4)))) (b (Tensor from '(2 4) 'f32)) (c (Tensor from '(3 1 3 7))))
  (let ((run (fn (_) (List map (fn (_ m) (m ->list))
                       (list (a less b) (a greater b) (a at-most b) (a at-least b) (a equal b) (a differ b)
                             (b less 3) (b equal 4) (c at-most 3) (c differ 3) (c greater 2))))))
    (let ((before (run)))
      (Tensor jit!)
      (list (equal? before (run)) (first before)))))
```
---
    (#t ((1.0 1.0) (0.0 0.0)))

## Reductions

### sum, min, max

```x
(import x/num/tensor)
(let ((t (Tensor from '((3 -1) (2 4)) 'f64)))
  (list (t sum) (t min) (t max)))
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
    (list (t sum) (t min) (t max) ((Tensor zeros 0 'i64) sum))))
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

## f32

An f32 element is a single, a 32-bit float, in 4 bytes. It is read as a
Float, which holds it exactly, and a Float stored is rounded to the
nearest single: 0.1 reads back as 0.100000001490116.

### an f32 tensor is asked for, and holds singles

```x
(import x/num/tensor)
(let ((t (Tensor from '(1 2.5 0.1) 'f32)))
  (list (t encoding) (t ->list)))
```
---
    ('f32 (1.0 2.5 0.100000001490116))

### zeros, fill, ref and set!

```x
(import x/num/tensor)
(list ((Tensor zeros 2 'f32) ->list) ((Tensor fill 2 1.5 'f32) ->list)
      (((Tensor zeros 3 'f32) set! -1 0.1) ref 2))
```
---
    ((0.0 0.0) (1.5 1.5) 0.100000001490116)

### f32 stays f32 with f32 and with a number, div included; an f64 tensor makes f64

```x
(import x/num/tensor)
(let ((a (Tensor from '(1 2) 'f32)))
  (list ((a add a) encoding) ((a mul 0.5) encoding) ((a div 3) encoding)
        ((a add (Tensor from '(1 2) 'f64)) encoding) (((Tensor from '(1 2) 'f64) sub a) encoding)))
```
---
    ('f32 'f32 'f32 'f64 'f64)

### f32 stays f32 with an i64 tensor

```x
(import x/num/tensor)
(if (< %word-size 8) (lit (f32 (2.0 5.0)))
  (let ((t ((Tensor from '(1 2.5) 'f32) mul (Tensor from '(2 2)))))
    (list (t encoding) (t ->list))))
```
---
    ('f32 (2.0 5.0))

### the arithmetic answers what single arithmetic does: 1 over 3 is the single nearest a third

```x
(import x/num/tensor)
(list (((Tensor from '(1) 'f32) div 3) ->list)
      (((Tensor from '(1 2.5 3) 'f32) add 0.1) ->list)
      (((Tensor from '(1 5 3) 'f32) min 2) ->list))
```
---
    ((0.333333343267441) (1.10000002384186 2.59999990463257 3.09999990463257) (1.0 2.0 2.0))

### the reductions answer Floats, the sum kept in a double

```x
(import x/num/tensor)
(let ((t (Tensor from '(1 2.5 3) 'f32)))
  (list (t sum) (t min) (t max) (t mean) ((Tensor zeros 0 'f32) sum)))
```
---
    (6.5 1.0 3.0 2.16666666666667 0.0)

### views step by elements of 4 bytes

```x
(import x/num/tensor)
(let ((m (Tensor from '((1 2 3) (4 5 6)) 'f32)))
  (list ((m transpose) ->list) (((m transpose) copy) ->list)
        (((m slice 1 1 3) add (Tensor from '(10 20) 'f32)) ->list)
        ((m transpose) sum)))
```
---
    (((1.0 4.0) (2.0 5.0) (3.0 6.0)) ((1.0 4.0) (2.0 5.0) (3.0 6.0)) ((12.0 23.0) (15.0 26.0)) 21.0)

### as rounds f64 to f32, and widens f32 to f64 exactly

```x
(import x/num/tensor)
(let ((t ((Tensor from '(0.1 2.5) 'f64) as 'f32)))
  (list (t encoding) (t ->list) ((t as 'f64) encoding) ((t as 'f64) ->list)))
```
---
    ('f32 (0.100000001490116 2.5) 'f64 (0.100000001490116 2.5))

### as converts between f32 and i64, truncating toward zero

```x
(import x/num/tensor)
(if (< %word-size 8) (lit ((2 -2) f32 (1.0 2.0)))
  (list (((Tensor from '(2.5 -2.5) 'f32) as 'i64) ->list)
        (((Tensor from '(1 2)) as 'f32) encoding) (((Tensor from '(1 2)) as 'f32) ->list)))
```
---
    ((2 -2) 'f32 (1.0 2.0))

### f32 mixes with complex numbers to c128

```x
(import x/num/tensor)
(let ((a (Tensor from '(1 2.5) 'f32)))
  (list ((a as 'c128) ->list) ((Tensor complex a 1) ->list)))
```
---
    ((1.0+0.0i 2.5+0.0i) (1.0+1.0i 2.5+1.0i))

### a complex element is refused

```x
(import x/num/tensor)
(import x/num/complex)
(guard (e (Err label e)) ((Tensor zeros 1 'f32) set! 0 (Complex make 0 1)))
```
---
    'type

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
  (list (guard (e (Err label e)) (t min))
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

### the compiled f32 kernels answer what the pure ones do

```x
(import x/num/tensor)
(let ((a (Tensor from '((1.5 2) (3 0.1)) 'f32)) (b (Tensor from '(0.25 -3) 'f32)))
  (let ((run (fn (_) (list ((a add b) ->list) ((a mul b) ->list) ((a div b) ->list) ((a max b) ->list)
                          (a sum) (a min) (((a transpose) copy) ->list)
                          ((a as 'f64) ->list) (((Tensor from '(0.1 0.7)) as 'f32) ->list)
                          ((Tensor fill 2 0.3 'f32) ->list) ((a as 'c128) ->list)))))
    (let ((before (run)))
      (Tensor jit!)
      (list (equal? before (run))
            (List all? (fn (_ k) (List any? (fn (_ c) (eq? c k)) (Tensor compiled)))
              (if (List includes? (lit f64-add) (Tensor compiled)) (lit (f32-add f32-div f32-sum f32-copy f32->f64 f64->f32)) ()))))))
```
---
    (#t #t)


## gather

### the entries the indexes pick, in their order, an index as often as it comes

```x
(import x/num/tensor)
(let ((t (Tensor from '(10 20 30 40) 'f64)))
  (list ((t gather '(2 0 2)) ->list) ((t gather '(-1 -4)) ->list)
        ((t gather '(3 2 1 0)) ->list) (t ->list)))
```
---
    ((30.0 10.0 30.0) (40.0 10.0) (40.0 30.0 20.0 10.0) (10.0 20.0 30.0 40.0))

### rows of a matrix, and whole slabs of a higher rank

```x
(import x/num/tensor)
(let ((m (Tensor from '((1 2) (3 4) (5 6)) 'f64))
      (c (Tensor from '(((1 2) (3 4)) ((5 6) (7 8))) 'f64)))
  (list ((m gather '(2 0)) ->list) ((m gather '(2 0)) extent)
        ((c gather '(1 1 0)) extent) ((c gather '(1)) ->list)))
```
---
    (((5.0 6.0) (1.0 2.0)) (2 2) (3 2 2) (((5.0 6.0) (7.0 8.0))))

### the encoding is kept, and a view that is not contiguous gathers as it reads

```x
(import x/num/tensor)
(let ((m (Tensor from '((1 2 3) (4 5 6)) 'f64)))
  (list (((Tensor from '(1.5 2.5 3.5) 'f32) gather '(2 0)) encoding)
        (((Tensor from '(1.5 2.5 3.5) 'f32) gather '(2 0)) ->list)
        (((m transpose) gather '(2 0)) ->list)
        (((m slice 1 1 3) gather '(1)) ->list)
        ((((Tensor from '((1 2) (3 4) (5 6)) 'f64) slice 0 1 3) gather '(1 0)) ->list)))
```
---
    ('f32 (3.5 1.5) ((3.0 6.0) (1.0 4.0)) ((5.0 6.0)) ((5.0 6.0) (3.0 4.0)))

### no indexes answers a tensor of no entries; a Matrix stays a Matrix

```x
(import x/num/tensor) (import x/num/matrix)
(list (((Tensor from '(1 2 3) 'f64) gather ()) extent)
      (((Tensor from '((1 2) (3 4)) 'f64) gather ()) extent)
      (class-name ((Matrix from '((1 2) (3 4)) 'f64) gather '(1 0)))
      (((Matrix from '((1 2) (3 4)) 'f64) gather '(1 0)) ->list))
```
---
    ((0) (0 2) 'Matrix ((3.0 4.0) (1.0 2.0)))

### an index outside the axis, one that is no integer, and a rank-0 tensor are refused

```x
(import x/num/tensor)
(let ((t (Tensor from '(10 20 30) 'f64)))
  (list (guard (e (Err label e)) (t gather '(3)))
        (guard (e (Err label e)) (t gather '(-4)))
        (guard (e (Err label e)) (t gather '(1.5)))
        (guard (e (Err label e)) ((Tensor from 7.0) gather '(0)))))
```
---
    ('value 'value 'type 'value)

### the answers are the same once the kernels are compiled

```x
(import x/num/tensor)
(let ((m (Tensor from '((1 2) (3 4) (5 6)) 'f64))
      (z (Tensor from (list 1+2i 3-1i 5) 'c128))
      (s (Tensor from '(1.5 2.5 3.5) 'f32)))
  (let ((run (fn (_) (list ((m gather '(2 0 -1 1)) ->list) ((m gather ()) extent)
                           (((m transpose) gather '(1 1)) ->list)
                           ((z gather '(2 0)) ->list) ((s gather '(2 0 1)) ->list)))))
    (let ((before (run)))
      (Tensor jit!)
      (list (equal? before (run)) (first before)))))
```
---
    (#t ((5.0 6.0) (1.0 2.0) (5.0 6.0) (3.0 4.0)))

### the refusals are the same once the kernels are compiled, the first in the list's order

```x
(import x/num/tensor)
(let ((t (Tensor from '(10 20 30) 'f64)))
  (let ((run (fn (_) (list (guard (e (list (Err label e) (e data))) (t gather '(0 3 1.5)))
                           (guard (e (list (Err label e) (e data))) (t gather '(0 1.5 3)))
                           (guard (e (list (Err label e) (e data))) (t gather '(2 -4)))
                           (guard (e (Err label e)) (t gather '(1.5)))
                           ((t gather '(-1 -3 2 0)) ->list)))))
    (let ((before (run)))
      (Tensor jit!)
      (list (equal? before (run)) (List map first (List take 3 before)) (List ref 4 before)))))
```
---
    (#t ('value 'type 'value) (30.0 10.0 30.0 10.0))

## Other names

### extent, encoding and deviation carry the names other libraries use

```x
(import x/num/tensor)
(list ((Doc entry 'Tensor/extent) known-as)
      ((Doc entry 'Tensor/encoding) known-as)
      ((Doc entry 'Tensor/deviation) known-as))
```
---
    (("shape") ("dtype") ("standard deviation" "std"))

### the comparisons carry the short names other libraries use

```x
(import x/num/tensor)
(List map (fn (_ n) ((Doc entry n) known-as))
  '(Tensor/less Tensor/greater Tensor/at-most Tensor/at-least Tensor/equal Tensor/differ))
```
---
    (("lt" "less than") ("gt" "greater than") ("le" "lte" "less than or equal") ("ge" "gte" "greater than or equal") ("eq" "equal to") ("ne" "neq" "not equal"))

## Runs along other axes

An element-wise operation is free to walk its axes in any order and to make
them fewer first; the answers are the ones row-major order gives.

### a row against a tall tensor

```x
(import x/num/tensor)
(((Tensor from '((1 2) (3 4) (5 6)) 'f64) add (Tensor from '(10 20) 'f64)) ->list)
```
---
    ((11.0 22.0) (13.0 24.0) (15.0 26.0))

### a transposed view against a tensor

```x
(import x/num/tensor)
((((Tensor from '((1 2 3) (4 5 6)) 'f64) transpose) mul (Tensor from '((1 10) (2 20) (3 30)) 'f64)) ->list)
```
---
    ((1.0 40.0) (4.0 100.0) (9.0 180.0))

### a column stretched across three axes, the last the longest

Element (i j k) of the first is 12i + 4j + k, and row j of the column adds
100(j + 1).

```x
(import x/num/tensor)
(do
  (def tn-sum3 (((Tensor range 24 'f64) reshape '(2 3 4)) add (Tensor from '((100) (200) (300)) 'f64)))
  (list (tn-sum3 ref 0 0 0) (tn-sum3 ref 0 2 3) (tn-sum3 ref 1 1 2) (tn-sum3 ref 1 2 3) (tn-sum3 sum)))
```
---
    (100.0 311.0 218.0 323.0 5076.0)

### a column stretched across three axes, the first the longest

Element (i j k) of the first is 6i + 3j + k, and row j of the column adds
10(j + 1).

```x
(import x/num/tensor)
(do
  (def tn-sum5 (((Tensor range 30 'f64) reshape '(5 2 3)) add (Tensor from '((10) (20)) 'f64)))
  (list (tn-sum5 extent) (tn-sum5 ref 0 0 0) (tn-sum5 ref 4 1 2) (tn-sum5 ref 2 0 1) (tn-sum5 sum)))
```
---
    ((5 2 3) 10.0 49.0 23.0 885.0)

### a column of a matrix: its reductions, and a number against it

```x
(import x/num/tensor)
(do
  (def tn-col ((Tensor from '((1 2) (3 4) (5 6)) 'f64) slice 1 1 2))
  (list (tn-col sum) (tn-col min) (tn-col max) ((tn-col mul 2) ->list)))
```
---
    (12.0 2.0 6.0 ((4.0) (8.0) (12.0)))
