# matrices and linear algebra (Matrix)
# @weight 2

`Matrix` is a `Tensor` of rank 2 with the linear algebra: the matrix
product, solve, inverse, determinant, trace, diagonal and norm, and its
lower-upper and Cholesky factorizations, a `LowerUpper` and a
`Cholesky`. Every result of the linear algebra is f64, so the cases
answer the same on a 4-byte word as on an 8-byte one.

## Making matrices

### a Matrix is a Tensor of two axes

```x
(import x/num/matrix)
(let ((m (Matrix from '((1 2) (3 4)))))
  (list (class-name m) (instance-of? m Tensor) (m extent)))
```
---
    ('Matrix #t (2 2))

### a making method refuses another rank

```x
(import x/num/matrix)
(guard (e (Err label e)) (Matrix from '(1 2)))
```
---
    'value

### the identity

```x
(import x/num/matrix)
((Matrix identity 3) ->list)
```
---
    ((1.0 0.0 0.0) (0.0 1.0 0.0) (0.0 0.0 1.0))

## The class a result takes

### an operation that keeps two axes answers a Matrix

```x
(import x/num/matrix)
(let ((m (Matrix from '((1 2) (3 4)) 'f64)))
  (List map class-name (list (m transpose) (m add 1) (m slice 0 0 1) (m copy))))
```
---
    ('Matrix 'Matrix 'Matrix 'Matrix)

### one that does not answers a Tensor

```x
(import x/num/matrix)
(let ((m (Matrix from '((1 2) (3 4)) 'f64)))
  (List map class-name (list (m diagonal) (m reshape 4))))
```
---
    ('Tensor 'Tensor)

### a Tensor's operations still answer a Tensor

```x
(import x/num/matrix)
(class-name ((Tensor from '((1 2) (3 4)) 'f64) add 1))
```
---
    'Tensor

## The product

### of two matrices

```x
(import x/num/matrix)
(((Matrix from '((1 2) (3 4))) product (Matrix from '((0 1) (1 0)))) ->list)
```
---
    ((2.0 1.0) (4.0 3.0))

### of different shapes

```x
(import x/num/matrix)
(((Matrix from '((1 2 3) (4 5 6))) product (Matrix from '((1 0) (0 1) (1 1)))) ->list)
```
---
    ((4.0 5.0) (10.0 11.0))

### with a rank-1 Tensor, a column

```x
(import x/num/matrix)
(let ((r ((Matrix from '((1 2) (3 4))) product (Tensor from '(1 1)))))
  (list (class-name r) (r ->list)))
```
---
    ('Tensor (3.0 7.0))

### through a transposed view

```x
(import x/num/matrix)
(let ((m (Matrix from '((1 2) (3 4)) 'f64)))
  (((m transpose) product m) ->list))
```
---
    ((10.0 14.0) (14.0 20.0))

### a mismatched inner axis is refused

```x
(import x/num/matrix)
(guard (e (Err label e)) ((Matrix from '((1 2) (3 4))) product (Matrix from '((1 2 3)))))
```
---
    'value

## Determinant, solve and inverse

### the determinant

```x
(import x/num/matrix)
(List map (fn (_ m) ((Matrix from m) determinant))
  (list '((4 1) (2 3)) '((0 1) (1 0)) '((1 2) (2 4)) '((2 0 0) (0 3 0) (0 0 4))))
```
---
    (10.0 -1.0 0.0 24.0)

### solve against a rank-1 right side

```x
(import x/num/matrix)
(((Matrix from '((2 1) (1 3))) solve (Tensor from '(3 5))) ->list)
```
---
    (0.8 1.4)

### solve when the first pivot is zero

```x
(import x/num/matrix)
(((Matrix from '((0 2) (3 0))) solve (Tensor from '(4 6))) ->list)
```
---
    (2.0 2.0)

### solve against a matrix right side

```x
(import x/num/matrix)
(((Matrix from '((2 0) (0 4))) solve (Matrix from '((2 4) (8 12)))) ->list)
```
---
    ((1.0 2.0) (2.0 3.0))

### the inverse

```x
(import x/num/matrix)
(((Matrix from '((2 0) (0 4))) inverse) ->list)
```
---
    ((0.5 0.0) (0.0 0.25))

### a matrix times its inverse is near the identity

```x
(import x/num/matrix)
(import x/num/float f-lt)
(let ((a (Matrix from '((4 -2 1) (3 6 -4) (2 1 8)))))
  (f-lt (((a product (a inverse)) sub (Matrix identity 3)) norm) 0.000000001))
```
---
    #t

### a singular matrix is refused

```x
(import x/num/matrix)
(let ((m (Matrix from '((1 2) (2 4)))))
  (list (guard (e (Err label e)) (m solve (Tensor from '(1 1))))
        (guard (e (Err label e)) (m inverse))))
```
---
    ('value 'value)

### a non-square matrix is refused

```x
(import x/num/matrix)
(guard (e (Err label e)) ((Matrix from '((1 2 3) (4 5 6))) determinant))
```
---
    'value

## The lower-upper factorization

### the parts of a factorization that swaps its rows

```x
(import x/num/matrix)
(let ((f ((Matrix from '((2 1) (4 3))) factor-lower-upper)))
  (list (class-name f) ((f lower) ->list) ((f upper) ->list) ((f permutation) ->list)))
```
---
    ('LowerUpper ((1.0 0.0) (0.5 1.0)) ((4.0 3.0) (0.0 -0.5)) ((0.0 1.0) (1.0 0.0)))

### the permutation times the matrix is the lower times the upper

```x
(import x/num/matrix)
(import x/num/float f-lt)
(let ((a (Matrix from '((1 2 3) (4 5 6) (7 8 10)))))
  (let ((f (a factor-lower-upper)))
    (list ((f permutation) ->list)
          (f-lt ((((f permutation) product a) sub ((f lower) product (f upper))) norm) 0.000000001))))
```
---
    (((0.0 0.0 1.0) (1.0 0.0 0.0) (0.0 1.0 0.0)) #t)

### one factorization solves several right sides

```x
(import x/num/matrix)
(let ((f ((Matrix from '((2 1) (1 3))) factor-lower-upper)))
  (list ((f solve (Tensor from '(3 5))) ->list)
        ((f solve (Tensor from '(3 4))) ->list)
        (class-name (f solve (Matrix from '((3 3) (5 4)))))
        (f determinant)))
```
---
    ((0.8 1.4) (1.0 1.0) 'Matrix 5.0)

### a singular matrix factors, and its solve is refused

```x
(import x/num/matrix)
(let ((f ((Matrix from '((1 2) (2 4))) factor-lower-upper)))
  (list (f singular?) (f determinant)
        (guard (e (Err label e)) (f solve (Tensor from '(1 1))))))
```
---
    (#t 0.0 'value)

### a non-square matrix does not factor

```x
(import x/num/matrix)
(guard (e (Err label e)) ((Matrix from '((1 2 3) (4 5 6))) factor-lower-upper))
```
---
    'value

## The Cholesky factorization

### the lower factor times its transpose is the matrix

```x
(import x/num/matrix)
(let ((f ((Matrix from '((4 2) (2 5))) factor-cholesky)))
  (list (class-name f) ((f lower) ->list) ((f upper) ->list)
        (((f lower) product (f upper)) ->list)))
```
---
    ('Cholesky ((2.0 0.0) (1.0 2.0)) ((2.0 1.0) (0.0 2.0)) ((4.0 2.0) (2.0 5.0)))

### it solves and answers the determinant

```x
(import x/num/matrix)
(import x/num/float f-lt)
(let ((a (Matrix from '((4 12 -16) (12 37 -43) (-16 -43 98)))))
  (let ((f (a factor-cholesky)) (b (Tensor from '(1 2 3))))
    (list ((f lower) ->list) (f determinant)
          (let ((r ((a product (f solve b)) sub b)))
            (f-lt ((r mul r) sum) 0.000000000000000001)))))
```
---
    (((2.0 0.0 0.0) (6.0 1.0 0.0) (-8.0 5.0 3.0)) 36.0 #t)

### a matrix that is not symmetric, or not positive definite, is refused

```x
(import x/num/matrix)
(list (guard (e (Err label e)) ((Matrix from '((4 2) (1 5))) factor-cholesky))
      (guard (e (Err label e)) ((Matrix from '((1 2) (2 1))) factor-cholesky))
      (guard (e (Err label e)) ((Matrix from '((0 0) (0 1))) factor-cholesky))
      (guard (e (Err label e)) ((Matrix from '((1 2 3) (4 5 6))) factor-cholesky)))
```
---
    ('value 'value 'value 'value)

## Diagonal, trace and norm

### the diagonal is a view

```x
(import x/num/matrix)
(let ((m (Matrix from '((1 2) (3 4)) 'f64)))
  ((m diagonal) set! 1 9)
  (m ->list))
```
---
    ((1.0 2.0) (3.0 9.0))

### trace and norm

```x
(import x/num/matrix)
(list ((Matrix from '((1 2) (3 4)) 'f64) trace) ((Matrix from '((3 0) (0 4))) norm))
```
---
    (5.0 5.0)

## Compiled kernels

### the compiled kernels answer what the pure ones do

```x
(import x/num/matrix)
(let ((a (Matrix from '((4 -2 1) (3 6 -4) (2 1 8)))) (b (Tensor from '(1 2 3))))
  (let ((before (list ((a inverse) ->list) (a determinant) ((a solve b) ->list))))
    (Matrix jit!)
    (equal? before (list ((a inverse) ->list) (a determinant) ((a solve b) ->list)))))
```
---
    #t
