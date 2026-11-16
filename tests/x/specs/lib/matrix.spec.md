# matrices and linear algebra (Matrix)
# @weight 2

`Matrix` is a `Tensor` of rank 2 with the linear algebra: the matrix
product, solve, inverse, determinant, trace, diagonal and norm, and its
lower-upper, Cholesky, orthogonal-upper, symmetric eigen and eigen
factorizations, a `LowerUpper`, a `Cholesky`, an `Orthogonal`, a
`SymmetricEigen` and an `Eigen`. Every result of the linear algebra is
f64, or c128 for `Eigen`, so the cases answer the same on a 4-byte word as
on an 8-byte one.

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

## The orthogonal-upper factorization

### the parts of a factorization

```x
(import x/num/matrix)
(let ((f ((Matrix from '((0 1) (1 1))) factor-orthogonal)))
  (list (class-name f) ((f orthogonal) ->list) ((f upper) ->list)))
```
---
    ('Orthogonal ((0.0 -1.0) (-1.0 0.0)) ((-1.0 -1.0) (0.0 -1.0)))

### Q times R is the matrix, and Q's columns are orthonormal

```x
(import x/num/matrix)
(import x/num/float f-lt)
(let ((near (fn (_ a b) (let ((d (a sub b))) (f-lt ((d mul d) sum) 0.000000000000000001)))))
  (List map
    (fn (_ rows)
      (let ((a (Matrix from rows)))
        (let ((f (a factor-orthogonal)))
          (let ((q (f orthogonal)) (r (f upper)))
            (list (q extent) (r extent) (near (q product r) a)
                  (near ((q transpose) product q) (Matrix identity (List ref 1 (q extent)))))))))
    '(((1 2 3) (4 5 6) (7 8 10) (2 1 1)) ((1 2 3) (4 5 6)) ((2 -1 0) (-1 2 -1) (0 -1 2)))))
```
---
    (((4 3) (3 3) #t #t) ((2 2) (2 3) #t #t) ((3 3) (3 3) #t #t))

### solve fits least squares

```x
(import x/num/matrix)
(import x/num/float f-lt)
(let ((near (fn (_ a b) (let ((d (a sub b))) (f-lt ((d mul d) sum) 0.000000000000000001))))
      (a (Matrix from '((1 0) (1 1) (1 2) (1 3)))) (b (Tensor from '(1 2 2 4))))
  (let ((x ((a factor-orthogonal) solve b)))
    (list (x extent) (near x (Tensor from '(0.9 0.9)))
          (near ((a transpose) product ((a product x) sub b)) (Tensor from '(0 0))))))
```
---
    ((2) #t #t)

### a square solve agrees with the lower-upper one

```x
(import x/num/matrix)
(import x/num/float f-lt)
(let ((a (Matrix from '((4 -2 1) (3 6 -4) (2 1 8)))) (b (Matrix from '((1 0) (2 1) (3 0)))))
  (let ((d (((a factor-orthogonal) solve b) sub (a solve b))))
    (list (class-name d) (f-lt ((d mul d) sum) 0.000000000000000001))))
```
---
    ('Matrix #t)

### solve refuses a wide matrix, dependent columns and a mismatched b

```x
(import x/num/matrix)
(list (guard (e (Err label e)) (((Matrix from '((1 2 3) (4 5 6))) factor-orthogonal) solve (Tensor from '(1 1))))
      (guard (e (Err label e)) (((Matrix from '((1 0) (1 0) (1 0))) factor-orthogonal) solve (Tensor from '(1 2 3))))
      (guard (e (Err label e)) (((Matrix from '((1 0) (0 1) (1 1))) factor-orthogonal) solve (Tensor from '(1 2)))))
```
---
    ('value 'value 'value)

## The symmetric eigen factorization

### values from least to greatest, vectors as columns

```x
(import x/num/matrix)
(let ((f ((Matrix from '((2 0) (0 1))) factor-symmetric-eigen)))
  (list (class-name f) ((f values) ->list) ((f vectors) ->list)))
```
---
    ('SymmetricEigen (1.0 2.0) ((0.0 1.0) (1.0 0.0)))

### the vectors are orthonormal and rebuild the matrix

```x
(import x/num/matrix)
(import x/num/float f-lt)
(let ((near (fn (_ a b) (let ((d (a sub b))) (f-lt ((d mul d) sum) 0.000000000000000001)))))
  (List map
    (fn (_ rows)
      (let ((a (Matrix from rows)))
        (let ((f (a factor-symmetric-eigen)))
          (let ((v (f vectors)) (w (f values)))
            (list (near ((v mul w) product (v transpose)) a)
                  (near ((v transpose) product v) (Matrix identity (List ref 0 (a extent)))))))))
    '(((2 1) (1 2)) ((4 1 -2) (1 2 0) (-2 0 3)) ((2 -1 0 0) (-1 2 -1 0) (0 -1 2 -1) (0 0 -1 2)))))
```
---
    ((#t #t) (#t #t) (#t #t))

### the values of a known matrix

```x
(import x/num/matrix)
(import x/num/float f-lt)
(let ((w (((Matrix from '((2 1) (1 2))) factor-symmetric-eigen) values))
      (u (((Matrix from '((6 0 0) (0 -1 0) (0 0 3))) factor-symmetric-eigen) values)))
  (let ((d (w sub (Tensor from '(1 3)))))
    (list (f-lt ((d mul d) sum) 0.000000000000000001) (u ->list))))
```
---
    (#t (-1.0 3.0 6.0))

### one row, and a matrix that is not symmetric or not square

```x
(import x/num/matrix)
(let ((f ((Matrix from '((5))) factor-symmetric-eigen)))
  (list ((f values) ->list) ((f vectors) ->list)
        (guard (e (Err label e)) ((Matrix from '((1 2) (3 4))) factor-symmetric-eigen))
        (guard (e (Err label e)) ((Matrix from '((1 2 3) (4 5 6))) factor-symmetric-eigen))))
```
---
    ((5.0) ((1.0)) 'value 'value)

## The eigen factorization

### a rotation's values are a conjugate pair, the positive imaginary part first

```x
(import x/num/matrix)
(let ((e ((Matrix from '((0 -1) (1 0))) factor-eigen)))
  (list (class-name e) ((e values) ->list) ((e vectors) encoding)))
```
---
    ('Eigen (0.0+1.0i 0.0-1.0i) 'c128)

### a diagonal matrix's values and vectors

```x
(import x/num/matrix)
(let ((e ((Matrix from '((2 0) (0 3))) factor-eigen)))
  (list ((e values) ->list) ((e vectors) ->list)))
```
---
    ((2.0+0.0i 3.0+0.0i) ((1.0+0.0i 0.0+0.0i) (0.0+0.0i 1.0+0.0i)))

### the matrix times the vectors is the vectors times the values

```x
(import x/num/matrix)
(import x/num/float f-lt)
(let ((near (fn (_ a b) (let ((d (a sub b))) (f-lt ((d mul d) sum) 0.000000000000000001)))))
  (List map
    (fn (_ rows)
      (let ((a (Matrix from rows)))
        (let ((e (a factor-eigen)))
          (let ((vr ((e vectors) real)) (vi ((e vectors) imaginary))
                (wr ((e values) real)) (wi ((e values) imaginary)))
            (list (near (a product vr) ((vr mul wr) sub (vi mul wi)))
                  (near (a product vi) ((vr mul wi) add (vi mul wr))))))))
    '(((0 -1) (1 0)) ((1 2 3) (4 5 6) (7 8 10)) ((0 0 1) (1 0 0) (0 1 0))
      ((4 -2 1 3) (3 6 -4 1) (2 1 8 -1) (1 -3 2 5))
      ((1 2 0 0 0) (0 1 2 0 0) (0 0 1 2 0) (0 0 0 1 2) (2 0 0 0 1)))))
```
---
    ((#t #t) (#t #t) (#t #t) (#t #t) (#t #t))

### the values of a known matrix, and the vectors' length

```x
(import x/num/matrix)
(import x/num/float f-lt)
(let ((e ((Matrix from '((0 0 1) (1 0 0) (0 1 0))) factor-eigen)))
  (let ((w (e values)) (v (e vectors)))
    (let ((d ((w real) sub (Tensor from '(-0.5 -0.5 1))))
          (h (((w imaginary) mul (w imaginary)) sub (Tensor from '(0.75 0.75 0))))
          (n (((((v real) mul (v real)) add ((v imaginary) mul (v imaginary))) transpose) product (Tensor from '(1 1 1)))))
      (let ((m (n sub 1)))
        (list (f-lt ((d mul d) sum) 0.000000000000000001) (f-lt ((h mul h) sum) 0.000000000000000001)
              (f-lt ((m mul m) sum) 0.000000000000000001))))))
```
---
    (#t #t #t)

### a pair's vectors are conjugates, and a real value's vector is real

```x
(import x/num/matrix)
(let ((e ((Matrix from '((0 0 1) (1 0 0) (0 1 0))) factor-eigen)))
  (let ((v (e vectors)))
    (list (equal? (((v slice 1 0 1) conjugate) ->list) ((v slice 1 1 2) ->list))
          (((v slice 1 2 3) imaginary) ->list))))
```
---
    (#t ((0.0) (0.0) (0.0)))

### one row, and a matrix that is not square

```x
(import x/num/matrix)
(let ((e ((Matrix from '((5))) factor-eigen)))
  (list ((e values) ->list) ((e vectors) ->list)
        (guard (x (Err label x)) ((Matrix from '((1 2 3) (4 5 6))) factor-eigen))))
```
---
    ((5.0+0.0i) ((1.0+0.0i)) 'value)

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
  (let ((before (list ((a inverse) ->list) (a determinant) ((a solve b) ->list)
                      (((a factor-orthogonal) solve b) ->list)
                      (((((a transpose) product a) factor-symmetric-eigen) values) ->list)
                      (((a factor-eigen) vectors) ->list))))
    (Matrix jit!)
    (equal? before (list ((a inverse) ->list) (a determinant) ((a solve b) ->list)
                         (((a factor-orthogonal) solve b) ->list)
                         (((((a transpose) product a) factor-symmetric-eigen) values) ->list)
                         (((a factor-eigen) vectors) ->list)))))
```
---
    #t
