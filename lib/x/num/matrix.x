; matrix.x -- Matrix: a Tensor of rank 2, with the linear algebra.
;
; A Matrix is a Tensor whose extent has two axes, rows then columns, and it
; is everything a Tensor is: the views, the element-wise arithmetic and the
; reductions answer a Matrix while their result keeps two axes, and a Tensor
; once it does not (a diagonal, a reshape to one axis).  On top it has the
; matrix product, solve, inverse and determinant, trace, diagonal and
; norm, and the covariance and correlation of its columns, each column a
; variable and each row an observation.  Every result of the linear
; algebra is f64.
;
; A factorization is a value of its own: (m factor-lower-upper) answers a
; LowerUpper, which keeps the factors and answers its parts, solves and the
; determinant from them, so a matrix factored once solves many right sides.
; (m factor-lower-transpose) answers a LowerTranspose for a symmetric positive-definite
; m, built on a LowerUpper that never swaps a row.  (m factor-orthogonal)
; answers an Orthogonal, the factorization by Householder reflections,
; which solves least squares.  (m factor-symmetric-eigen) answers a
; SymmetricEigen, the eigenvalues and orthonormal eigenvectors of a
; symmetric m, by cyclic Jacobi rotations.  (m factor-eigen) answers an
; Eigen for any square m, its values and vectors complex: m is reduced to
; Hessenberg form and then to real Schur form by Francis's double-shift QR
; steps, that form is made complex triangular, and the vectors are solved
; on the triangle.  (m factor-singular) answers a Singular for any m, its
; singular values and the left and right vectors, by one-sided Jacobi
; rotations of m's columns; its rank counts the values above a tolerance.
;
; The work is done by eleven kernels, word forms (x/tool/word-form) that
; loop over two or three axes inside one run, so an operation costs a few
; runs however large its matrices: the product; LU factorization with
; partial pivoting, a pivot search down a column, a row swap and the
; elimination below a pivot, with forward and back substitution for solve;
; a scale down a column and a reflection of a block of columns for the
; Householder factorization, the Hessenberg reduction and the QR steps;
; a sweep of Jacobi rotations, and a sweep of them on a matrix's columns
; alone; and back substitution on a complex triangular matrix for its
; eigenvectors.
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
(import x/num/float float float-of f-add f-sub f-mul f-div f-lt f-eq libm-fn)
(import x/tool/word-form word-form-pure)
(import x/core/doors int+ int- int* int/ int< int= mem-cmp obj-ref ptr->int int->ptr
  ptr-ref-word ptr-set-word! str->ptr str-make type?)

(def-class Matrix (extends Tensor)
  (doc "A Tensor of rank 2, rows then columns, with the linear algebra: the matrix product, solve, inverse, determinant, trace, diagonal and norm, and the covariance and correlation of its columns. It is every other thing a Tensor is, and an operation on it answers a Matrix while the result keeps two axes."
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
    ; pivot that is not positive: what LowerTranspose needs, whose matrices never
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

    ; --- the eigenvalues of any square matrix ----------------------------------
    ; Apply I - tau v v^T, v the R doubles at V with stride VS, to COUNT
    ; vectors of R doubles at C, each ALONG apart within and ACROSS apart
    ; from the next.
    (method %reflect-block (self s v vs r tau c along across count)
      (self %run-doubles s (lit f64-reflect)
        (list (pair 0 v) (pair 1 c) (pair 3 vs) (pair 4 along) (pair 5 across)
              (pair 10 r) (pair 12 count) (pair 13 0) (pair 14 0))
        (list (pair 17 tau))))

    ; (H Z) for the N by N state ST: H a fresh contiguous f64 copy reduced
    ; to upper Hessenberg form, 0 below the first subdiagonal, by a
    ; Householder reflection from both sides for each column, and Z the
    ; product of the reflections, so ST is Z H Z^T.  Column K's reflection
    ; is made as the Householder factorization makes one, from row K + 1.
    (method %hessenberg (self st n)
      (let ((f (Tensor %fast)) (s (str-make 256)) (zero (float-of 0)))
        (let ((h ((obj-ref f 10) st (lit f64))) (z ((Matrix identity n) %st)))
          (let ((hb ((obj-ref f 13) h)) (zb ((obj-ref f 13) z))
                (get ((obj-ref f 5) (lit f64))) (put ((obj-ref f 6) (lit f64))))
            (def at (fn (_ b i j) (int+ b (int* 8 (int+ (int* i n) j)))))
            (def go
              (fn (go k)
                (if (int< k (int- n 2))
                  (let ((x0 (get hb (int+ (int* (int+ k 1) n) k)))
                        (tail ((obj-ref f 11) h (list (int- n (int+ k 2))) (list n) (int+ (int* (int+ k 2) n) k)))
                        (r (int- n (int+ k 1))))
                    (let ((tt (self %sum-squares tail)))
                      (if (f-lt zero tt)
                        (let ((norm ((self %sqrt) (f-add (f-mul x0 x0) tt))))
                          (let ((beta (if (f-lt x0 zero) norm (f-sub zero norm))))
                            (let ((tau (f-div (f-sub beta x0) beta)) (v (at hb (int+ k 1) k)))
                              (self %run-doubles s (lit f64-scale)
                                (list (pair 0 (at hb (int+ k 2) k)) (pair 3 n) (pair 6 (int- n (int+ k 2))) (pair 7 0))
                                (list (pair 17 (f-div (float-of 1) (f-sub x0 beta)))))
                              (put hb (int+ (int* (int+ k 1) n) k) (float-of 1))
                              (self %reflect-block s v n r tau (at hb (int+ k 1) (int+ k 1)) n 1 r)
                              (self %reflect-block s v n r tau (at hb 0 (int+ k 1)) 1 n n)
                              (self %reflect-block s v n r tau (at zb 0 (int+ k 1)) 1 n n)
                              (put hb (int+ (int* (int+ k 1) n) k) beta)
                              ((obj-ref f 9) tail 0)
                              (go (int+ k 1)))))
                        (go (int+ k 1)))))
                  (list h z))))
            (go 0)))))

    ; (WR WI), the real and imaginary parts of the eigenvalues, for the N
    ; by N upper Hessenberg state H, which is left in real Schur form: upper
    ; triangular but for a 2 by 2 block on the diagonal for each conjugate
    ; pair, whose subdiagonal element is the one left below the diagonal
    ; (the elements further below hold leftovers of the steps).  Z takes
    ; every reflection from the right.  The steps are EISPACK's hqr2:
    ; Francis's double-shift QR steps on the block above the last row not
    ; yet split off, a row splitting off with its eigenvalue once its
    ; subdiagonal element is negligible beside its neighbours on the
    ; diagonal, two rows once the element above that is, an exceptional
    ; shift after 10 and 20 steps without one, and a refusal after 30 N
    ; steps in all.  Two rows with real eigenvalues are reflected to
    ; triangular form; a conjugate pair keeps its block, the positive
    ; imaginary part first.
    (method %francis (self h z n)
      (let ((f (Tensor %fast)) (s (str-make 256)) (zero (float-of 0)) (one (float-of 1)))
        (let ((hb ((obj-ref f 13) h)) (zb ((obj-ref f 13) z)) (v ((obj-ref f 4) (lit f64) (list 3)))
              (get ((obj-ref f 5) (lit f64))) (put ((obj-ref f 6) (lit f64)))
              (norm ((self %sqrt) (self %sum-squares h)))
              (half (f-div one (float-of 2))) (three-quarters (f-div (float-of 3) (float-of 4)))
              (seven-sixteenths (f-div (float-of 7) (float-of 16))))
          (let ((vb ((obj-ref f 13) v)))
            (def at (fn (_ i j) (get hb (int+ (int* i n) j))))
            (def at! (fn (_ i j x) (put hb (int+ (int* i n) j) x)))
            (def absolute (fn (_ x) (if (f-lt x zero) (f-sub zero x) x)))
            (def signed (fn (_ a b) (if (f-lt b zero) (f-sub zero (absolute a)) (absolute a))))
            ; I - tau v v^T, v (1 Q R) cut to LEN, on rows K up from column
            ; K, on columns K up to row EN or K + 3, and on Z's columns K up.
            (def reflect
              (fn (_ k len tau q r en)
                (put vb 0 one) (put vb 1 q) (put vb 2 r)
                (self %reflect-block s vb 1 len tau (int+ hb (int* 8 (int+ (int* k n) k))) n 1 (int- n k))
                (self %reflect-block s vb 1 len tau (int+ hb (int* 8 k)) 1 n
                  (int+ (if (int< en (int+ k 3)) en (int+ k 3)) 1))
                (self %reflect-block s vb 1 len tau (int+ zb (int* 8 k)) 1 n n)))
            ; The first row of the block ending at row L: the row below the
            ; last negligible subdiagonal element above L, which is set to
            ; 0, else 0.
            (def split
              (fn (go l)
                (if (int= l 0) 0
                  (let ((d (f-add (absolute (at (int- l 1) (int- l 1))) (absolute (at l l)))))
                    (let ((d (if (f-eq d zero) norm d)))
                      (if (f-eq (f-add d (absolute (at l (int- l 1)))) d)
                        (do (at! l (int- l 1) zero) l)
                        (go (int- l 1))))))))
            ; (M P Q R): the row M at or below L where the step starts, the
            ; first two subdiagonal elements below it negligible, with the
            ; first column of the shifted product there, scaled.
            (def start
              (fn (go m l x y w)
                (let ((zz (at m m)))
                  (let ((r (f-sub x zz)) (d (f-sub y zz)))
                    (let ((p (f-add (f-div (f-sub (f-mul r d) w) (at (int+ m 1) m)) (at m (int+ m 1))))
                          (q (f-sub (f-sub (f-sub (at (int+ m 1) (int+ m 1)) zz) r) d))
                          (r (at (int+ m 2) (int+ m 1))))
                      (let ((d (f-add (f-add (absolute p) (absolute q)) (absolute r))))
                        (let ((p (f-div p d)) (q (f-div q d)) (r (f-div r d)))
                          (if (int= m l) (list m p q r)
                            (let ((t1 (f-mul (absolute p)
                                        (f-add (f-add (absolute (at (int- m 1) (int- m 1))) (absolute zz))
                                               (absolute (at (int+ m 1) (int+ m 1)))))))
                              (if (f-eq (f-add t1 (f-mul (absolute (at m (int- m 1))) (f-add (absolute q) (absolute r)))) t1)
                                (list m p q r)
                                (go (int- m 1) l x y w)))))))))))
            ; The bulge chased from row M to the end of the block at EN.
            (def chase
              (fn (go k m l en p q r)
                (if (int< (int- en 1) k) ()
                  (let ((final (int= k (int- en 1))))
                    (let ((pqr (if (int= k m) (list p q r)
                                 (let ((p (at k (int- k 1))) (q (at (int+ k 1) (int- k 1)))
                                       (r (if final zero (at (int+ k 2) (int- k 1)))))
                                   (let ((x (f-add (f-add (absolute p) (absolute q)) (absolute r))))
                                     (if (f-eq x zero) ()
                                       (list (f-div p x) (f-div q x) (f-div r x) x)))))))
                      (if (null? pqr) (go (int+ k 1) m l en zero zero zero)
                        (let ((p (List ref 0 pqr)) (q (List ref 1 pqr)) (r (List ref 2 pqr)))
                          (let ((d (signed ((self %sqrt) (f-add (f-add (f-mul p p) (f-mul q q)) (f-mul r r))) p)))
                            (if (int= k m)
                              (if (int= l m) () (at! k (int- k 1) (f-sub zero (at k (int- k 1)))))
                              (at! k (int- k 1) (f-sub zero (f-mul d (List ref 3 pqr)))))
                            (let ((p (f-add p d)))
                              (reflect k (if final 2 3) (f-div p d) (f-div q p) (f-div r p) en)
                              (go (int+ k 1) m l en zero zero zero))))))))))
            ; One double-shift step on the block from row L to EN, shifts
            ; given by X, Y and W.
            (def step
              (fn (_ en l x y w)
                (let ((b (start (int- en 2) l x y w)))
                  (let ((m (first b)))
                    (List for-each
                      (fn (_ i) (do (at! i (int- i 2) zero) (if (int= i (int+ m 2)) () (at! i (int- i 3) zero))))
                      (List range (int+ m 2) (int+ en 1)))
                    (chase m m l en (List ref 1 b) (List ref 2 b) (List ref 3 b))))))
            ; The two eigenvalues of rows EN - 1 and EN, (WR1 WR2 WI1 WI2),
            ; with a real pair's rows reflected to triangular form.  T is the
            ; shift taken from the diagonal so far.
            (def two
              (fn (_ en x y w t)
                (let ((na (int- en 1)) (p (f-mul (f-sub y x) half)))
                  (let ((q (f-add (f-mul p p) w)) (x (f-add x t)))
                    (let ((zz ((self %sqrt) (absolute q))))
                      (at! en en x)
                      (at! na na (f-add y t))
                      (if (f-lt q zero)
                        (list (f-add x p) (f-add x p) zz (f-sub zero zz))
                        (let ((zz (f-add p (signed zz p))) (c (at en na)))
                          (let ((size ((self %sqrt) (f-add (f-mul zz zz) (f-mul c c)))))
                            (let ((beta (if (f-lt zz zero) size (f-sub zero size))))
                              (reflect na 2 (f-div (f-sub beta zz) beta) (f-div c (f-sub zz beta)) zero en)
                              (at! en na zero)
                              (list (f-add x zz) (if (f-eq zz zero) (f-add x zz) (f-sub x (f-div w zz))) zero zero))))))))))
            (def roots
              (fn (go en its t steps wr wi)
                (if (int< en 0) (list wr wi)
                  (let ((l (split en)) (x (at en en)))
                    (if (int= l en)
                      (do (at! en en (f-add x t))
                          (go (int- en 1) 0 t steps (pair (f-add x t) wr) (pair zero wi)))
                      (let ((na (int- en 1)))
                        (let ((y (at na na)) (w (f-mul (at en na) (at na en))))
                          (if (int= l na)
                            (let ((e (two en x y w t)))
                              (go (int- en 2) 0 t steps
                                (pair (List ref 0 e) (pair (List ref 1 e) wr))
                                (pair (List ref 2 e) (pair (List ref 3 e) wi))))
                            (if (int= steps 0)
                              (Err raise (lit value) "Matrix factor-eigen: the QR steps did not converge" ())
                              (let ((odd (if (int= its 10) #t (int= its 20))))
                                (if odd (List for-each (fn (_ i) (at! i i (f-sub (at i i) x))) (List range 0 (int+ en 1))) ())
                                (if odd
                                  (let ((d (f-add (absolute (at en na)) (absolute (at na (int- na 1))))))
                                    (step en l (f-mul three-quarters d) (f-mul three-quarters d)
                                      (f-sub zero (f-mul seven-sixteenths (f-mul d d)))))
                                  (step en l x y w))
                                (go en (int+ its 1) (if odd (f-add t x) t) (int- steps 1) wr wi)))))))))))
            (roots (int- n 1) 0 zero (int* 30 n) () ())))))

    ; U and W, c128 copies of the real Schur form T and of Z, made complex
    ; triangular: each 2 by 2 block of T, a conjugate pair's, is rotated by
    ; G = (c* s; -s c), U's rows by G and its and W's columns by G^H, with c
    ; and s from the pair's eigenvalue whose imaginary part is positive, so
    ; that eigenvalue comes first on U's diagonal.  The matrix is then W U
    ; W^H.
    (method %complex-schur (self t u w n wr wi)
      (let ((f (Tensor %fast)) (zero (float-of 0)))
        (let ((tb ((obj-ref f 13) t)) (ub ((obj-ref f 13) u)) (wb ((obj-ref f 13) w))
              (get ((obj-ref f 5) (lit f64))) (put ((obj-ref f 6) (lit f64))))
          ; Over COUNT pairs of elements at double indexes I0 and I1 of
          ; BASE, STEP doubles apart, (x y) becomes (a x + b y, c x + d y);
          ; a, b, c and d are complex, each its real and imaginary parts.
          (def mix
            (fn (go base i0 i1 count step ar ai br bi cr ci dr di)
              (if (int< 0 count)
                (let ((xr (get base i0)) (xi (get base (int+ i0 1))) (yr (get base i1)) (yi (get base (int+ i1 1))))
                  (put base i0 (f-sub (f-add (f-mul ar xr) (f-mul br yr)) (f-add (f-mul ai xi) (f-mul bi yi))))
                  (put base (int+ i0 1) (f-add (f-add (f-mul ar xi) (f-mul ai xr)) (f-add (f-mul br yi) (f-mul bi yr))))
                  (put base i1 (f-sub (f-add (f-mul cr xr) (f-mul dr yr)) (f-add (f-mul ci xi) (f-mul di yi))))
                  (put base (int+ i1 1) (f-add (f-add (f-mul cr xi) (f-mul ci xr)) (f-add (f-mul dr yi) (f-mul di yr))))
                  (go base (int+ i0 step) (int+ i1 step) (int- count 1) step ar ai br bi cr ci dr di))
                ())))
          (def go
            (fn (go m)
              (if (int< 0 m)
                (let ((sub (get tb (int+ (int* m n) (int- m 1)))))
                  (if (f-eq sub zero) (go (int- m 1))
                    (let ((mr (f-sub (List ref (int- m 1) wr) (get tb (int+ (int* m n) m)))) (mi (List ref (int- m 1) wi)))
                      (let ((r ((self %sqrt) (f-add (f-add (f-mul mr mr) (f-mul mi mi)) (f-mul sub sub)))))
                        (let ((cr (f-div mr r)) (ci (f-div mi r)) (sr (f-div sub r)))
                          (let ((nci (f-sub zero ci)) (nsr (f-sub zero sr)))
                            (mix ub (int* 2 (int+ (int* (int- m 1) n) (int- m 1))) (int* 2 (int+ (int* m n) (int- m 1)))
                              (int+ (int- n m) 1) 2 cr nci sr zero nsr zero cr ci)
                            (mix ub (int* 2 (int- m 1)) (int* 2 m) (int+ m 1) (int* 2 n) cr ci sr zero nsr zero cr nci)
                            (mix wb (int* 2 (int- m 1)) (int* 2 m) n (int* 2 n) cr ci sr zero nsr zero cr nci)
                            (put ub (int* 2 (int+ (int* m n) (int- m 1))) zero)
                            (put ub (int+ (int* 2 (int+ (int* m n) (int- m 1))) 1) zero)
                            (go (int- m 2))))))))
                ())))
          (go (int- n 1)))))

    ; The eigenvectors, a c128 Matrix: W Y, with W the unitary c128 state
    ; and Y the c128 state of the triangle's eigenvectors, each column made
    ; unit length with its greatest element real and positive.  Column K
    ; of a value whose imaginary part, in WI, is negative is the conjugate
    ; of the column before, its pair's; one whose imaginary part is 0 is
    ; made real.
    (method %eigenvectors (self w y n wi)
      (let ((f (Tensor %fast)) (zero (float-of 0)))
        (let ((wr (Matrix %make (Tensor %part w 0))) (wm (Matrix %make (Tensor %part w 1)))
              (yr (Matrix %make (Tensor %part y 0))) (ym (Matrix %make (Tensor %part y 1))))
          (let ((xr (((wr product yr) sub (wm product ym)) %st)) (xi (((wr product ym) add (wm product yr)) %st)))
            (let ((rb ((obj-ref f 13) xr)) (ib ((obj-ref f 13) xi))
                  (get ((obj-ref f 5) (lit f64))) (put ((obj-ref f 6) (lit f64))))
              (def at (fn (_ i k) (int+ (int* i n) k)))
              (def go
                (fn (go k wi)
                  (if (null? wi) ()
                    (do (if (f-lt (first wi) zero)
                          (List for-each
                            (fn (_ i) (do (put rb (at i k) (get rb (at i (int- k 1))))
                                          (put ib (at i k) (f-sub zero (get ib (at i (int- k 1)))))))
                            (List range 0 n))
                          (self %unit-column rb ib n k (f-eq (first wi) zero)))
                        (go (int+ k 1) (rest wi))))))
              (go 0 wi)
              (Matrix complex (Matrix %make xr) (Matrix %make xi)))))))

    ; Column K of the N by N contiguous f64 states at RB and IB, the real
    ; and imaginary parts, scaled to unit length and turned so its first
    ; greatest element is real and positive; with REAL, its imaginary parts
    ; set to 0.  Adding 0.0 makes a -0.0 0.0.
    (method %unit-column (self rb ib n k real)
      (let ((zero (float-of 0)) (get ((obj-ref (Tensor %fast) 5) (lit f64))) (put ((obj-ref (Tensor %fast) 6) (lit f64))))
        (def at (fn (_ i) (int+ (int* i n) k)))
        (let ((squares (List map (fn (_ i) (let ((a (get rb (at i))) (b (get ib (at i)))) (f-add (f-mul a a) (f-mul b b))))
                         (List range 0 n))))
          (def total (fn (go xs acc) (if (null? xs) acc (go (rest xs) (f-add acc (first xs))))))
          (let ((j (self %least-index (List map (fn (_ x) (f-sub zero x)) squares))))
            (let ((size ((self %sqrt) (f-mul (total squares zero) (List ref j squares)))))
              (let ((a (f-div (get rb (at j)) size)) (b (f-div (f-sub zero (get ib (at j))) size)))
                (List for-each
                  (fn (_ i)
                    (let ((xr (get rb (at i))) (xi (get ib (at i))))
                      (put rb (at i) (f-add (f-sub (f-mul xr a) (f-mul xi b)) zero))
                      (put ib (at i) (if (if real #t (int= i j)) zero (f-add (f-add (f-mul xr b) (f-mul xi a)) zero)))))
                  (List range 0 n))))))))

    ; (VALUES VECTORS) for the N by N state ST: VALUES a rank-1 c128
    ; Tensor in the order the QR steps leave them on the diagonal, VECTORS
    ; a c128 Matrix whose column I is value I's eigenvector.  The vectors
    ; are solved on the complex triangle U, a value equal to one above it
    ; on U's diagonal taking a difference of 2^-52 of U's size in place of
    ; 0.
    (method %eigen (self st)
      (let ((f (Tensor %fast)) (n (first (List ref 1 st))) (zero (float-of 0)))
        (let ((hz (self %hessenberg st n)))
          (let ((t (first hz)) (z (List ref 1 hz)))
            (let ((w (self %francis t z n)))
              (self %fill-rows! t (fn (_ i) (if (int< i 2) 0 (int- i 1))) (fn (_ i) 0) 0)
              (let ((u ((obj-ref f 10) t (lit c128))) (v ((obj-ref f 10) z (lit c128)))
                    (y ((obj-ref f 10) ((Matrix identity n) %st) (lit c128)))
                    (e (f-div (float-of 1) (float-of 67108864)))
                    (size ((self %sqrt) (self %sum-squares t))))
                (self %complex-schur t u v n (first w) (List ref 1 w))
                (if (int< n 2) ()
                  (self %run-doubles (str-make 256) (lit c128-eigenvectors)
                    (list (pair 0 ((obj-ref f 13) u)) (pair 1 ((obj-ref f 13) y)) (pair 11 n)
                          (pair 13 0) (pair 14 0) (pair 15 0))
                    (list (pair 22 (f-mul (f-mul e e) (if (f-lt zero size) size (float-of 1)))))))
                (list (Tensor complex (Tensor from (first w) (lit f64)) (Tensor from (List ref 1 w) (lit f64)))
                      (self %eigenvectors v y n (List ref 1 w)))))))))

    ; --- the singular value decomposition ------------------------------------
    ; (LEFT VALUES RIGHT) for the state ST of R rows and C columns: VALUES
    ; a list of K Floats from greatest to least, K the lesser of R and C,
    ; LEFT a fresh f64 state of R rows and K columns and RIGHT one of C rows
    ; and K columns, both with orthonormal columns, and ST is LEFT times the
    ; diagonal of VALUES times RIGHT's transpose.  A matrix wider than it is
    ; tall is factored through its transpose, which exchanges LEFT and
    ; RIGHT.
    (method %singular (self st)
      (let ((rows (first (List ref 1 st))) (cols (List ref 1 (List ref 1 st))))
        (if (int< rows cols)
          (let ((r (self %singular-tall (((Matrix %make st) transpose) %st))))
            (list (List ref 2 r) (List ref 1 r) (List ref 0 r)))
          (self %singular-tall st))))

    ; %singular for ST of R rows and C columns, R at least C.  The sweeps
    ; rotate pairs of A's columns, and V's by the same rotation, until no
    ; pair is rotated, a pair being passed once its product is at most R
    ; 2^-52 of the product of its lengths; 64 sweeps bound them.  Column J
    ; of A is then value J times left column J.
    (method %singular-tall (self st)
      (let ((f (Tensor %fast)) (s (str-make 256))
            (r (first (List ref 1 st))) (c (List ref 1 (List ref 1 st))))
        (let ((a ((obj-ref f 10) st (lit f64))) (v ((Matrix identity c) %st))
              (e (f-div (float-of 1) (float-of 67108864))))
          (let ((ab ((obj-ref f 13) a)) (vb ((obj-ref f 13) v)) (tol (f-mul (float-of r) (f-mul e e))))
            (def sweep
              (fn (go count)
                (if (int= count 64) ()
                  (do (self %run-doubles s (lit f64-column-jacobi)
                        (list (pair 0 ab) (pair 1 vb) (pair 3 c) (pair 4 c) (pair 9 0) (pair 10 0)
                              (pair 11 c) (pair 12 r) (pair 13 0) (pair 14 1) (pair 15 0))
                        (list (pair 22 tol)))
                      (if (int= (self %word s 9) 0) () (go (int+ count 1)))))))
            (if (int< c 2) () (sweep 0))
            (let ((vals (self %sort-singular a v r c)))
              (self %left-columns a r c vals (f-mul (f-mul (float-of r) (f-mul e e)) (first vals)))
              (list a vals v))))))

    ; The lengths of A's C columns, greatest first, with A's and V's
    ; columns swapped to match.  A has R rows, V has C.
    (method %sort-singular (self a v r c)
      (let ((f (Tensor %fast)) (s (str-make 256)) (zero (float-of 0)) (get ((obj-ref (Tensor %fast) 5) (lit f64))))
        (let ((ab ((obj-ref f 13) a)) (vb ((obj-ref f 13) v)))
          (def column-length
            (fn (_ j)
              (def go (fn (go i acc) (if (int= i r) acc (let ((x (get ab (int+ (int* i c) j)))) (go (int+ i 1) (f-add acc (f-mul x x)))))))
              ((self %sqrt) (go 0 zero))))
          (def swap
            (fn (_ base k j count)
              (self %run s (lit f64-swap)
                (list (pair 0 (int+ base (int* 8 k))) (pair 1 (int+ base (int* 8 (int+ k j))))
                      (pair 3 c) (pair 4 c) (pair 6 count) (pair 7 0)))))
          (def place
            (fn (go k vals acc)
              (if (null? vals) (List reverse acc)
                (let ((j (self %least-index (List map (fn (_ x) (f-sub zero x)) vals))))
                  (if (int= j 0) () (do (swap ab k j r) (swap vb k j c)))
                  (let ((vals (self %swap-first vals j)))
                    (go (int+ k 1) (rest vals) (pair (first vals) acc)))))))
          (place 0 (List map column-length (List range 0 c)) ()))))

    ; A's C columns made the left vectors: column J divided by value J, or,
    ; where value J is at most CUT, the unit vector most nearly orthogonal
    ; to the columns before it, made so by subtracting its projection on
    ; them twice.  A has R rows.
    (method %left-columns (self a r c vals cut)
      (let ((zero (float-of 0)) (one (float-of 1)) (ab ((obj-ref (Tensor %fast) 13) a))
            (get ((obj-ref (Tensor %fast) 5) (lit f64))) (put ((obj-ref (Tensor %fast) 6) (lit f64))))
        (def at (fn (_ i j) (int+ (int* i c) j)))
        (def dot
          (fn (_ x j)
            (def go (fn (go i xs acc) (if (null? xs) acc (go (int+ i 1) (rest xs) (f-add acc (f-mul (first xs) (get ab (at i j))))))))
            (go 0 x zero)))
        (def project
          (fn (_ x j)
            (def go
              (fn (go l x)
                (if (int= l j) x
                  (let ((d (dot x l)))
                    (go (int+ l 1) (List map (fn (_ i) (f-sub (List ref i x) (f-mul d (get ab (at i l))))) (List range 0 r)))))))
            (go 0 x)))
        (def squares (fn (_ x) (List fold (fn (_ acc y) (f-add acc (f-mul y y))) zero x)))
        (def complete
          (fn (_ j)
            (let ((xs (List map (fn (_ k) (project (project (List map (fn (_ i) (if (int= i k) one zero)) (List range 0 r)) j) j))
                        (List range 0 r))))
              (let ((x (List ref (self %least-index (List map (fn (_ x) (f-sub zero (squares x))) xs)) xs)))
                (let ((size ((self %sqrt) (squares x))))
                  (List for-each (fn (_ i) (put ab (at i j) (f-add (f-div (List ref i x) size) zero))) (List range 0 r)))))))
        (def go
          (fn (go j vals)
            (if (null? vals) ()
              (do (if (f-lt cut (first vals))
                    (List for-each (fn (_ i) (put ab (at i j) (f-add (f-div (get ab (at i j)) (first vals)) zero))) (List range 0 r))
                    (complete j))
                  (go (int+ j 1) (rest vals))))))
        (go 0 vals)))

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
          (lit ((0 . a) (1 . b) (3 . 3) (4 . 1) (5 . 3) (6 . 1) (11 . 3) (12 . 3))))
        ; Back substitution for the eigenvectors of the complex upper
        ; triangle U, N (11) by N c128 at 0: column K (13) of Y, c128 at 1
        ; and the identity to start, takes for each row I above K, from
        ; the last, minus the sum over J (15) from I + 1 to K of U (I J)
        ; times Y (J K), in 16 and 17, over U (I I) less U (K K), in 20
        ; and 21, divided by Smith's method with the ratio and divisor at
        ; 18 and 19.  Word 14 is I + 1, 0 when a column is done; a divisor
        ; of 0 takes the small double at 22.  Element (I J) is the doubles
        ; 2(I N + J) and the one after, its real and imaginary parts.
        (list (lit c128-eigenvectors)
          (lit (fn (self s)
            (match
              ((= (%mem-ref s 8) 0) 0)
              ((= (%mem-ref s 13) (%mem-ref s 11)) 1)
              ((= (%mem-ref s 14) 0)
                (do (%mem-set! s 13 (+ (%mem-ref s 13) 1)) (%mem-set! s 14 (%mem-ref s 13)) (%mem-set! s 15 (%mem-ref s 13))
                    (%mem-set! s 8 (- (%mem-ref s 8) 1)) (self s)))
              ((< (%mem-ref s 15) (+ (%mem-ref s 13) 1))
                (do (f-set! s 16
                      (f+ (f-ref s 16) (f- (f* (f-ref (%mem-ref s 0) (* 2 (+ (* (- (%mem-ref s 14) 1) (%mem-ref s 11)) (%mem-ref s 15)))) (f-ref (%mem-ref s 1) (* 2 (+ (* (%mem-ref s 15) (%mem-ref s 11)) (%mem-ref s 13))))) (f* (f-ref (%mem-ref s 0) (+ (* 2 (+ (* (- (%mem-ref s 14) 1) (%mem-ref s 11)) (%mem-ref s 15))) 1)) (f-ref (%mem-ref s 1) (+ (* 2 (+ (* (%mem-ref s 15) (%mem-ref s 11)) (%mem-ref s 13))) 1))))))
                    (f-set! s 17
                      (f+ (f-ref s 17) (f+ (f* (f-ref (%mem-ref s 0) (* 2 (+ (* (- (%mem-ref s 14) 1) (%mem-ref s 11)) (%mem-ref s 15)))) (f-ref (%mem-ref s 1) (+ (* 2 (+ (* (%mem-ref s 15) (%mem-ref s 11)) (%mem-ref s 13))) 1))) (f* (f-ref (%mem-ref s 0) (+ (* 2 (+ (* (- (%mem-ref s 14) 1) (%mem-ref s 11)) (%mem-ref s 15))) 1)) (f-ref (%mem-ref s 1) (* 2 (+ (* (%mem-ref s 15) (%mem-ref s 11)) (%mem-ref s 13))))))))
                    (%mem-set! s 15 (+ (%mem-ref s 15) 1))
                    (%mem-set! s 8 (- (%mem-ref s 8) 1)) (self s)))
              (#t
                (do (f-set! s 20 (f- (f-ref (%mem-ref s 0) (* 2 (+ (* (- (%mem-ref s 14) 1) (%mem-ref s 11)) (- (%mem-ref s 14) 1)))) (f-ref (%mem-ref s 0) (* 2 (+ (* (%mem-ref s 13) (%mem-ref s 11)) (%mem-ref s 13))))))
                    (f-set! s 21 (f- (f-ref (%mem-ref s 0) (+ (* 2 (+ (* (- (%mem-ref s 14) 1) (%mem-ref s 11)) (- (%mem-ref s 14) 1))) 1)) (f-ref (%mem-ref s 0) (+ (* 2 (+ (* (%mem-ref s 13) (%mem-ref s 11)) (%mem-ref s 13))) 1))))
                    (if (f= (f-ref s 20) (i->f 0)) (if (f= (f-ref s 21) (i->f 0)) (f-set! s 20 (f-ref s 22)) 0) 0)
                    (if (f< (if (f< (f-ref s 20) (i->f 0)) (f- (i->f 0) (f-ref s 20)) (f-ref s 20)) (if (f< (f-ref s 21) (i->f 0)) (f- (i->f 0) (f-ref s 21)) (f-ref s 21)))
                      (do (f-set! s 18 (f/ (f-ref s 20) (f-ref s 21)))
                          (f-set! s 19 (f- (i->f 0) (f+ (f-ref s 21) (f* (f-ref s 20) (f-ref s 18)))))
                          (f-set! (%mem-ref s 1) (* 2 (+ (* (- (%mem-ref s 14) 1) (%mem-ref s 11)) (%mem-ref s 13))) (f/ (f+ (f* (f-ref s 16) (f-ref s 18)) (f-ref s 17)) (f-ref s 19)))
                          (f-set! (%mem-ref s 1) (+ (* 2 (+ (* (- (%mem-ref s 14) 1) (%mem-ref s 11)) (%mem-ref s 13))) 1) (f/ (f- (f* (f-ref s 17) (f-ref s 18)) (f-ref s 16)) (f-ref s 19))))
                      (do (f-set! s 18 (f/ (f-ref s 21) (f-ref s 20)))
                          (f-set! s 19 (f- (i->f 0) (f+ (f-ref s 20) (f* (f-ref s 21) (f-ref s 18)))))
                          (f-set! (%mem-ref s 1) (* 2 (+ (* (- (%mem-ref s 14) 1) (%mem-ref s 11)) (%mem-ref s 13))) (f/ (f+ (f-ref s 16) (f* (f-ref s 17) (f-ref s 18))) (f-ref s 19)))
                          (f-set! (%mem-ref s 1) (+ (* 2 (+ (* (- (%mem-ref s 14) 1) (%mem-ref s 11)) (%mem-ref s 13))) 1) (f/ (f- (f-ref s 17) (f* (f-ref s 16) (f-ref s 18))) (f-ref s 19)))))
                    (f-set! s 16 (i->f 0)) (f-set! s 17 (i->f 0))
                    (%mem-set! s 14 (- (%mem-ref s 14) 1)) (%mem-set! s 15 (%mem-ref s 14))
                    (%mem-set! s 8 (- (%mem-ref s 8) 1)) (self s))))))
          (lit ((0 . a) (1 . b) (11 . 2))))
        ; A sweep of one-sided Jacobi rotations rotates each pair of columns
        ; P < Q (13 14) of the M (12) by N (11) matrix at 0, row stride 3, to
        ; make them orthogonal, and V's columns at 1, row stride 4, by the
        ; same rotation.  Word 10 is 0 while K (15) runs down the rows
        ; summing the squares of the two columns at 18 and 19 and their
        ; product at 20, 1 while K runs through A's rows (below M) and V's
        ; (below M + N) rotating them.  A pair whose product is at most the
        ; double at 22 times the root of the product of its squares is
        ; passed; word 9 counts the pairs rotated.  The rotation's c and s
        ; are at 16 and 17, made as the symmetric Schur step makes them
        ; from the squares and the product, with theta and the temporary at
        ; 21 and t at 18.
        (list (lit f64-column-jacobi)
          (lit (fn (self s)
            (match
              ((= (%mem-ref s 8) 0) 0)
              ((= (%mem-ref s 13) (- (%mem-ref s 11) 1)) 1)
              ((= (%mem-ref s 14) (%mem-ref s 11))
                (do (%mem-set! s 14 (+ (%mem-ref s 13) 2)) (%mem-set! s 13 (+ (%mem-ref s 13) 1))
                    (%mem-set! s 8 (- (%mem-ref s 8) 1)) (self s)))
              ((= (%mem-ref s 10) 0)
                (do (if (< (%mem-ref s 15) (%mem-ref s 12))
                      (do (f-set! s 18
                            (f+ (f-ref s 18)
                                (f* (f-ref (%mem-ref s 0) (+ (* (%mem-ref s 15) (%mem-ref s 3)) (%mem-ref s 13)))
                                    (f-ref (%mem-ref s 0) (+ (* (%mem-ref s 15) (%mem-ref s 3)) (%mem-ref s 13))))))
                          (f-set! s 19
                            (f+ (f-ref s 19)
                                (f* (f-ref (%mem-ref s 0) (+ (* (%mem-ref s 15) (%mem-ref s 3)) (%mem-ref s 14)))
                                    (f-ref (%mem-ref s 0) (+ (* (%mem-ref s 15) (%mem-ref s 3)) (%mem-ref s 14))))))
                          (f-set! s 20
                            (f+ (f-ref s 20)
                                (f* (f-ref (%mem-ref s 0) (+ (* (%mem-ref s 15) (%mem-ref s 3)) (%mem-ref s 13)))
                                    (f-ref (%mem-ref s 0) (+ (* (%mem-ref s 15) (%mem-ref s 3)) (%mem-ref s 14))))))
                          (%mem-set! s 15 (+ (%mem-ref s 15) 1)))
                      (do (if (f< (f* (f-ref s 22) (f-sqrt (f* (f-ref s 18) (f-ref s 19))))
                                  (if (f< (f-ref s 20) (i->f 0)) (f- (i->f 0) (f-ref s 20)) (f-ref s 20)))
                            (do (f-set! s 21 (f/ (f- (f-ref s 19) (f-ref s 18)) (f+ (f-ref s 20) (f-ref s 20))))
                                (f-set! s 18
                                  (f/ (i->f 1)
                                      (f+ (if (f< (f-ref s 21) (i->f 0)) (f- (i->f 0) (f-ref s 21)) (f-ref s 21))
                                          (f-sqrt (f+ (f* (f-ref s 21) (f-ref s 21)) (i->f 1))))))
                                (if (f< (f-ref s 21) (i->f 0)) (f-set! s 18 (f- (i->f 0) (f-ref s 18))) 0)
                                (f-set! s 16 (f/ (i->f 1) (f-sqrt (f+ (f* (f-ref s 18) (f-ref s 18)) (i->f 1)))))
                                (f-set! s 17 (f* (f-ref s 18) (f-ref s 16)))
                                (%mem-set! s 9 (+ (%mem-ref s 9) 1))
                                (%mem-set! s 10 1))
                            (%mem-set! s 14 (+ (%mem-ref s 14) 1)))
                          (f-set! s 18 (i->f 0)) (f-set! s 19 (i->f 0)) (f-set! s 20 (i->f 0))
                          (%mem-set! s 15 0)))
                    (%mem-set! s 8 (- (%mem-ref s 8) 1)) (self s)))
              ((< (%mem-ref s 15) (%mem-ref s 12))
                (do (f-set! s 21 (f-ref (%mem-ref s 0) (+ (* (%mem-ref s 15) (%mem-ref s 3)) (%mem-ref s 13))))
                    (f-set! (%mem-ref s 0) (+ (* (%mem-ref s 15) (%mem-ref s 3)) (%mem-ref s 13))
                      (f- (f* (f-ref s 16) (f-ref s 21))
                          (f* (f-ref s 17) (f-ref (%mem-ref s 0) (+ (* (%mem-ref s 15) (%mem-ref s 3)) (%mem-ref s 14))))))
                    (f-set! (%mem-ref s 0) (+ (* (%mem-ref s 15) (%mem-ref s 3)) (%mem-ref s 14))
                      (f+ (f* (f-ref s 17) (f-ref s 21))
                          (f* (f-ref s 16) (f-ref (%mem-ref s 0) (+ (* (%mem-ref s 15) (%mem-ref s 3)) (%mem-ref s 14))))))
                    (%mem-set! s 15 (+ (%mem-ref s 15) 1))
                    (%mem-set! s 8 (- (%mem-ref s 8) 1)) (self s)))
              ((< (%mem-ref s 15) (+ (%mem-ref s 12) (%mem-ref s 11)))
                (do (f-set! s 21 (f-ref (%mem-ref s 1) (+ (* (- (%mem-ref s 15) (%mem-ref s 12)) (%mem-ref s 4)) (%mem-ref s 13))))
                    (f-set! (%mem-ref s 1) (+ (* (- (%mem-ref s 15) (%mem-ref s 12)) (%mem-ref s 4)) (%mem-ref s 13))
                      (f- (f* (f-ref s 16) (f-ref s 21))
                          (f* (f-ref s 17) (f-ref (%mem-ref s 1) (+ (* (- (%mem-ref s 15) (%mem-ref s 12)) (%mem-ref s 4)) (%mem-ref s 14))))))
                    (f-set! (%mem-ref s 1) (+ (* (- (%mem-ref s 15) (%mem-ref s 12)) (%mem-ref s 4)) (%mem-ref s 14))
                      (f+ (f* (f-ref s 17) (f-ref s 21))
                          (f* (f-ref s 16) (f-ref (%mem-ref s 1) (+ (* (- (%mem-ref s 15) (%mem-ref s 12)) (%mem-ref s 4)) (%mem-ref s 14))))))
                    (%mem-set! s 15 (+ (%mem-ref s 15) 1))
                    (%mem-set! s 8 (- (%mem-ref s 8) 1)) (self s)))
              (#t
                (do (%mem-set! s 10 0) (%mem-set! s 15 0) (%mem-set! s 14 (+ (%mem-ref s 14) 1))
                    (%mem-set! s 8 (- (%mem-ref s 8) 1)) (self s))))))
          (lit ((0 . a) (1 . b) (3 . 3) (4 . 3) (11 . 3) (12 . 3) (14 . 1))))))

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

  (method factor-lower-transpose (self)
    (doc "The lower-transpose factorization: a lower matrix L with a positive diagonal whose product with its transpose is self. Self must be symmetric and positive definite; any other matrix is refused."
      (known-as "Cholesky")
      (returns LowerTranspose "The factorization, which solves and answers the determinant without factoring again")
      (example "((((Matrix from '((4 2) (2 5))) factor-lower-transpose) lower) ->list)" "((2.0 0.0) (1.0 2.0))"))
    (Matrix %square (self %st) "factor-lower-transpose")
    (Matrix %symmetric self "factor-lower-transpose")
    (LowerTranspose %of (self %st)))

  (method factor-symmetric-eigen (self)
    (doc "The eigenvalues and eigenvectors of a symmetric matrix, by cyclic Jacobi rotations: values, real and from least to greatest, and vectors, whose columns are orthonormal and whose column i is value i's eigenvector. Self must be symmetric; any other matrix is refused."
      (returns SymmetricEigen "The values and vectors")
      (example "((((Matrix from '((2 1) (1 2))) factor-symmetric-eigen) values) ->list)" "(1.0 3.0)")
      (see factor-eigen))
    (Matrix %square (self %st) "factor-symmetric-eigen")
    (Matrix %symmetric self "factor-symmetric-eigen")
    (SymmetricEigen %of (self %st)))

  (method factor-eigen (self)
    (doc "The eigenvalues and eigenvectors of any square matrix: values, complex, in the order the QR steps leave them on the diagonal of the Schur form, a conjugate pair with the positive imaginary part first; and vectors, a complex Matrix whose column i is value i's eigenvector, of unit length with its first greatest element real and positive. For a symmetric matrix, factor-symmetric-eigen answers real values and vectors."
      (returns Eigen "The values and vectors")
      (example "((((Matrix from '((0 -1) (1 0))) factor-eigen) values) ->list)" "(0.0+1.0i 0.0-1.0i)")
      (see factor-symmetric-eigen))
    (Matrix %square (self %st) "factor-eigen")
    (Eigen %of (self %st)))

  (method factor-singular (self)
    (doc "The singular value decomposition by one-sided Jacobi rotations: values, the singular values from greatest to least, and left and right, whose columns are orthonormal, with self equal to left times the diagonal of values times right's transpose. With k the lesser of self's rows and columns, there are k values, left has self's rows and k columns, and right has self's columns and k columns. Any matrix factors."
      (returns Singular "The values and vectors, which answer the rank")
      (example "((((Matrix from '((3 0) (0 -4))) factor-singular) values) ->list)" "(4.0 3.0)"))
    (Singular %of (self %st)))

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
      ((Matrix %sqrt) (if (type? ss float) ss (float-of ss)))))

  (method covariance (self . (param correction INTEGER "Optional, taken from the rows before dividing: 1 by default, 0 for the population covariance"))
    (doc "The covariance of the columns, each a variable whose observations are the rows: element (i j) is the sum over the rows of the products of column i's and column j's differences from their means, over the rows less the correction. Its diagonal is each column's variance."
      (returns Matrix "A fresh f64 Matrix of self's columns by self's columns")
      (example "(((Matrix from '((1 2) (2 4) (3 6))) covariance) ->list)" "((1.0 2.0) (2.0 4.0))")
      (see correlation))
    (let ((n (first (self extent))) (c (if (null? correction) 1 (first correction))))
      (if (int< c n) ()
        (Err raise (lit value) "Matrix covariance: needs more rows than the correction" n))
      (let ((x (self as (lit f64))) (f (Tensor %fast)))
        (let ((ones ((obj-ref f 4) (lit f64) (list n))))
          ((obj-ref f 9) ones 1)
          (let ((d (x sub (((x transpose) product (Tensor %make ones)) div (float-of n)))))
            (((d transpose) product d) div (float-of (int- n c))))))))

  (method correlation (self)
    (doc "The Pearson correlation of the columns, each a variable whose observations are the rows: the covariance with element (i j) divided by the deviations of columns i and j. Its diagonal is 1; a column whose elements are all equal has no deviation, and its row and column are not numbers."
      (returns Matrix "A fresh f64 Matrix of self's columns by self's columns")
      (example "(((Matrix from '((1 2) (2 4) (3 6))) correlation) ->list)" "((1.0 1.0) (1.0 1.0))")
      (see covariance))
    (let ((v (self covariance)))
      (let ((d (Tensor from (List map (fn (_ x) ((Matrix %sqrt) x)) ((v diagonal) ->list)) (lit f64))))
        (((v div d) transpose) div d)))))

;
; LowerUpper keeps the factors in one f64 state, L below the diagonal (its
; diagonal of 1s implied) and U on and above it, with the row swapped into
; each row in turn.  Its parts are made from that state when asked.
(def-class LowerUpper ()
  (doc "The lower-upper factorization of a square Matrix with partial pivoting, from (m factor-lower-upper): a lower matrix L with 1 on its diagonal, an upper matrix U and a permutation P, with P times the matrix equal to L times U. It solves and answers the determinant from the factors, so a matrix factored once solves many right sides."
    (known-as "LU")
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
; LowerTranspose keeps the matrix's LowerUpper, factored without a row swap, and
; the square roots of U's diagonal.  With D that diagonal, the matrix is
; L' D L'^T for the LowerUpper's unit lower L', so its L is L' with each
; column scaled by the square root of D's: the roots.
(def-class LowerTranspose ()
  (doc "The lower-transpose factorization of a symmetric positive-definite Matrix, from (m factor-lower-transpose): a lower matrix L with a positive diagonal whose product with its transpose is the matrix. It solves and answers the determinant from the factors, so a matrix factored once solves many right sides."
    (known-as "Cholesky")
    (example "(let ((f ((Matrix from '((4 2) (2 5))) factor-lower-transpose))) (list ((f lower) ->list) ((f upper) ->list)))" "(((2.0 0.0) (1.0 2.0)) ((2.0 1.0) (0.0 2.0)))")
    (example "(((Matrix from '((4 2) (2 5))) factor-lower-transpose) determinant)" "16.0")
    (see lower) (see upper) (see solve) (see determinant))

  factors   ; the matrix's LowerUpper, factored without a row swap
  roots     ; a rank-1 f64 Tensor: the square root of each of U's diagonal elements

  (static
    (method %of (self st)
      (let ((lu (LowerUpper %of st #f)))
        (if (lu singular?)
          (Err raise (lit value) "Matrix factor-lower-transpose: the matrix is not positive definite" ())
          ())
        (new-from self
          (list (lit factors) lu
                (lit roots) (Tensor from (List map (Matrix %sqrt) (((lu upper) diagonal) ->list)) (lit f64)))))))

  (method lower (self)
    (doc "L: lower, with a positive diagonal and 0 above it, whose product with its transpose is the matrix."
      (returns Matrix "A fresh f64 Matrix")
      (example "((((Matrix from '((4 2) (2 5))) factor-lower-transpose) lower) ->list)" "((2.0 0.0) (1.0 2.0))"))
    (((field (lit factors)) lower) mul (field (lit roots))))

  (method upper (self)
    (doc "The transpose of L: upper, with a positive diagonal and 0 below it."
      (returns Matrix "A fresh f64 Matrix")
      (example "((((Matrix from '((4 2) (2 5))) factor-lower-transpose) upper) ->list)" "((2.0 1.0) (0.0 2.0))"))
    (((self lower) transpose) copy))

  (method solve (self (param b Tensor "The right side: a rank-1 Tensor of the matrix's rows, or a Matrix of them"))
    (doc "The x for which the factored matrix times x is b."
      (returns Tensor "A fresh f64 Tensor of b's extent: rank 1 for a rank-1 b, a Matrix for a Matrix")
      (example "((((Matrix from '((4 2) (2 5))) factor-lower-transpose) solve (Tensor from '(6 7))) ->list)" "(1.0 1.0)"))
    ((field (lit factors)) solve b))

  (method determinant (self)
    (doc "The determinant: the product of L's diagonal, squared. Always positive."
      (returns FLOAT "The determinant")
      (example "(((Matrix from '((4 2) (2 5))) factor-lower-transpose) determinant)" "16.0"))
    ((field (lit factors)) determinant)))

;
; Orthogonal keeps the Householder factors in one f64 state, R on and
; above the diagonal and each reflection's vector below it, with each
; reflection's tau.  Q is never kept: it is the reflections applied to the
; identity's first k columns, and a solve applies them to b instead.
(def-class Orthogonal ()
  (doc "The orthogonal-upper (QR) factorization of a Matrix by Householder reflections, from (m factor-orthogonal): Q, whose columns are orthonormal, and an upper R, with Q times R equal to the matrix. It solves least squares, so a matrix factored once fits many right sides."
    (known-as "QR")
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

;
; Eigen keeps the values as a rank-1 c128 Tensor and the vectors as a c128
; Matrix, made by the Hessenberg reduction, the QR steps and the complex
; triangle.
(def-class Eigen ()
  (doc "The eigenvalues and eigenvectors of a square Matrix, from (m factor-eigen): values, complex, in the order the QR steps leave them on the diagonal, a conjugate pair with the positive imaginary part first; and vectors, a complex Matrix whose column i is value i's eigenvector, so the matrix times vectors is vectors times the diagonal of values."
    (example "(let ((e ((Matrix from '((2 0) (0 3))) factor-eigen))) (list ((e values) ->list) ((e vectors) ->list)))" "((2.0+0.0i 3.0+0.0i) ((1.0+0.0i 0.0+0.0i) (0.0+0.0i 1.0+0.0i)))")
    (see values) (see vectors))

  values    ; a rank-1 c128 Tensor
  vectors   ; a c128 Matrix, column i value i's eigenvector

  (static
    (method %of (self st)
      (let ((r (Matrix %eigen st)))
        (new-from self (list (lit values) (first r) (lit vectors) (List ref 1 r))))))

  (method values (self)
    (doc "The eigenvalues, complex, a conjugate pair with the positive imaginary part first. A real eigenvalue has imaginary part 0.0."
      (returns Tensor "A rank-1 c128 Tensor")
      (example "((((Matrix from '((2 1) (0 3))) factor-eigen) values) ->list)" "(2.0+0.0i 3.0+0.0i)"))
    (field (lit values)))

  (method vectors (self)
    (doc "The eigenvectors: a complex Matrix whose column i is value i's eigenvector, of unit length with its first greatest element real and positive; a real eigenvalue's is real, and a conjugate pair's are conjugates."
      (returns Matrix "A c128 Matrix")
      (example "((((Matrix from '((2 0) (0 3))) factor-eigen) vectors) ->list)" "((1.0+0.0i 0.0+0.0i) (0.0+0.0i 1.0+0.0i))"))
    (field (lit vectors))))

;
; Singular keeps the values as a rank-1 f64 Tensor and the left and right
; vectors as f64 Matrices, made by one-sided Jacobi rotations of the
; columns of the matrix or of its transpose.
(def-class Singular ()
  (doc "The singular value decomposition of a Matrix, from (m factor-singular): values, from greatest to least, and left and right, whose columns are orthonormal, so the matrix is left times the diagonal of values times right's transpose. The rank is the number of values above a tolerance."
    (known-as "SVD")
    (example "(let ((d ((Matrix from '((0 2) (1 0))) factor-singular))) (list ((d values) ->list) ((d left) ->list) ((d right) ->list)))" "((2.0 1.0) ((1.0 0.0) (0.0 1.0)) ((0.0 1.0) (1.0 0.0)))")
    (see values) (see left) (see right) (see rank))

  left      ; an f64 Matrix, the matrix's rows by k
  values    ; a rank-1 f64 Tensor of k values, greatest first
  right     ; an f64 Matrix, the matrix's columns by k

  (static
    (method %of (self st)
      (let ((r (Matrix %singular st)))
        (new-from self
          (list (lit left) (Matrix %make (List ref 0 r))
                (lit values) (Tensor from (List ref 1 r) (lit f64))
                (lit right) (Matrix %make (List ref 2 r)))))))

  (method values (self)
    (doc "The singular values, from greatest to least, none negative."
      (returns Tensor "A rank-1 f64 Tensor")
      (example "((((Matrix from '((1 1) (1 1))) factor-singular) values) ->list)" "(2.0 0.0)"))
    (field (lit values)))

  (method left (self)
    (doc "The left vectors: a Matrix of the matrix's rows whose columns are orthonormal, column i value i's. A vector's sign is not fixed, but left column i and right column i change sign together."
      (returns Matrix "An f64 Matrix")
      (example "((((Matrix from '((0 2) (1 0))) factor-singular) left) ->list)" "((1.0 0.0) (0.0 1.0))"))
    (field (lit left)))

  (method right (self)
    (doc "The right vectors: a Matrix of the matrix's columns whose columns are orthonormal, column i value i's. The matrix times right column i is value i times left column i."
      (returns Matrix "An f64 Matrix")
      (example "((((Matrix from '((0 2) (1 0))) factor-singular) right) ->list)" "((0.0 1.0) (1.0 0.0))"))
    (field (lit right)))

  (method rank (self . (param tolerance NUMBER "Optional; the default is the greatest value times the greater of the matrix's rows and columns times 2^-52"))
    (doc "The matrix's rank: how many singular values are greater than the tolerance. The default tolerance scales with the matrix, so a value left by rounding in place of 0 is not counted. This is the matrix's rank in linear algebra, not a Tensor's rank, its number of axes."
      (returns INTEGER "The number of values above the tolerance")
      (example "(((Matrix from '((1 2) (2 4))) factor-singular) rank)" "1")
      (example "(((Matrix from '((1 0) (0 0.001))) factor-singular) rank 0.01)" "1"))
    (let ((vals ((field (lit values)) ->list))
          (e (f-div (float-of 1) (float-of 67108864))))
      (let ((cut (if (null? tolerance)
                   (let ((rows (first (List ref 1 ((field (lit left)) %st))))
                         (cols (first (List ref 1 ((field (lit right)) %st)))))
                     (f-mul (f-mul (first vals) (float-of (if (int< rows cols) cols rows))) (f-mul e e)))
                   (float-of (first tolerance)))))
        (List length (List filter (fn (_ x) (f-lt cut x)) vals))))))

(Matrix %register-all!)

(doc (provide x/num/matrix Matrix LowerUpper LowerTranspose Orthogonal SymmetricEigen Eigen Singular)
  "Matrix: a Tensor of rank 2 with the linear algebra -- the matrix product, solve, inverse, determinant, trace, diagonal, norm, covariance and correlation -- run in kernels that compile once they have run long enough; and its factorizations, LowerUpper, LowerTranspose, Orthogonal, SymmetricEigen, Eigen and Singular."
  (example "((Matrix from '((2 1) (1 3))) determinant)" "5.0"))
