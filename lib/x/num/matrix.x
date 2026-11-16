; matrix.x -- Matrix: a Tensor of rank 2, with the linear algebra.
;
; A Matrix is a Tensor whose extent has two axes, rows then columns, and it
; is everything a Tensor is: the views, the element-wise arithmetic and the
; reductions answer a Matrix while their result keeps two axes, and a Tensor
; once it does not (a diagonal, a reshape to one axis).  On top it has the
; matrix product, solve, inverse and determinant, and trace, diagonal and
; norm.  Every result of the linear algebra is f64.
;
; A factorization is a value of its own: (m factor-lower-upper) answers a
; LowerUpper, which keeps the factors and answers its parts, solves and the
; determinant from them, so a matrix factored once solves many right sides.
; (m factor-cholesky) answers a Cholesky for a symmetric positive-definite
; m, built on a LowerUpper that never swaps a row.  (m factor-orthogonal)
; answers an Orthogonal, the factorization by Householder reflections,
; which solves least squares.  (m factor-symmetric-eigen) answers a
; SymmetricEigen, the eigenvalues and orthonormal eigenvectors of a
; symmetric m, by cyclic Jacobi rotations.
;
; The work is done by nine kernels, word forms (x/tool/word-form) that
; loop over two or three axes inside one run, so an operation costs a few
; runs however large its matrices: the product; LU factorization with
; partial pivoting, a pivot search down a column, a row swap and the
; elimination below a pivot, with forward and back substitution for solve;
; a scale down a column and a reflection of a block of columns for the
; Householder factorization; and a sweep of Jacobi rotations.
; They run on Tensor's lanes, pure in budgeted calls until they have run
; long enough, then compiled once the compiled kernel writes what the pure
; one writes on a check problem.
;
; @copyright 2026 Jon Ruttan
; @license MIT No Attribution (MIT-0)

(module x/num/matrix)
(import x/type/class)
(import x/type/list)
(import x/num/tensor)
(import x/num/float float float-of f-add f-sub f-mul f-div f-lt libm-fn)
(import x/tool/word-form word-form-pure)
(import x/core/doors int+ int- int* int/ int< int= mem-cmp obj-ref ptr->int int->ptr
  ptr-ref-word ptr-set-word! str->ptr str-make type?)

(def-class Matrix (extends Tensor)
  (doc "A Tensor of rank 2, rows then columns, with the linear algebra: the matrix product, solve, inverse, determinant, trace, diagonal and norm. It is every other thing a Tensor is, and an operation on it answers a Matrix while the result keeps two axes."
    (note "Make one as a Tensor is made, (Matrix from '((1 2) (3 4))); a making method refuses an extent that is not two axes. The results of the linear algebra are f64.")
    (example "(((Matrix from '((1 2) (3 4))) product (Matrix from '((0 1) (1 0)))) ->list)" "((2.0 1.0) (4.0 3.0))")
    (example "((Matrix from '((4 1) (2 3))) determinant)" "10.0")
    (see product) (see solve) (see inverse) (see identity))

  (static
    (method identity (self (param n INTEGER "The number of rows and columns"))
      (doc "The n by n identity matrix: 1 on the diagonal, 0 elsewhere."
        (returns Matrix "A fresh f64 matrix")
        (example "((Matrix identity 2) ->list)" "((1.0 0.0) (0.0 1.0))"))
      (let ((f (Tensor %fast)))
        (let ((st ((obj-ref f 4) (lit f64) (list n n))))
          ((obj-ref f 9) st 0)
          ((obj-ref f 9) ((obj-ref f 11) st (list n) (list (int+ n 1)) 0) 1)
          (self %make st))))

    (method jit! (self)
      (doc "Build the compiled version of every Matrix kernel now (JIT; ARM64 and x86-64), adopting each one that writes what its pure version does on the check problem. Answers the names of the Matrix kernels running compiled; the results are the same either way."
        (returns LIST "Kernel names, () where none can be built")
        (sample "(Matrix jit!)" "every Matrix kernel's name where a JIT backend is, () elsewhere"))
      (List map (fn (_ k) (Tensor %jit (first k))) (self %kernels))
      (let ((mine (List map first (self %kernels))))
        (List filter (fn (_ name) (List includes? name mine)) (Tensor compiled))))

    ; --- the class a result takes ------------------------------------------
    (method %make (self st)
      (if (int= (List length (List ref 1 st)) 2) (new-from self (list (lit st) st))
        (Err raise (lit value) "Matrix: a matrix has two axes" (List ref 1 st))))
    (method %result-class (self st)
      (if (int= (List length (List ref 1 st)) 2) self Tensor))

    ; --- running a kernel ----------------------------------------------------
    ; Write WORDS, ((K . V) ...), into scratch S, clear the doubles the
    ; kernels keep from 16 to 20, and drive kernel NAME to the end of its
    ; run.
    (method %run (self s name words) (self %run-doubles s name words ()))

    ; As %run, with DOUBLES, ((K . FLOAT) ...), written over the cleared
    ; doubles before the run.
    (method %run-doubles (self s name words doubles)
      (let ((p (str->ptr s)) (put ((obj-ref (Tensor %fast) 6) (lit f64))))
        (def clear (fn (go b) (if (int< b 168) (do (ptr-set-word! p b 0) (go (int+ b %word-size))) ())))
        (clear 128)
        (List for-each (fn (_ w) (ptr-set-word! p (int* (first w) %word-size) (rest w))) words)
        (List for-each (fn (_ d) (put (ptr->int p) (first d) (rest d))) doubles)
        ((obj-ref (Tensor %fast) 14) name s)))

    ; In each row I of the contiguous state ST, COUNT(I) elements from
    ; column FROM(I) set to X.  Answers ST.
    (method %fill-rows! (self st count from x)
      (let ((f (Tensor %fast)) (r (first (List ref 1 st))) (c (List ref 1 (List ref 1 st))))
        (def go
          (fn (go i)
            (if (int< i r)
              (do (if (int= (count i) 0) ()
                    ((obj-ref f 9) ((obj-ref f 11) st (list (count i)) (list 1) (int+ (int* i c) (from i))) x))
                  (go (int+ i 1)))
              st)))
        (go 0)))

    ; libm's sqrt, made on first use.
    (%sqrt-cell (pair () ()))
    (method %sqrt (self)
      (if (null? (first (self %sqrt-cell)))
        (%set-first! (self %sqrt-cell) (libm-fn (lit %matrix-sqrt) "d->d" "sqrt"))
        ())
      (first (self %sqrt-cell)))

    (method %word (self s k) (ptr-ref-word (str->ptr s) (int* k %word-size)))

    ; Whether the double at 16 is zero: its bytes all are.
    (method %zero-16? (self s)
      (let ((p (str->ptr s)))
        (def go (fn (go b) (if (int< b 136) (if (int= (ptr-ref-word p b) 0) (go (int+ b %word-size)) #f) #t)))
        (go 128)))

    ; --- the lower-upper factorization -----------------------------------------
    ; (A N PIVOTS SINGULAR?) for the square state ST: A a fresh contiguous
    ; f64 copy holding L below the diagonal (its unit diagonal implied) and
    ; U on and above it, PIVOTS the row swapped into each row in turn, and
    ; SINGULAR? whether a column had no nonzero pivot.  Without PIVOTING no
    ; row is swapped, and the factoring stops with SINGULAR? #t at the first
    ; pivot that is not positive: what Cholesky needs, whose matrices never
    ; need a swap.
    (method %factor (self st pivoting)
      (let ((f (Tensor %fast)) (n (first (List ref 1 st))) (s (str-make 256)))
        (let ((a ((obj-ref f 10) st (lit f64))))
          (let ((base ((obj-ref f 13) a)) (get ((obj-ref f 5) (lit f64))))
            (def at (fn (_ i j) (int+ base (int* 8 (int+ (int* i n) j)))))
            (def go
              (fn (go k pivots singular)
                (if (int= k n) (list a n (List reverse pivots) singular)
                  (if (if pivoting #f (if (f-lt (float-of 0) (get base (int+ (int* k n) k))) #f #t))
                    (list a n (List reverse pivots) #t)
                    (do
                      (if pivoting
                        (self %run s (lit f64-pivot)
                          (list (pair 0 (at k k)) (pair 3 n) (pair 6 (int- n k)) (pair 7 0) (pair 13 0)))
                        ())
                      (let ((p (if pivoting (int+ k (self %word s 13)) k)) (zero (if pivoting (self %zero-16? s) #f)))
                        (if (int= p k) ()
                          (self %run s (lit f64-swap)
                            (list (pair 0 (at k 0)) (pair 1 (at p 0)) (pair 3 1) (pair 4 1) (pair 6 n) (pair 7 0))))
                        (if zero ()
                          (self %run s (lit f64-eliminate)
                            (list (pair 0 (at k k)) (pair 3 n) (pair 4 1) (pair 10 (int- n k)) (pair 12 (int- n k))
                                  (pair 13 1) (pair 14 0))))
                        (go (int+ k 1) (pair p pivots) (if zero #t singular))))))))
            (go 0 () #f)))))

    ; --- the Householder factorization ------------------------------------------
    ; (A M N TAUS) for the M by N state ST: A a fresh contiguous f64 copy
    ; holding R on and above the diagonal and, below it, the tail of each
    ; reflection's vector v, whose first element is 1; TAUS the factor of
    ; each reflection I - tau v v^T, 0.0 where a column needed none.  Column
    ; K's reflection sends its elements from row K to (beta 0 ... 0), beta
    ; of the opposite sign to the first, as LAPACK's dlarfg does.
    (method %householder (self st)
      (let ((f (Tensor %fast)) (m (first (List ref 1 st))) (n (List ref 1 (List ref 1 st))) (s (str-make 256)))
        (let ((a ((obj-ref f 10) st (lit f64))) (zero (float-of 0)))
          (let ((base ((obj-ref f 13) a)) (get ((obj-ref f 5) (lit f64))) (put ((obj-ref f 6) (lit f64)))
                (steps (if (int< (int- m 1) n) (int- m 1) n)))
            (def at (fn (_ i j) (int+ base (int* 8 (int+ (int* i n) j)))))
            (def go
              (fn (go k taus)
                (if (int< k steps)
                  (let ((x0 (get base (int+ (int* k n) k)))
                        (tail (Tensor %make ((obj-ref f 11) a (list (int- m (int+ k 1))) (list n) (int+ (int* (int+ k 1) n) k)))))
                    (let ((tt ((tail mul tail) sum)))
                      (if (f-lt zero tt)
                        (let ((norm ((self %sqrt) (f-add (f-mul x0 x0) tt))))
                          (let ((beta (if (f-lt x0 zero) norm (f-sub zero norm))))
                            (let ((tau (f-div (f-sub beta x0) beta)))
                              (self %run-doubles s (lit f64-scale)
                                (list (pair 0 (at (int+ k 1) k)) (pair 3 n) (pair 6 (int- m (int+ k 1))) (pair 7 0))
                                (list (pair 17 (f-div (float-of 1) (f-sub x0 beta)))))
                              (put base (int+ (int* k n) k) (float-of 1))
                              (if (int< (int+ k 1) n)
                                (self %run-doubles s (lit f64-reflect)
                                  (list (pair 0 (at k k)) (pair 1 (at k (int+ k 1))) (pair 3 n) (pair 4 n) (pair 5 1)
                                        (pair 10 (int- m k)) (pair 12 (int- n (int+ k 1))) (pair 13 0) (pair 14 0))
                                  (list (pair 17 tau)))
                                ())
                              (put base (int+ (int* k n) k) beta)
                              (go (int+ k 1) (pair tau taus)))))
                        (go (int+ k 1) (pair zero taus)))))
                  (list a m n (List reverse taus)))))
            (go 0 ())))))

    ; Refuse M unless it equals its transpose exactly.  A product's AᵀA is
    ; exact: both triangles sum the same products in the same order.
    (method %symmetric (self m who)
      (let ((d (m sub (m transpose))))
        (let ((ss ((d mul d) sum)))
          (if (f-lt (float-of 0) (if (type? ss float) ss (float-of ss)))
            (Err raise (lit value) (Str8 append "Matrix " who ": the matrix is not symmetric") ())
            ()))))

    ; --- the Jacobi eigenvalue iteration -------------------------------------
    ; (VALUES VECTORS) for the symmetric N by N state ST: VALUES a list of
    ; Floats from least to greatest, VECTORS a fresh contiguous f64 state
    ; whose column I is value I's eigenvector.  A sweep rotates every pair
    ; of rows and columns once; the sweeps stop when the sum of squares off
    ; the diagonal is at most 1e-30 of the whole, is 0, or has stopped
    ; falling, which roundoff reaches near 1e-32.
    (method %jacobi (self st)
      (let ((f (Tensor %fast)) (n (first (List ref 1 st))) (s (str-make 256)))
        (let ((a ((obj-ref f 10) st (lit f64))) (v ((obj-ref f 4) (lit f64) (list n n))))
          ((obj-ref f 9) v 0)
          ((obj-ref f 9) ((obj-ref f 11) v (list n) (list (int+ n 1)) 0) 1)
          (let ((total (self %sum-squares a)) (limit (self %ten-to-minus-30)))
            (def sweep
              (fn (go count last)
                (let ((off (self %off-squares a n)))
                  (if (if (int= count 64) #t
                        (if (f-lt (f-mul limit total) off) (if (f-lt off last) #f #t) #t))
                    ()
                    (do (self %run s (lit f64-jacobi)
                          (list (pair 0 ((obj-ref f 13) a)) (pair 1 ((obj-ref f 13) v)) (pair 3 n)
                                (pair 10 0) (pair 11 n) (pair 13 0) (pair 14 1) (pair 15 0)))
                        (go (int+ count 1) off))))))
            (if (int< n 2) () (sweep 0 (f-mul total (float-of 2))))
            (self %sort-eigen a v n)))))

    ; 1e-30, made from integers so the file needs no float literal.
    (method %ten-to-minus-30 (self)
      (let ((m (f-div (float-of 1) (float-of 1000000))))
        (f-mul m (f-mul m (f-mul m (f-mul m m))))))

    (method %sum-squares (self st)
      (let ((t (Tensor %make st)))
        (let ((x ((t mul t) sum))) (if (type? x float) x (float-of x)))))

    ; The sum of squares of the N by N state ST's elements off the diagonal.
    (method %off-squares (self st n)
      (let ((f (Tensor %fast)))
        (let ((c ((obj-ref f 10) st (lit f64))))
          ((obj-ref f 9) ((obj-ref f 11) c (list n) (list (int+ n 1)) 0) 0)
          (self %sum-squares c))))

    ; A's diagonal, least first, with V's columns swapped to match.
    (method %sort-eigen (self a v n)
      (let ((f (Tensor %fast)) (s (str-make 256)) (get ((obj-ref (Tensor %fast) 5) (lit f64))))
        (let ((vb ((obj-ref f 13) v)) (ab ((obj-ref f 13) a)))
          (def place
            (fn (go k vals acc)
              (if (null? vals) (list (List reverse acc) v)
                (let ((j (self %least-index vals)))
                  (if (int= j 0) ()
                    (self %run s (lit f64-swap)
                      (list (pair 0 (int+ vb (int* 8 k))) (pair 1 (int+ vb (int* 8 (int+ k j))))
                            (pair 3 n) (pair 4 n) (pair 6 n) (pair 7 0))))
                  (let ((vals (self %swap-first vals j)))
                    (go (int+ k 1) (rest vals) (pair (first vals) acc)))))))
          (place 0 (List map (fn (_ i) (get ab (int+ (int* i n) i))) (List range 0 n)) ()))))

    ; The index of the least of the Floats VALS, the first where two tie.
    (method %least-index (self vals)
      (def go
        (fn (go i best bi vals)
          (if (null? vals) bi
            (if (f-lt (first vals) best) (go (int+ i 1) (first vals) i (rest vals))
              (go (int+ i 1) best bi (rest vals))))))
      (go 1 (first vals) 0 (rest vals)))

    ; VALS with its first element and element J exchanged.
    (method %swap-first (self vals j)
      (if (int= j 0) vals
        (let ((x (List ref j vals)))
          (pair x (List map (fn (_ i) (if (int= i j) (first vals) (List ref i vals))) (List range 1 (List length vals)))))))

    (method %square (self st who)
      (let ((ext (List ref 1 st)))
        (if (int= (first ext) (first (rest ext))) (first ext)
          (Err raise (lit value) (Str8 append "Matrix " who ": the matrix is not square") ext))))

    ; B solved in place against the factored A: its rows put in pivot order,
    ; then forward substitution with L and back substitution with U.  B is a
    ; fresh contiguous f64 state of N rows, one axis or two.
    (method %substitute (self lu b)
      (let ((f (Tensor %fast)) (a (List ref 0 lu)) (n (List ref 1 lu)) (s (str-make 256)))
        (let ((ab ((obj-ref f 13) a)) (bb ((obj-ref f 13) b))
              (m (if (int= (List length (List ref 1 b)) 1) 1 (List ref 1 (List ref 1 b)))))
          (let ((brs (if (int= (List length (List ref 1 b)) 1) 1 m)) (bcs 1))
            (def swap-rows
              (fn (go k pivots)
                (if (null? pivots) ()
                  (do (if (int= (first pivots) k) ()
                        (self %run s (lit f64-swap)
                          (list (pair 0 (int+ bb (int* 8 (int* k brs)))) (pair 1 (int+ bb (int* 8 (int* (first pivots) brs))))
                                (pair 3 1) (pair 4 1) (pair 6 m) (pair 7 0))))
                      (go (int+ k 1) (rest pivots))))))
            (swap-rows 0 (List ref 2 lu))
            (let ((words (list (pair 0 ab) (pair 1 bb) (pair 3 n) (pair 4 1) (pair 5 brs) (pair 6 bcs)
                               (pair 11 n) (pair 12 m) (pair 13 0) (pair 14 0) (pair 15 0))))
              (self %run s (lit f64-forward) words)
              (self %run s (lit f64-backward) words))
            b))))

    ; --- the kernels, written once ---------------------------------------------
    ; Scratch words: 8 is the budget, as on every lane.  The product reads A
    ; (0), B (1) and writes O (2) by their row and column strides (3 4, 5 6,
    ; 7 9) over R (10) rows, N (11) inner and C (12) columns, counting I J K
    ; (13 14 15) and summing in the double at 16.  The pivot search finds
    ; the row at the greatest square down a column at 0 with stride 3, CNT
    ; (6) rows counted by 7, keeping the row in 13 and its square at 16.  The
    ; swap exchanges CNT elements of the rows at 0 and 1, strides 3 and 4.
    ; The elimination works under the pivot at 0, row and column strides 3
    ; and 4, over R (10) rows and C (12) columns from I 1, J 0, keeping each
    ; row's multiplier at 17.  Forward and back substitution solve the N (11)
    ; by M (12) right side at 1 (strides 5 6) against L or U at 0 (strides 3
    ; 4), summing in 16.  A sum starts again from the zero double at 18: a
    ; literal 0 is one word, and on a 4-byte word a double is two.
    (method %kernels (self)
      (list
        (list (lit f64-product)
          (lit (fn (self s)
            (match
              ((= (%mem-ref s 8) 0) 0)
              ((= (%mem-ref s 13) (%mem-ref s 10)) 1)
              ((= (%mem-ref s 14) (%mem-ref s 12))
                (do (%mem-set! s 14 0) (%mem-set! s 13 (+ (%mem-ref s 13) 1))
                    (%mem-set! s 8 (- (%mem-ref s 8) 1)) (self s)))
              ((< (%mem-ref s 15) (%mem-ref s 11))
                (do (f-set! s 16
                      (f+ (f-ref s 16)
                          (f* (f-ref (%mem-ref s 0) (+ (* (%mem-ref s 13) (%mem-ref s 3)) (* (%mem-ref s 15) (%mem-ref s 4))))
                              (f-ref (%mem-ref s 1) (+ (* (%mem-ref s 15) (%mem-ref s 5)) (* (%mem-ref s 14) (%mem-ref s 6)))))))
                    (%mem-set! s 15 (+ (%mem-ref s 15) 1))
                    (%mem-set! s 8 (- (%mem-ref s 8) 1)) (self s)))
              (#t
                (do (f-set! (%mem-ref s 2) (+ (* (%mem-ref s 13) (%mem-ref s 7)) (* (%mem-ref s 14) (%mem-ref s 9))) (f-ref s 16))
                    (f-set! s 16 (f-ref s 18)) (%mem-set! s 15 0) (%mem-set! s 14 (+ (%mem-ref s 14) 1))
                    (%mem-set! s 8 (- (%mem-ref s 8) 1)) (self s))))))
          (lit ((0 . a) (1 . b) (2 . o) (3 . 3) (4 . 1) (5 . 3) (6 . 1) (7 . 3) (9 . 1) (10 . 3) (11 . 3) (12 . 3))))
        (list (lit f64-pivot)
          (lit (fn (self s)
            (match
              ((= (%mem-ref s 8) 0) 0)
              ((= (%mem-ref s 7) (%mem-ref s 6)) 1)
              (#t
                (do (if (f< (f-ref s 16)
                            (f* (f-ref (%mem-ref s 0) (* (%mem-ref s 7) (%mem-ref s 3)))
                                (f-ref (%mem-ref s 0) (* (%mem-ref s 7) (%mem-ref s 3)))))
                      (do (f-set! s 16 (f* (f-ref (%mem-ref s 0) (* (%mem-ref s 7) (%mem-ref s 3)))
                                           (f-ref (%mem-ref s 0) (* (%mem-ref s 7) (%mem-ref s 3)))))
                          (%mem-set! s 13 (%mem-ref s 7)))
                      0)
                    (%mem-set! s 7 (+ (%mem-ref s 7) 1))
                    (%mem-set! s 8 (- (%mem-ref s 8) 1)) (self s))))))
          (lit ((0 . a) (3 . 3) (6 . 3))))
        (list (lit f64-swap)
          (lit (fn (self s)
            (match
              ((= (%mem-ref s 8) 0) 0)
              ((= (%mem-ref s 7) (%mem-ref s 6)) 1)
              (#t
                (do (f-set! s 16 (f-ref (%mem-ref s 0) (* (%mem-ref s 7) (%mem-ref s 3))))
                    (f-set! (%mem-ref s 0) (* (%mem-ref s 7) (%mem-ref s 3))
                            (f-ref (%mem-ref s 1) (* (%mem-ref s 7) (%mem-ref s 4))))
                    (f-set! (%mem-ref s 1) (* (%mem-ref s 7) (%mem-ref s 4)) (f-ref s 16))
                    (%mem-set! s 7 (+ (%mem-ref s 7) 1))
                    (%mem-set! s 8 (- (%mem-ref s 8) 1)) (self s))))))
          (lit ((0 . a) (1 . a1) (3 . 1) (4 . 1) (6 . 3))))
        (list (lit f64-eliminate)
          (lit (fn (self s)
            (match
              ((= (%mem-ref s 8) 0) 0)
              ((= (%mem-ref s 13) (%mem-ref s 10)) 1)
              ((= (%mem-ref s 14) (%mem-ref s 12))
                (do (%mem-set! s 14 0) (%mem-set! s 13 (+ (%mem-ref s 13) 1))
                    (%mem-set! s 8 (- (%mem-ref s 8) 1)) (self s)))
              ((= (%mem-ref s 14) 0)
                (do (f-set! s 17 (f/ (f-ref (%mem-ref s 0) (* (%mem-ref s 13) (%mem-ref s 3)))
                                     (f-ref (%mem-ref s 0) 0)))
                    (f-set! (%mem-ref s 0) (* (%mem-ref s 13) (%mem-ref s 3)) (f-ref s 17))
                    (%mem-set! s 14 1)
                    (%mem-set! s 8 (- (%mem-ref s 8) 1)) (self s)))
              (#t
                (do (f-set! (%mem-ref s 0) (+ (* (%mem-ref s 13) (%mem-ref s 3)) (* (%mem-ref s 14) (%mem-ref s 4)))
                      (f- (f-ref (%mem-ref s 0) (+ (* (%mem-ref s 13) (%mem-ref s 3)) (* (%mem-ref s 14) (%mem-ref s 4))))
                          (f* (f-ref s 17) (f-ref (%mem-ref s 0) (* (%mem-ref s 14) (%mem-ref s 4))))))
                    (%mem-set! s 14 (+ (%mem-ref s 14) 1))
                    (%mem-set! s 8 (- (%mem-ref s 8) 1)) (self s))))))
          (lit ((0 . a) (3 . 3) (4 . 1) (10 . 3) (12 . 3) (13 . 1))))
        (list (lit f64-forward)
          (lit (fn (self s)
            (match
              ((= (%mem-ref s 8) 0) 0)
              ((= (%mem-ref s 14) (%mem-ref s 12)) 1)
              ((= (%mem-ref s 13) (%mem-ref s 11))
                (do (%mem-set! s 13 0) (%mem-set! s 14 (+ (%mem-ref s 14) 1))
                    (%mem-set! s 8 (- (%mem-ref s 8) 1)) (self s)))
              ((< (%mem-ref s 15) (%mem-ref s 13))
                (do (f-set! s 16
                      (f+ (f-ref s 16)
                          (f* (f-ref (%mem-ref s 0) (+ (* (%mem-ref s 13) (%mem-ref s 3)) (* (%mem-ref s 15) (%mem-ref s 4))))
                              (f-ref (%mem-ref s 1) (+ (* (%mem-ref s 15) (%mem-ref s 5)) (* (%mem-ref s 14) (%mem-ref s 6)))))))
                    (%mem-set! s 15 (+ (%mem-ref s 15) 1))
                    (%mem-set! s 8 (- (%mem-ref s 8) 1)) (self s)))
              (#t
                (do (f-set! (%mem-ref s 1) (+ (* (%mem-ref s 13) (%mem-ref s 5)) (* (%mem-ref s 14) (%mem-ref s 6)))
                      (f- (f-ref (%mem-ref s 1) (+ (* (%mem-ref s 13) (%mem-ref s 5)) (* (%mem-ref s 14) (%mem-ref s 6))))
                          (f-ref s 16)))
                    (f-set! s 16 (f-ref s 18)) (%mem-set! s 15 0) (%mem-set! s 13 (+ (%mem-ref s 13) 1))
                    (%mem-set! s 8 (- (%mem-ref s 8) 1)) (self s))))))
          (lit ((0 . a) (1 . b) (3 . 3) (4 . 1) (5 . 3) (6 . 1) (11 . 3) (12 . 3))))
        ; The scale multiplies CNT (6) elements at 0, stride 3, counted by 7,
        ; by the double at 17.
        (list (lit f64-scale)
          (lit (fn (self s)
            (match
              ((= (%mem-ref s 8) 0) 0)
              ((= (%mem-ref s 7) (%mem-ref s 6)) 1)
              (#t
                (do (f-set! (%mem-ref s 0) (* (%mem-ref s 7) (%mem-ref s 3))
                      (f* (f-ref (%mem-ref s 0) (* (%mem-ref s 7) (%mem-ref s 3))) (f-ref s 17)))
                    (%mem-set! s 7 (+ (%mem-ref s 7) 1))
                    (%mem-set! s 8 (- (%mem-ref s 8) 1)) (self s))))))
          (lit ((0 . a) (3 . 1) (6 . 3))))
        ; The reflection applies I - tau v v^T, tau the double at 17, to the
        ; R (10) rows and C (12) columns at 1 (row and column strides 4 5),
        ; v the R elements at 0 (stride 3).  Column J (14) takes I (13)
        ; through 2R + 1 steps: below R, the sum of v times the column, in
        ; 16; at R, the sum times tau; above R, row I - R - 1 less the sum
        ; times v.
        (list (lit f64-reflect)
          (lit (fn (self s)
            (match
              ((= (%mem-ref s 8) 0) 0)
              ((= (%mem-ref s 14) (%mem-ref s 12)) 1)
              ((= (%mem-ref s 13) (+ (* 2 (%mem-ref s 10)) 1))
                (do (f-set! s 16 (f-ref s 18)) (%mem-set! s 13 0) (%mem-set! s 14 (+ (%mem-ref s 14) 1))
                    (%mem-set! s 8 (- (%mem-ref s 8) 1)) (self s)))
              ((< (%mem-ref s 13) (%mem-ref s 10))
                (do (f-set! s 16
                      (f+ (f-ref s 16)
                          (f* (f-ref (%mem-ref s 0) (* (%mem-ref s 13) (%mem-ref s 3)))
                              (f-ref (%mem-ref s 1) (+ (* (%mem-ref s 13) (%mem-ref s 4)) (* (%mem-ref s 14) (%mem-ref s 5)))))))
                    (%mem-set! s 13 (+ (%mem-ref s 13) 1))
                    (%mem-set! s 8 (- (%mem-ref s 8) 1)) (self s)))
              ((= (%mem-ref s 13) (%mem-ref s 10))
                (do (f-set! s 16 (f* (f-ref s 16) (f-ref s 17))) (%mem-set! s 13 (+ (%mem-ref s 13) 1))
                    (%mem-set! s 8 (- (%mem-ref s 8) 1)) (self s)))
              (#t
                (do (f-set! (%mem-ref s 1)
                      (+ (* (- (- (%mem-ref s 13) (%mem-ref s 10)) 1) (%mem-ref s 4)) (* (%mem-ref s 14) (%mem-ref s 5)))
                      (f- (f-ref (%mem-ref s 1)
                            (+ (* (- (- (%mem-ref s 13) (%mem-ref s 10)) 1) (%mem-ref s 4)) (* (%mem-ref s 14) (%mem-ref s 5))))
                          (f* (f-ref s 16) (f-ref (%mem-ref s 0) (* (- (- (%mem-ref s 13) (%mem-ref s 10)) 1) (%mem-ref s 3))))))
                    (%mem-set! s 13 (+ (%mem-ref s 13) 1))
                    (%mem-set! s 8 (- (%mem-ref s 8) 1)) (self s))))))
          (lit ((0 . a) (1 . b) (3 . 3) (4 . 3) (5 . 1) (10 . 3) (12 . 3))))
        ; A Jacobi sweep rotates each pair P < Q (13 14) of the symmetric N
        ; (11) by N matrix at 0, row stride 3, to zero its (P Q) element,
        ; and V at 1 by the same rotation.  Word 10 is 0 before a pair's
        ; rotation is made, 1 after; K (15) then runs through the columns
        ; (below N), the rows (below 2N) and V's columns (below 3N).  The
        ; rotation's c and s are at 16 and 17, theta and the temporary at
        ; 19, t at 20, as Golub and Van Loan's symmetric Schur step makes
        ; them: theta (aqq - app) / 2apq, t sign(theta) / (|theta| +
        ; sqrt(theta^2 + 1)), c 1 / sqrt(t^2 + 1), s t c.  A pair whose
        ; element is already 0 is passed.
        (list (lit f64-jacobi)
          (lit (fn (self s)
            (match
              ((= (%mem-ref s 8) 0) 0)
              ((= (%mem-ref s 13) (- (%mem-ref s 11) 1)) 1)
              ((= (%mem-ref s 14) (%mem-ref s 11))
                (do (%mem-set! s 14 (+ (%mem-ref s 13) 2)) (%mem-set! s 13 (+ (%mem-ref s 13) 1))
                    (%mem-set! s 8 (- (%mem-ref s 8) 1)) (self s)))
              ((= (%mem-ref s 10) 0)
                (do (if (f= (f-ref (%mem-ref s 0) (+ (* (%mem-ref s 13) (%mem-ref s 3)) (%mem-ref s 14))) (i->f 0))
                      (%mem-set! s 14 (+ (%mem-ref s 14) 1))
                      (do (f-set! s 19
                            (f/ (f- (f-ref (%mem-ref s 0) (+ (* (%mem-ref s 14) (%mem-ref s 3)) (%mem-ref s 14)))
                                    (f-ref (%mem-ref s 0) (+ (* (%mem-ref s 13) (%mem-ref s 3)) (%mem-ref s 13))))
                                (f+ (f-ref (%mem-ref s 0) (+ (* (%mem-ref s 13) (%mem-ref s 3)) (%mem-ref s 14)))
                                    (f-ref (%mem-ref s 0) (+ (* (%mem-ref s 13) (%mem-ref s 3)) (%mem-ref s 14))))))
                          (f-set! s 20
                            (f/ (i->f 1)
                                (f+ (if (f< (f-ref s 19) (i->f 0)) (f- (i->f 0) (f-ref s 19)) (f-ref s 19))
                                    (f-sqrt (f+ (f* (f-ref s 19) (f-ref s 19)) (i->f 1))))))
                          (if (f< (f-ref s 19) (i->f 0)) (f-set! s 20 (f- (i->f 0) (f-ref s 20))) 0)
                          (f-set! s 16 (f/ (i->f 1) (f-sqrt (f+ (f* (f-ref s 20) (f-ref s 20)) (i->f 1)))))
                          (f-set! s 17 (f* (f-ref s 20) (f-ref s 16)))
                          (%mem-set! s 10 1) (%mem-set! s 15 0)))
                    (%mem-set! s 8 (- (%mem-ref s 8) 1)) (self s)))
              ((< (%mem-ref s 15) (%mem-ref s 11))
                (do (f-set! s 19 (f-ref (%mem-ref s 0) (+ (* (%mem-ref s 15) (%mem-ref s 3)) (%mem-ref s 13))))
                    (f-set! (%mem-ref s 0) (+ (* (%mem-ref s 15) (%mem-ref s 3)) (%mem-ref s 13))
                      (f- (f* (f-ref s 16) (f-ref s 19))
                          (f* (f-ref s 17) (f-ref (%mem-ref s 0) (+ (* (%mem-ref s 15) (%mem-ref s 3)) (%mem-ref s 14))))))
                    (f-set! (%mem-ref s 0) (+ (* (%mem-ref s 15) (%mem-ref s 3)) (%mem-ref s 14))
                      (f+ (f* (f-ref s 17) (f-ref s 19))
                          (f* (f-ref s 16) (f-ref (%mem-ref s 0) (+ (* (%mem-ref s 15) (%mem-ref s 3)) (%mem-ref s 14))))))
                    (%mem-set! s 15 (+ (%mem-ref s 15) 1))
                    (%mem-set! s 8 (- (%mem-ref s 8) 1)) (self s)))
              ((< (%mem-ref s 15) (* 2 (%mem-ref s 11)))
                (do (f-set! s 19 (f-ref (%mem-ref s 0) (+ (* (%mem-ref s 13) (%mem-ref s 3)) (- (%mem-ref s 15) (%mem-ref s 11)))))
                    (f-set! (%mem-ref s 0) (+ (* (%mem-ref s 13) (%mem-ref s 3)) (- (%mem-ref s 15) (%mem-ref s 11)))
                      (f- (f* (f-ref s 16) (f-ref s 19))
                          (f* (f-ref s 17) (f-ref (%mem-ref s 0) (+ (* (%mem-ref s 14) (%mem-ref s 3)) (- (%mem-ref s 15) (%mem-ref s 11)))))))
                    (f-set! (%mem-ref s 0) (+ (* (%mem-ref s 14) (%mem-ref s 3)) (- (%mem-ref s 15) (%mem-ref s 11)))
                      (f+ (f* (f-ref s 17) (f-ref s 19))
                          (f* (f-ref s 16) (f-ref (%mem-ref s 0) (+ (* (%mem-ref s 14) (%mem-ref s 3)) (- (%mem-ref s 15) (%mem-ref s 11)))))))
                    (%mem-set! s 15 (+ (%mem-ref s 15) 1))
                    (%mem-set! s 8 (- (%mem-ref s 8) 1)) (self s)))
              ((< (%mem-ref s 15) (* 3 (%mem-ref s 11)))
                (do (f-set! s 19 (f-ref (%mem-ref s 1) (+ (* (- (%mem-ref s 15) (* 2 (%mem-ref s 11))) (%mem-ref s 3)) (%mem-ref s 13))))
                    (f-set! (%mem-ref s 1) (+ (* (- (%mem-ref s 15) (* 2 (%mem-ref s 11))) (%mem-ref s 3)) (%mem-ref s 13))
                      (f- (f* (f-ref s 16) (f-ref s 19))
                          (f* (f-ref s 17) (f-ref (%mem-ref s 1) (+ (* (- (%mem-ref s 15) (* 2 (%mem-ref s 11))) (%mem-ref s 3)) (%mem-ref s 14))))))
                    (f-set! (%mem-ref s 1) (+ (* (- (%mem-ref s 15) (* 2 (%mem-ref s 11))) (%mem-ref s 3)) (%mem-ref s 14))
                      (f+ (f* (f-ref s 17) (f-ref s 19))
                          (f* (f-ref s 16) (f-ref (%mem-ref s 1) (+ (* (- (%mem-ref s 15) (* 2 (%mem-ref s 11))) (%mem-ref s 3)) (%mem-ref s 14))))))
                    (%mem-set! s 15 (+ (%mem-ref s 15) 1))
                    (%mem-set! s 8 (- (%mem-ref s 8) 1)) (self s)))
              (#t
                (do (%mem-set! s 10 0) (%mem-set! s 15 0) (%mem-set! s 14 (+ (%mem-ref s 14) 1))
                    (%mem-set! s 8 (- (%mem-ref s 8) 1)) (self s))))))
          (lit ((0 . a) (1 . b) (3 . 3) (11 . 3) (13 . 0) (14 . 1))))
        ; Back substitution walks the rows from the last: row R is N - 1 - I,
        ; and its sum runs over the columns N - I + K for K below I.
        (list (lit f64-backward)
          (lit (fn (self s)
            (match
              ((= (%mem-ref s 8) 0) 0)
              ((= (%mem-ref s 14) (%mem-ref s 12)) 1)
              ((= (%mem-ref s 13) (%mem-ref s 11))
                (do (%mem-set! s 13 0) (%mem-set! s 14 (+ (%mem-ref s 14) 1))
                    (%mem-set! s 8 (- (%mem-ref s 8) 1)) (self s)))
              ((< (%mem-ref s 15) (%mem-ref s 13))
                (do (f-set! s 16
                      (f+ (f-ref s 16)
                          (f* (f-ref (%mem-ref s 0)
                                (+ (* (- (- (%mem-ref s 11) 1) (%mem-ref s 13)) (%mem-ref s 3))
                                   (* (+ (- (%mem-ref s 11) (%mem-ref s 13)) (%mem-ref s 15)) (%mem-ref s 4))))
                              (f-ref (%mem-ref s 1)
                                (+ (* (+ (- (%mem-ref s 11) (%mem-ref s 13)) (%mem-ref s 15)) (%mem-ref s 5))
                                   (* (%mem-ref s 14) (%mem-ref s 6)))))))
                    (%mem-set! s 15 (+ (%mem-ref s 15) 1))
                    (%mem-set! s 8 (- (%mem-ref s 8) 1)) (self s)))
              (#t
                (do (f-set! (%mem-ref s 1)
                      (+ (* (- (- (%mem-ref s 11) 1) (%mem-ref s 13)) (%mem-ref s 5)) (* (%mem-ref s 14) (%mem-ref s 6)))
                      (f/ (f- (f-ref (%mem-ref s 1)
                                (+ (* (- (- (%mem-ref s 11) 1) (%mem-ref s 13)) (%mem-ref s 5)) (* (%mem-ref s 14) (%mem-ref s 6))))
                              (f-ref s 16))
                          (f-ref (%mem-ref s 0)
                            (+ (* (- (- (%mem-ref s 11) 1) (%mem-ref s 13)) (%mem-ref s 3))
                               (* (- (- (%mem-ref s 11) 1) (%mem-ref s 13)) (%mem-ref s 4))))))
                    (f-set! s 16 (f-ref s 18)) (%mem-set! s 15 0) (%mem-set! s 13 (+ (%mem-ref s 13) 1))
                    (%mem-set! s 8 (- (%mem-ref s 8) 1)) (self s))))))
          (lit ((0 . a) (1 . b) (3 . 3) (4 . 1) (5 . 3) (6 . 1) (11 . 3) (12 . 3))))))

    (method %register-all! (self)
      (List for-each
        (fn (_ k) (Tensor %register! (first k) (List ref 1 k) (fn (_ compiled) (Matrix %agrees? (first k) compiled))))
        (self %kernels)))

    ; The compiled kernel against the pure one on the check problem: two 3 by
    ; 3 matrices A and B and an output O, made afresh for each run, with the
    ; kernel's check words (a, a1 the second row of A, b and o standing for
    ; the addresses).  A, B and O and the scratch's counters and doubles
    ; must agree to the byte.
    (method %agrees? (self name compiled)
      (let ((k (Assoc entry name (self %kernels))))
        (let ((r1 (self %check-run (word-form-pure (List ref 1 k)) (List ref 2 k)))
              (r2 (self %check-run compiled (List ref 2 k))))
          (if (List all? (fn (_ i) (int= (mem-cmp (str->ptr (List ref i r1)) (str->ptr (List ref i r2)) 72) 0)) (list 0 1 2))
            (int= (mem-cmp (int->ptr (int+ (ptr->int (str->ptr (List ref 3 r1))) 104))
                           (int->ptr (int+ (ptr->int (str->ptr (List ref 3 r2))) 104)) 40) 0)
            #f))))

    ; (A B O SCRATCH) after KERN has run over the check problem.
    (method %check-run (self kern words)
      (let ((f (Tensor %fast)))
        (let ((a ((Tensor from (lit ((4 -2 1) (3 6 -4) (2 1 8))) (lit f64)) %st))
              (b ((Tensor from (lit ((1 2 3) (0 1 -1) (5 -3 2))) (lit f64)) %st))
              (o ((obj-ref f 4) (lit f64) (list 3 3)))
              (s (str-make 256)))
          (let ((addr (fn (_ st) ((obj-ref f 13) st))))
            (let ((value
                    (fn (_ v)
                      (match
                        ((eq? v (lit a)) (addr a))
                        ((eq? v (lit a1)) (int+ (addr a) 24))
                        ((eq? v (lit b)) (addr b))
                        ((eq? v (lit o)) (addr o))
                        (#t v)))))
              (def clear (fn (go b) (if (int< b 168) (do (ptr-set-word! (str->ptr s) b 0) (go (int+ b %word-size))) ())))
              (clear 0)
              (List for-each (fn (_ w) (ptr-set-word! (str->ptr s) (int* (first w) %word-size) (value (rest w)))) words)
              (ptr-set-word! (str->ptr s) (int* 8 %word-size) 1073741823)
              (kern (ptr->int (str->ptr s)))
              (list (List ref 4 a) (List ref 4 b) (List ref 4 o) s)))))))

  ; --- the linear algebra -------------------------------------------------------
  (method product (self (param other Tensor "A Matrix, or a rank-1 Tensor, whose rows match self's columns"))
    (doc "The matrix product: element (i j) is the sum over k of self's (i k) times other's (k j). A rank-1 other is a column, and the product is then a rank-1 Tensor."
      (returns Tensor "A fresh f64 Matrix of self's rows and other's columns, or a rank-1 Tensor for a rank-1 other")
      (example "(((Matrix from '((1 2) (3 4))) product (Matrix identity 2)) ->list)" "((1.0 2.0) (3.0 4.0))")
      (example "(((Matrix from '((1 2) (3 4))) product (Tensor from '(1 1))) ->list)" "(3.0 7.0)"))
    (let ((f (Tensor %fast)) (a (self %st)) (b (other %st)))
      (let ((a (if (eq? (first a) (lit f64)) a ((obj-ref f 10) a (lit f64))))
            (b (if (eq? (first b) (lit f64)) b ((obj-ref f 10) b (lit f64))))
            (column (int= (List length (List ref 1 b)) 1)))
        (let ((r (List ref 0 (List ref 1 a))) (n (List ref 1 (List ref 1 a)))
              (bn (List ref 0 (List ref 1 b))) (c (if column 1 (List ref 1 (List ref 1 b)))))
          (if (int= n bn) ()
            (Err raise (lit value) "Matrix product: self's columns and other's rows differ" (list n bn)))
          (let ((o ((obj-ref f 4) (lit f64) (if column (list r) (list r c)))))
            (if (if (int= r 0) #t (int= c 0)) ()
              (Matrix %run (str-make 256) (lit f64-product)
                (list (pair 0 ((obj-ref f 13) a)) (pair 1 ((obj-ref f 13) b)) (pair 2 ((obj-ref f 13) o))
                      (pair 3 (List ref 0 (List ref 2 a))) (pair 4 (List ref 1 (List ref 2 a)))
                      (pair 5 (List ref 0 (List ref 2 b))) (pair 6 (if column 0 (List ref 1 (List ref 2 b))))
                      (pair 7 c) (pair 9 1) (pair 10 r) (pair 11 n) (pair 12 c)
                      (pair 13 0) (pair 14 0) (pair 15 0))))
            (self %wrap o))))))

  (method factor-lower-upper (self)
    (doc "The lower-upper factorization with partial pivoting: a lower matrix L with 1 on its diagonal, an upper matrix U and a permutation P, with P times self equal to L times U. A singular matrix factors too, and its U has a 0 on the diagonal."
      (returns LowerUpper "The factorization, which solves and answers the determinant without factoring again")
      (example "((((Matrix from '((2 1) (4 3))) factor-lower-upper) lower) ->list)" "((1.0 0.0) (0.5 1.0))"))
    (Matrix %square (self %st) "factor-lower-upper")
    (LowerUpper %of (self %st) #t))

  (method factor-cholesky (self)
    (doc "The Cholesky factorization: a lower matrix L with a positive diagonal whose product with its transpose is self. Self must be symmetric and positive definite; any other matrix is refused."
      (returns Cholesky "The factorization, which solves and answers the determinant without factoring again")
      (example "((((Matrix from '((4 2) (2 5))) factor-cholesky) lower) ->list)" "((2.0 0.0) (1.0 2.0))"))
    (Matrix %square (self %st) "factor-cholesky")
    (Matrix %symmetric self "factor-cholesky")
    (Cholesky %of (self %st)))

  (method factor-symmetric-eigen (self)
    (doc "The eigenvalues and eigenvectors of a symmetric matrix, by cyclic Jacobi rotations: values, real and from least to greatest, and vectors, whose columns are orthonormal and whose column i is value i's eigenvector. Self must be symmetric; any other matrix is refused."
      (returns SymmetricEigen "The values and vectors")
      (example "((((Matrix from '((2 1) (1 2))) factor-symmetric-eigen) values) ->list)" "(1.0 3.0)")
      (see factor-eigen))
    (Matrix %square (self %st) "factor-symmetric-eigen")
    (Matrix %symmetric self "factor-symmetric-eigen")
    (SymmetricEigen %of (self %st)))

  (method factor-orthogonal (self)
    (doc "The orthogonal-upper (QR) factorization by Householder reflections: Q, whose columns are orthonormal, and an upper R, with Q times R equal to self. With k the lesser of self's rows and columns, Q has self's rows and k columns and R has k rows and self's columns. Any matrix factors."
      (returns Orthogonal "The factorization, which solves least squares without factoring again")
      (example "((((Matrix from '((0 1) (1 1))) factor-orthogonal) upper) ->list)" "((-1.0 -1.0) (0.0 -1.0))"))
    (Orthogonal %of (self %st)))

  (method solve (self (param b Tensor "The right side: a rank-1 Tensor of self's rows, or a Matrix of them"))
    (doc "The x for which self times x is b, through the lower-upper factorization. A singular matrix is refused. To solve many right sides against one matrix, factor it once with factor-lower-upper and solve with that."
      (returns Tensor "A fresh f64 Tensor of b's extent: rank 1 for a rank-1 b, a Matrix for a Matrix")
      (example "(((Matrix from '((2 1) (1 3))) solve (Tensor from '(3 5))) ->list)" "(0.8 1.4)")
      (see factor-lower-upper))
    ((self factor-lower-upper) solve b))

  (method inverse (self)
    (doc "The matrix whose product with self is the identity. A singular matrix is refused."
      (returns Matrix "A fresh f64 Matrix")
      (example "(((Matrix from '((2 0) (0 4))) inverse) ->list)" "((0.5 0.0) (0.0 0.25))"))
    (self solve (Matrix identity (Matrix %square (self %st) "inverse"))))

  (method determinant (self)
    (doc "The determinant, from the lower-upper factorization. 0.0 for a singular matrix."
      (returns FLOAT "The determinant")
      (example "((Matrix from '((4 1) (2 3))) determinant)" "10.0")
      (see factor-lower-upper))
    ((self factor-lower-upper) determinant))

  (method diagonal (self)
    (doc "The view of the elements whose row and column are the same, as a rank-1 Tensor sharing self's bytes."
      (returns Tensor "A rank-1 view of the shorter axis's length")
      (example "(((Matrix from '((1 2) (3 4)) 'f64) diagonal) ->list)" "(1.0 4.0)"))
    (let ((st (self %st)))
      (let ((ext (List ref 1 st)) (str (List ref 2 st)))
        (self %wrap
          ((obj-ref (Tensor %fast) 11) st
            (list (if (int< (first ext) (first (rest ext))) (first ext) (first (rest ext))))
            (list (int+ (first str) (first (rest str))))
            (List ref 3 st))))))

  (method trace (self)
    (doc "The sum of the diagonal."
      (returns NUMBER "A Float for f64, an integer for i64")
      (example "((Matrix from '((1 2) (3 4)) 'f64) trace)" "5.0"))
    ((self diagonal) sum))

  (method norm (self)
    (doc "The Frobenius norm: the square root of the sum of every element squared."
      (returns FLOAT "The norm")
      (example "((Matrix from '((3 0) (0 4))) norm)" "5.0"))
    (let ((ss ((self mul self) sum)))
      ((Matrix %sqrt) (if (type? ss float) ss (float-of ss))))))

;
; LowerUpper keeps the factors in one f64 state, L below the diagonal (its
; diagonal of 1s implied) and U on and above it, with the row swapped into
; each row in turn.  Its parts are made from that state when asked.
(def-class LowerUpper ()
  (doc "The lower-upper factorization of a square Matrix with partial pivoting, from (m factor-lower-upper): a lower matrix L with 1 on its diagonal, an upper matrix U and a permutation P, with P times the matrix equal to L times U. It solves and answers the determinant from the factors, so a matrix factored once solves many right sides."
    (example "(let ((f ((Matrix from '((2 1) (4 3))) factor-lower-upper))) (list ((f lower) ->list) ((f upper) ->list) ((f permutation) ->list)))" "(((1.0 0.0) (0.5 1.0)) ((4.0 3.0) (0.0 -0.5)) ((0.0 1.0) (1.0 0.0)))")
    (example "(((Matrix from '((2 1) (4 3))) factor-lower-upper) determinant)" "2.0")
    (see lower) (see upper) (see permutation) (see solve) (see determinant))

  packed    ; the factors: a contiguous f64 state of n rows, L below the diagonal, U on and above
  n         ; the rows and columns
  pivots    ; the row swapped into each row in turn
  singular  ; #t where a column had no nonzero pivot

  (static
    (method %of (self st pivoting)
      (let ((r (Matrix %factor st pivoting)))
        (new-from self
          (list (lit packed) (List ref 0 r) (lit n) (List ref 1 r)
                (lit pivots) (List ref 2 r) (lit singular) (List ref 3 r))))))

  ; A fresh copy of the factors with, in each row I, COUNT(I) elements from
  ; column FROM(I) set to X.
  (method %triangle (self count from x)
    (Matrix %fill-rows! ((obj-ref (Tensor %fast) 10) (field (lit packed)) (lit f64)) count from x))

  (method lower (self)
    (doc "L: the multipliers below the diagonal, 1 on it and 0 above."
      (returns Matrix "A fresh f64 Matrix")
      (example "((((Matrix from '((2 1) (4 3))) factor-lower-upper) lower) ->list)" "((1.0 0.0) (0.5 1.0))"))
    (let ((n (field (lit n))) (f (Tensor %fast)))
      (let ((st (self %triangle (fn (_ i) (int- n (int+ i 1))) (fn (_ i) (int+ i 1)) 0)))
        ((obj-ref f 9) ((obj-ref f 11) st (list n) (list (int+ n 1)) 0) 1)
        (Matrix %make st))))

  (method upper (self)
    (doc "U: the factored rows on and above the diagonal, 0 below it."
      (returns Matrix "A fresh f64 Matrix")
      (example "((((Matrix from '((2 1) (4 3))) factor-lower-upper) upper) ->list)" "((4.0 3.0) (0.0 -0.5))"))
    (Matrix %make (self %triangle (fn (_ i) i) (fn (_ i) 0) 0)))

  (method permutation (self)
    (doc "P: the identity with its rows swapped as the factorization swapped the matrix's, so P times the matrix is L times U."
      (returns Matrix "A fresh f64 Matrix of 0s and 1s")
      (example "((((Matrix from '((2 1) (4 3))) factor-lower-upper) permutation) ->list)" "((0.0 1.0) (1.0 0.0))"))
    (let ((n (field (lit n))) (p (Matrix identity (field (lit n)))) (s (str-make 256)))
      (let ((base ((obj-ref (Tensor %fast) 13) (p %st))))
        (def go
          (fn (go k pivots)
            (if (null? pivots) p
              (do (if (int= (first pivots) k) ()
                    (Matrix %run s (lit f64-swap)
                      (list (pair 0 (int+ base (int* 8 (int* k n)))) (pair 1 (int+ base (int* 8 (int* (first pivots) n))))
                            (pair 3 1) (pair 4 1) (pair 6 n) (pair 7 0))))
                  (go (int+ k 1) (rest pivots))))))
        (go 0 (field (lit pivots))))))

  (method singular? (self)
    (doc "Whether the matrix is singular: a column had no nonzero pivot, and U has a 0 on its diagonal."
      (returns BOOL "#t for a singular matrix")
      (example "(((Matrix from '((1 2) (2 4))) factor-lower-upper) singular?)" "#t"))
    (field (lit singular)))

  (method solve (self (param b Tensor "The right side: a rank-1 Tensor of the matrix's rows, or a Matrix of them"))
    (doc "The x for which the factored matrix times x is b: b's rows put in P's order, then forward substitution with L and back substitution with U. A singular matrix is refused."
      (returns Tensor "A fresh f64 Tensor of b's extent: rank 1 for a rank-1 b, a Matrix for a Matrix")
      (example "((((Matrix from '((2 1) (1 3))) factor-lower-upper) solve (Tensor from '(3 5))) ->list)" "(0.8 1.4)"))
    (let ((n (field (lit n))) (bs (b %st)))
      (if (int= (first (List ref 1 bs)) n) ()
        (Err raise (lit value) "LowerUpper solve: b's rows and the matrix's differ" (List ref 1 bs)))
      (if (field (lit singular)) (Err raise (lit value) "LowerUpper solve: the matrix is singular" ()) ())
      (let ((x (Matrix %substitute
                 (list (field (lit packed)) n (field (lit pivots)) (field (lit singular)))
                 ((obj-ref (Tensor %fast) 10) bs (lit f64)))))
        ((Matrix %result-class x) %make x))))

  (method determinant (self)
    (doc "The determinant: the product of U's diagonal, negated for each row swap. 0.0 for a singular matrix."
      (returns FLOAT "The determinant")
      (example "(((Matrix from '((4 1) (2 3))) factor-lower-upper) determinant)" "10.0"))
    (if (field (lit singular)) (float-of 0)
      (let ((n (field (lit n))) (get ((obj-ref (Tensor %fast) 5) (lit f64))))
        (let ((base ((obj-ref (Tensor %fast) 13) (field (lit packed)))))
          (def go
            (fn (go k pivots acc)
              (if (int= k n) acc
                (let ((d (get base (int+ (int* k n) k))))
                  (go (int+ k 1) (rest pivots)
                    (f-mul (if (int= (first pivots) k) acc (f-mul acc (float-of -1))) d))))))
          (go 0 (field (lit pivots)) (float-of 1)))))))

;
; Cholesky keeps the matrix's LowerUpper, factored without a row swap, and
; the square roots of U's diagonal.  With D that diagonal, the matrix is
; L' D L'^T for the LowerUpper's unit lower L', so its L is L' with each
; column scaled by the square root of D's: the roots.
(def-class Cholesky ()
  (doc "The Cholesky factorization of a symmetric positive-definite Matrix, from (m factor-cholesky): a lower matrix L with a positive diagonal whose product with its transpose is the matrix. It solves and answers the determinant from the factors, so a matrix factored once solves many right sides."
    (example "(let ((f ((Matrix from '((4 2) (2 5))) factor-cholesky))) (list ((f lower) ->list) ((f upper) ->list)))" "(((2.0 0.0) (1.0 2.0)) ((2.0 1.0) (0.0 2.0)))")
    (example "(((Matrix from '((4 2) (2 5))) factor-cholesky) determinant)" "16.0")
    (see lower) (see upper) (see solve) (see determinant))

  factors   ; the matrix's LowerUpper, factored without a row swap
  roots     ; a rank-1 f64 Tensor: the square root of each of U's diagonal elements

  (static
    (method %of (self st)
      (let ((lu (LowerUpper %of st #f)))
        (if (lu singular?)
          (Err raise (lit value) "Matrix factor-cholesky: the matrix is not positive definite" ())
          ())
        (new-from self
          (list (lit factors) lu
                (lit roots) (Tensor from (List map (Matrix %sqrt) (((lu upper) diagonal) ->list)) (lit f64)))))))

  (method lower (self)
    (doc "L: lower, with a positive diagonal and 0 above it, whose product with its transpose is the matrix."
      (returns Matrix "A fresh f64 Matrix")
      (example "((((Matrix from '((4 2) (2 5))) factor-cholesky) lower) ->list)" "((2.0 0.0) (1.0 2.0))"))
    (((field (lit factors)) lower) mul (field (lit roots))))

  (method upper (self)
    (doc "The transpose of L: upper, with a positive diagonal and 0 below it."
      (returns Matrix "A fresh f64 Matrix")
      (example "((((Matrix from '((4 2) (2 5))) factor-cholesky) upper) ->list)" "((2.0 1.0) (0.0 2.0))"))
    (((self lower) transpose) copy))

  (method solve (self (param b Tensor "The right side: a rank-1 Tensor of the matrix's rows, or a Matrix of them"))
    (doc "The x for which the factored matrix times x is b."
      (returns Tensor "A fresh f64 Tensor of b's extent: rank 1 for a rank-1 b, a Matrix for a Matrix")
      (example "((((Matrix from '((4 2) (2 5))) factor-cholesky) solve (Tensor from '(6 7))) ->list)" "(1.0 1.0)"))
    ((field (lit factors)) solve b))

  (method determinant (self)
    (doc "The determinant: the product of L's diagonal, squared. Always positive."
      (returns FLOAT "The determinant")
      (example "(((Matrix from '((4 2) (2 5))) factor-cholesky) determinant)" "16.0"))
    ((field (lit factors)) determinant)))

;
; Orthogonal keeps the Householder factors in one f64 state, R on and
; above the diagonal and each reflection's vector below it, with each
; reflection's tau.  Q is never kept: it is the reflections applied to the
; identity's first k columns, and a solve applies them to b instead.
(def-class Orthogonal ()
  (doc "The orthogonal-upper (QR) factorization of a Matrix by Householder reflections, from (m factor-orthogonal): Q, whose columns are orthonormal, and an upper R, with Q times R equal to the matrix. It solves least squares, so a matrix factored once fits many right sides."
    (example "(let ((f ((Matrix from '((0 1) (1 1))) factor-orthogonal))) (list ((f orthogonal) ->list) ((f upper) ->list)))" "(((0.0 -1.0) (-1.0 0.0)) ((-1.0 -1.0) (0.0 -1.0)))")
    (see orthogonal) (see upper) (see solve))

  packed    ; the factors: a contiguous f64 state, R on and above the diagonal, each v's tail below
  m         ; the rows
  n         ; the columns
  taus      ; each reflection's tau, 0.0 for one not made

  (static
    (method %of (self st)
      (let ((r (Matrix %householder st)))
        (new-from self
          (list (lit packed) (List ref 0 r) (lit m) (List ref 1 r)
                (lit n) (List ref 2 r) (lit taus) (List ref 3 r))))))

  (method %k (self)
    (if (int< (field (lit m)) (field (lit n))) (field (lit m)) (field (lit n))))

  ; Apply the reflections numbered in ORDER to T, a fresh contiguous f64
  ; state of M rows, one axis or two.  Answers T.
  (method %reflect (self t order)
    (let ((f (Tensor %fast)) (n (field (lit n))) (m (field (lit m))) (s (str-make 256)))
      (let ((v ((obj-ref f 10) (field (lit packed)) (lit f64))))
        ((obj-ref f 9) ((obj-ref f 11) v (list (self %k)) (list (int+ n 1)) 0) 1)
        (let ((vb ((obj-ref f 13) v)) (tb ((obj-ref f 13) t))
              (c (if (int= (List length (List ref 1 t)) 1) 1 (List ref 1 (List ref 1 t)))))
          (List for-each
            (fn (_ k)
              (let ((tau (List ref k (field (lit taus)))))
                (if (f-lt (float-of 0) tau)
                  (Matrix %run-doubles s (lit f64-reflect)
                    (list (pair 0 (int+ vb (int* 8 (int+ (int* k n) k)))) (pair 1 (int+ tb (int* 8 (int* k c))))
                          (pair 3 n) (pair 4 c) (pair 5 1) (pair 10 (int- m k)) (pair 12 c) (pair 13 0) (pair 14 0))
                    (list (pair 17 tau)))
                  ())))
            order)
          t))))

  (method orthogonal (self)
    (doc "Q: the matrix's rows by k columns, k the lesser of its rows and columns, orthonormal, so Q's transpose times Q is the identity."
      (returns Matrix "A fresh f64 Matrix")
      (example "((((Matrix from '((0 1) (1 1))) factor-orthogonal) orthogonal) ->list)" "((0.0 -1.0) (-1.0 0.0))"))
    (let ((f (Tensor %fast)) (k (self %k)))
      (let ((t ((obj-ref f 4) (lit f64) (list (field (lit m)) k))))
        ((obj-ref f 9) t 0)
        ((obj-ref f 9) ((obj-ref f 11) t (list k) (list (int+ k 1)) 0) 1)
        (Matrix %make (self %reflect t (List reverse (List range 0 (List length (field (lit taus))))))))))

  (method upper (self)
    (doc "R: k rows by the matrix's columns, k the lesser of its rows and columns, 0 below the diagonal."
      (returns Matrix "A fresh f64 Matrix")
      (example "((((Matrix from '((0 1) (1 1))) factor-orthogonal) upper) ->list)" "((-1.0 -1.0) (0.0 -1.0))"))
    (let ((f (Tensor %fast)) (n (field (lit n))) (k (self %k)))
      (Matrix %make
        (Matrix %fill-rows!
          ((obj-ref f 10) ((obj-ref f 11) (field (lit packed)) (list k n) (list n 1) 0) (lit f64))
          (fn (_ i) (if (int< i n) i n)) (fn (_ i) 0) 0))))

  (method solve (self (param b Tensor "The right side: a rank-1 Tensor of the matrix's rows, or a Matrix of them"))
    (doc "The least-squares x: the one for which the matrix times x is nearest b, the exact solution for a square matrix. The matrix must have at least as many rows as columns, and independent columns; any other is refused."
      (returns Tensor "A fresh f64 Tensor of the matrix's columns: rank 1 for a rank-1 b, a Matrix of b's columns for a Matrix")
      (example "((((Matrix from '((0 1) (1 1))) factor-orthogonal) solve (Tensor from '(1 2))) ->list)" "(1.0 1.0)"))
    (let ((f (Tensor %fast)) (m (field (lit m))) (n (field (lit n))) (bs (b %st)))
      (if (int< m n) (Err raise (lit value) "Orthogonal solve: the matrix has fewer rows than columns" (list m n)) ())
      (if (int= (first (List ref 1 bs)) m) ()
        (Err raise (lit value) "Orthogonal solve: b's rows and the matrix's differ" (List ref 1 bs)))
      (let ((get ((obj-ref f 5) (lit f64))) (pb ((obj-ref f 13) (field (lit packed)))))
        (if (List any? (fn (_ i) (if (f-lt (float-of 0) (get pb (int+ (int* i n) i))) #f
                                   (if (f-lt (get pb (int+ (int* i n) i)) (float-of 0)) #f #t)))
              (List range 0 n))
          (Err raise (lit value) "Orthogonal solve: the matrix's columns are not independent" ())
          ()))
      (let ((y (self %reflect ((obj-ref f 10) bs (lit f64)) (List range 0 (List length (field (lit taus))))))
            (rank1 (int= (List length (List ref 1 bs)) 1)))
        (let ((c (if rank1 1 (List ref 1 (List ref 1 bs)))))
          (Matrix %run (str-make 256) (lit f64-backward)
            (list (pair 0 ((obj-ref f 13) (field (lit packed)))) (pair 1 ((obj-ref f 13) y))
                  (pair 3 n) (pair 4 1) (pair 5 c) (pair 6 1) (pair 11 n) (pair 12 c)
                  (pair 13 0) (pair 14 0) (pair 15 0)))
          (let ((x ((obj-ref f 10) ((obj-ref f 11) y (if rank1 (list n) (list n c)) (if rank1 (list 1) (list c 1)) 0) (lit f64))))
            ((Matrix %result-class x) %make x)))))))

;
; SymmetricEigen keeps the values as a rank-1 Tensor and the vectors as a
; Matrix, both made by the Jacobi iteration.
(def-class SymmetricEigen ()
  (doc "The eigenvalues and eigenvectors of a symmetric Matrix, from (m factor-symmetric-eigen): values, real and from least to greatest, and vectors, an orthonormal Matrix whose column i is value i's eigenvector, so the matrix is vectors times the diagonal of values times vectors' transpose."
    (example "(let ((f ((Matrix from '((2 0) (0 1))) factor-symmetric-eigen))) (list ((f values) ->list) ((f vectors) ->list)))" "((1.0 2.0) ((0.0 1.0) (1.0 0.0)))")
    (see values) (see vectors))

  values    ; a rank-1 f64 Tensor, least first
  vectors   ; a Matrix, column i value i's eigenvector

  (static
    (method %of (self st)
      (let ((r (Matrix %jacobi st)))
        (new-from self
          (list (lit values) (Tensor from (first r) (lit f64))
                (lit vectors) (Matrix %make (List ref 1 r)))))))

  (method values (self)
    (doc "The eigenvalues, real and from least to greatest."
      (returns Tensor "A rank-1 f64 Tensor")
      (example "((((Matrix from '((2 1) (1 2))) factor-symmetric-eigen) values) ->list)" "(1.0 3.0)"))
    (field (lit values)))

  (method vectors (self)
    (doc "The eigenvectors: an orthonormal Matrix whose column i is value i's eigenvector. An eigenvector's sign is not fixed: its negation is one too."
      (returns Matrix "An f64 Matrix")
      (example "((((Matrix from '((2 0) (0 1))) factor-symmetric-eigen) vectors) ->list)" "((0.0 1.0) (1.0 0.0))"))
    (field (lit vectors))))

(Matrix %register-all!)

(doc (provide x/num/matrix Matrix LowerUpper Cholesky Orthogonal SymmetricEigen)
  "Matrix: a Tensor of rank 2 with the linear algebra -- the matrix product, solve, inverse, determinant, trace, diagonal and norm -- run in kernels that compile once they have run long enough; and its factorizations, LowerUpper, Cholesky, Orthogonal and SymmetricEigen."
  (example "((Matrix from '((2 1) (1 3))) determinant)" "5.0"))
