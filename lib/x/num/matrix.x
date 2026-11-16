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
; m, built on a LowerUpper that never swaps a row.
;
; The work is done by six kernels, word forms (x/tool/word-form) that loop
; over two or three axes inside one run, so an operation costs a few runs
; however large its matrices: the product; and LU factorization with
; partial pivoting, a pivot search down a column, a row swap and the
; elimination below a pivot, with forward and back substitution for solve.
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
(import x/num/float float float-of f-mul f-lt libm-fn)
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
    ; kernels keep at 16, 17 and 18, and drive kernel NAME to the end of its
    ; run.
    (method %run (self s name words)
      (let ((p (str->ptr s)))
        (def clear (fn (go b) (if (int< b 152) (do (ptr-set-word! p b 0) (go (int+ b %word-size))) ())))
        (clear 128)
        (List for-each (fn (_ w) (ptr-set-word! p (int* (first w) %word-size) (rest w))) words)
        ((obj-ref (Tensor %fast) 14) name s)))

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
              (def clear (fn (go b) (if (int< b 152) (do (ptr-set-word! (str->ptr s) b 0) (go (int+ b %word-size))) ())))
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
    (let ((d (self sub (self transpose))))
      (let ((ss ((d mul d) sum)))
        (if (f-lt (float-of 0) (if (type? ss float) ss (float-of ss)))
          (Err raise (lit value) "Matrix factor-cholesky: the matrix is not symmetric" ())
          ())))
    (Cholesky %of (self %st)))

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
    (let ((f (Tensor %fast)) (n (field (lit n))))
      (let ((st ((obj-ref f 10) (field (lit packed)) (lit f64))))
        (def go
          (fn (go i)
            (if (int< i n)
              (do (if (int= (count i) 0) ()
                    ((obj-ref f 9) ((obj-ref f 11) st (list (count i)) (list 1) (int+ (int* i n) (from i))) x))
                  (go (int+ i 1)))
              st)))
        (go 0))))

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

(Matrix %register-all!)

(doc (provide x/num/matrix Matrix LowerUpper Cholesky)
  "Matrix: a Tensor of rank 2 with the linear algebra -- the matrix product, solve, inverse, determinant, trace, diagonal and norm -- run in kernels that compile once they have run long enough; and its factorizations, LowerUpper and Cholesky."
  (example "((Matrix from '((2 1) (1 3))) determinant)" "5.0"))
