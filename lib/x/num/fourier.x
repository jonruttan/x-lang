; fourier.x -- the discrete Fourier transform: a plan per length, any length.
;
; A Fourier plan holds what a length n needs, computed once: the twiddle
; table and bit-reversal table for a power of two (iterative radix-2), or for
; any other n the chirp and the transformed kernel of Bluestein's algorithm,
; which turns the transform into a convolution done by a power-of-two plan.
; Either way a transform is O(n log n).
;
; The plan works on SPLIT form, two vectors of floats (real parts and
; imaginary parts) transformed in place, so a butterfly allocates only its
; floats; forward / inverse convert from and to vectors of numbers
; (Complex values, or reals). The forward transform is unscaled,
; X[k] = sum x[j] e^(-2 pi i jk/n); the inverse divides by n.
;
; Every unit root comes from %unit, which folds its angle into the first
; octant: the quarter points are exact (cos pi/2 is 0, not 6e-17) and the
; table's errors are symmetric.
;
; x has no automatic collection: a transform of n points allocates on the
; order of n log n floats, so a long-running loop of transforms collects
; between them.
;
; @copyright 2026 Jon Ruttan
; @license MIT No Attribution (MIT-0)

(module x/num/fourier)
(import x/type/class)
(import x/type/vector)
(import x/num/float float-of f-add f-sub f-mul f-div fsin fcos pi)
(import x/num/complex Complex make-complex)
(import x/core/doors int+ int- int* int/ int% int< int= int& int>> obj-ref obj-set!)

(def-class Fourier ()
  (doc "A discrete Fourier transform plan for one length n: forward and inverse transforms in O(n log n) for every n (radix-2 for a power of two, Bluestein's algorithm otherwise). Make one with (Fourier plan n) and reuse it; (Fourier fft v) makes one per call."
    (note "The forward transform is unscaled, X[k] = sum x[j] e^(-2 pi i jk/n); the inverse divides by n, so (p inverse (p forward v)) is v to rounding.")
    (example "(Fourier fft #(1 2 3 4))" "#(10.0+0.0i -2.0+2.0i -2.0+0.0i -2.0-2.0i)")
    (see plan) (see forward) (see forward!) (see dft))

  n       ; the length
  cos     ; radix-2: cos 2 pi t/n for t in [0, n/2)
  sin     ; radix-2: sin 2 pi t/n for t in [0, n/2)
  rev     ; radix-2: the bit-reversal permutation of [0, n)
  inner   ; Bluestein: the power-of-two plan of the convolution, else ()
  wre     ; Bluestein: the chirp e^(-pi i k^2/n), real parts
  wim     ;   and imaginary parts
  bre     ; Bluestein: the transformed kernel, real parts
  bim     ;   and imaginary parts

  (static
    (method plan (self (param n INTEGER "Transform length, at least 1"))
      (doc "A plan for transforms of length n. A power of two runs radix-2; any other n runs Bluestein's algorithm on a power-of-two plan of at least 2n-1 points."
        (returns Fourier "A reusable plan")
        (example "((Fourier plan 6) size)" "6"))
      (if (int< n 1) (Err raise 'value "Fourier plan: n must be at least 1" n) ())
      (if (self %pow2? n)
        (self %radix2-plan n)
        (self %bluestein-plan n)))

    (method fft (self (param v VECTOR|LIST "Numbers: Complex values or reals"))
      (doc "The forward transform of v, through a plan made for its length."
        (returns VECTOR "A vector of Complex values, X[k] = sum v[j] e^(-2 pi i jk/n)")
        (example "(Fourier fft #(1 1 1 1))" "#(4.0+0.0i 0.0+0.0i 0.0+0.0i 0.0+0.0i)"))
      (let ((w (self %vec v)))
        ((self plan (Vector length w)) forward w)))

    (method ifft (self (param v VECTOR|LIST "Numbers: Complex values or reals"))
      (doc "The inverse transform of v, scaled by 1/n, through a plan made for its length."
        (returns VECTOR "A vector of Complex values, x[j] = (1/n) sum v[k] e^(2 pi i jk/n)")
        (example "(Fourier ifft #(4 0 0 0))" "#(1.0+0.0i 1.0+0.0i 1.0+0.0i 1.0+0.0i)"))
      (let ((w (self %vec v)))
        ((self plan (Vector length w)) inverse w)))

    (method dft (self (param v VECTOR|LIST "Numbers: Complex values or reals"))
      (doc "The forward transform by its definition, O(n^2): the reference fft is checked against."
        (returns VECTOR "A vector of Complex values, the same transform as fft")
        (example "(Fourier dft #(1 2 3 4))" "#(10.0+0.0i -2.0+2.0i -2.0+0.0i -2.0-2.0i)"))
      (self %direct (self %vec v) #f))

    (method idft (self (param v VECTOR|LIST "Numbers: Complex values or reals"))
      (doc "The inverse transform by its definition, O(n^2), scaled by 1/n."
        (returns VECTOR "A vector of Complex values, the same transform as ifft")
        (example "(Fourier idft #(4 0 0 0))" "#(1.0+0.0i 1.0+0.0i 1.0+0.0i 1.0+0.0i)"))
      (self %direct (self %vec v) #t))

    ; --- construction ----------------------------------------------------
    (method %vec (self v)
      (if (Vector vector? v) v (Vector from-list v)))

    (method %pow2? (self n)
      (int= (int& n (int- n 1)) 0))

    ; e^(2 pi i t/m) as (cos . sin), t in [0, m). The angle's quadrant q
    ; comes off as a rotation, its remainder r/m of a quarter turn folds at
    ; the octant (r past m/2 reads as m - r with cos and sin exchanged), so
    ; the libm call sees an angle in [0, pi/4] and r = 0 is exact.
    (method %unit (self t m)
      (let ((quad (int/ (int* 4 t) m)))
        (let ((r (int- (int* 4 t) (int* quad m))))
          (let ((fold (int< m (int* 2 r))))
            (let ((a (f-div (f-mul pi (float-of (if fold (int- m r) r)))
                            (float-of (int* 2 m)))))
              (self %rotate (if fold (fsin a) (fcos a)) (if fold (fcos a) (fsin a)) quad))))))

    ; (c . s) turned by quad quarter turns.
    (method %rotate (self c s quad)
      (let ((z (float-of 0)))
        (match
          ((int= quad 0) (pair c s))
          ((int= quad 1) (pair (f-sub z s) c))
          ((int= quad 2) (pair (f-sub z c) (f-sub z s)))
          (#t (pair s (f-sub z c))))))

    (method %radix2-plan (self n)
      (let ((half (int>> n 1))
            (cs (Vector make (int>> n 1) ()))
            (sn (Vector make (int>> n 1) ()))
            (rev (Vector make n 0)))
        (def table
          (fn (go t)
            (if (int< t half)
              (let ((u (self %unit t n)))
                (obj-set! cs (int+ t 1) (first u))
                (obj-set! sn (int+ t 1) (rest u))
                (go (int+ t 1))))))
        (table 0)
        (def bits
          (fn (go i r b)
            (if (int< b n) (go (int>> i 1) (int+ (int* r 2) (int& i 1)) (int* b 2)) r)))
        (def fill
          (fn (go i)
            (if (int< i n)
              (do (obj-set! rev (int+ i 1) (bits i 0 1)) (go (int+ i 1))))))
        (fill 0)
        (new-from self (list 'n n 'cos cs 'sin sn 'rev rev 'inner ()))))

    ; Bluestein: jk = (j^2 + k^2 - (k-j)^2)/2, so with the chirp
    ; w[k] = e^(-pi i k^2/n) the transform is X[k] = w[k] (a * b)[k], the
    ; convolution of a[j] = x[j] w[j] with the kernel b[j] = conj(w[|j|]),
    ; wrapped round m >= 2n - 1 points. The plan keeps B, the kernel's
    ; transform. k^2 is taken mod 2n before it becomes an angle, so a long
    ; n keeps its precision.
    (method %bluestein-plan (self n)
      (let ((m (self %pow2-at-least (int- (int* 2 n) 1) 1))
            (z (float-of 0)))
        (let ((inner (self %radix2-plan m))
              (wre (Vector make n ())) (wim (Vector make n ()))
              (bre (Vector make m z)) (bim (Vector make m z)))
          (def chirp
            (fn (go k)
              (if (int< k n)
                (let ((u (self %unit (int% (int* k k) (int* 2 n)) (int* 2 n))))
                  (obj-set! wre (int+ k 1) (first u))
                  (obj-set! wim (int+ k 1) (f-sub z (rest u)))
                  (obj-set! bre (int+ k 1) (first u))
                  (obj-set! bim (int+ k 1) (rest u))
                  (if (int< 0 k)
                    (do (obj-set! bre (int+ (int- m k) 1) (first u))
                        (obj-set! bim (int+ (int- m k) 1) (rest u))))
                  (go (int+ k 1))))))
          (chirp 0)
          (inner %radix2! bre bim #f)
          (new-from self (list 'n n 'inner inner 'wre wre 'wim wim 'bre bre 'bim bim)))))

    (method %pow2-at-least (self n m)
      (if (int< m n) (self %pow2-at-least n (int* m 2)) m))

    ; The definition, O(n^2), sign -1 forward and +1 inverse (then / n).
    (method %direct (self v inverse)
      (let ((n (Vector length v)) (z (float-of 0)))
        (let ((re (self %reals v)) (im (self %imags v)) (out (Vector make n ())))
          (def term
            (fn (go j k sr si)
              (if (int< j n)
                (let ((u (self %unit (int% (int* j k) n) n)))
                  (let ((c (first u)) (s (if inverse (rest u) (f-sub z (rest u))))
                        (xr (obj-ref re (int+ j 1))) (xi (obj-ref im (int+ j 1))))
                    (go (int+ j 1) k
                      (f-add sr (f-sub (f-mul xr c) (f-mul xi s)))
                      (f-add si (f-add (f-mul xr s) (f-mul xi c))))))
                (if inverse
                  (make-complex (f-div sr (float-of n)) (f-div si (float-of n)))
                  (make-complex sr si)))))
          (def each
            (fn (go k)
              (if (int< k n)
                (do (obj-set! out (int+ k 1) (term 0 k z z)) (go (int+ k 1))))))
          (each 0)
          out)))

    (method %reals (self v)
      (Vector map (fn (_ x) (float-of (Complex real-part x))) v))

    (method %imags (self v)
      (Vector map (fn (_ x) (float-of (Complex imag-part x))) v)))

  ; --- the transforms ----------------------------------------------------
  (method size (self)
    (doc "The length this plan transforms."
      (returns INTEGER "n")
      (example "((Fourier plan 8) size)" "8"))
    (field 'n))

  (method forward (self (param v VECTOR|LIST "n numbers: Complex values or reals"))
    (doc "The forward transform of v: X[k] = sum v[j] e^(-2 pi i jk/n), unscaled."
      (returns VECTOR "A vector of n Complex values")
      (example "((Fourier plan 2) forward #(1 2))" "#(3.0+0.0i -1.0+0.0i)"))
    (self %through v #f))

  (method inverse (self (param v VECTOR|LIST "n numbers: Complex values or reals"))
    (doc "The inverse transform of v: x[j] = (1/n) sum v[k] e^(2 pi i jk/n)."
      (returns VECTOR "A vector of n Complex values")
      (example "((Fourier plan 2) inverse #(3 -1))" "#(1.0+0.0i 2.0+0.0i)"))
    (self %through v #t))

  (method forward! (self (param re VECTOR "n floats, the real parts") (param im VECTOR "n floats, the imaginary parts"))
    (doc "The forward transform in place on split form: re and im are overwritten with the real and imaginary parts of X. Allocates no vectors, so a stream of transforms reuses its buffers."
      (returns Fourier "self, for chaining")
      (example "(let ((re (Vector of 1.0 2.0)) (im (Vector of 0.0 0.0))) ((Fourier plan 2) forward! re im) re)" "#(3.0 -1.0)"))
    (self %check re im)
    (self %transform! re im #f)
    self)

  (method inverse! (self (param re VECTOR "n floats, the real parts") (param im VECTOR "n floats, the imaginary parts"))
    (doc "The inverse transform in place on split form, scaled by 1/n."
      (returns Fourier "self, for chaining")
      (example "(let ((re (Vector of 3.0 -1.0)) (im (Vector of 0.0 0.0))) ((Fourier plan 2) inverse! re im) re)" "#(1.0 2.0)"))
    (self %check re im)
    (self %transform! re im #t)
    self)

  (method %check (self re im)
    (let ((n (field 'n)))
      (if (if (int= (Vector length re) n) (int= (Vector length im) n) #f) ()
        (Err raise 'value "Fourier: split vectors must both have the plan's length" n))))

  (method %through (self v inverse)
    (let ((w (Fourier %vec v)))
      (if (int= (Vector length w) (field 'n)) ()
        (Err raise 'value "Fourier: input length is not the plan's" (Vector length w)))
      (let ((re (Fourier %reals w)) (im (Fourier %imags w)))
        (self %transform! re im inverse)
        (Vector build (field 'n)
          (fn (_ k) (make-complex (obj-ref re (int+ k 1)) (obj-ref im (int+ k 1))))))))

  ; Either algorithm, then the inverse's 1/n.
  (method %transform! (self re im inverse)
    (if (null? (field 'inner))
      (self %radix2! re im inverse)
      (self %bluestein! re im inverse))
    (if inverse (self %scale! re im) ()))

  (method %scale! (self re im)
    (let ((n (field 'n)) (f (f-div (float-of 1) (float-of (field 'n)))))
      (def walk
        (fn (go i)
          (if (int< i n)
            (do (obj-set! re (int+ i 1) (f-mul f (obj-ref re (int+ i 1))))
                (obj-set! im (int+ i 1) (f-mul f (obj-ref im (int+ i 1))))
                (go (int+ i 1))))))
      (walk 0)))

  ; Iterative radix-2, unscaled: bit-reverse, then log2 n passes of
  ; butterflies. A pass of span `size` takes every (n/size)-th twiddle; the
  ; forward transform conjugates it. The loops are local to this method:
  ; a class dispatch per butterfly would cost more than the butterfly.
  (method %radix2! (self re im inverse)
    (let ((n (field 'n)) (cs (field 'cos)) (sn (field 'sin)) (rev (field 'rev))
          (z (float-of 0)))
      (def swap
        (fn (go i)
          (if (int< i n)
            (let ((j (obj-ref rev (int+ i 1))))
              (if (int< i j)
                (let ((r (obj-ref re (int+ i 1))) (s (obj-ref im (int+ i 1))))
                  (obj-set! re (int+ i 1) (obj-ref re (int+ j 1)))
                  (obj-set! im (int+ i 1) (obj-ref im (int+ j 1)))
                  (obj-set! re (int+ j 1) r)
                  (obj-set! im (int+ j 1) s)))
              (go (int+ i 1))))))
      (swap 0)
      (def fly
        (fn (go a k half step)
          (if (int< k half)
            (let ((b (int+ a half)) (t (int+ (int* k step) 1)))
              (let ((wr (obj-ref cs t))
                    (wi (if inverse (obj-ref sn t) (f-sub z (obj-ref sn t))))
                    (br (obj-ref re (int+ b 1))) (bi (obj-ref im (int+ b 1)))
                    (ar (obj-ref re (int+ a 1))) (ai (obj-ref im (int+ a 1))))
                (let ((tr (f-sub (f-mul wr br) (f-mul wi bi)))
                      (ti (f-add (f-mul wr bi) (f-mul wi br))))
                  (obj-set! re (int+ b 1) (f-sub ar tr))
                  (obj-set! im (int+ b 1) (f-sub ai ti))
                  (obj-set! re (int+ a 1) (f-add ar tr))
                  (obj-set! im (int+ a 1) (f-add ai ti))
                  (go (int+ a 1) (int+ k 1) half step)))))))
      (def blocks
        (fn (go start size)
          (if (int< start n)
            (do (fly start 0 (int>> size 1) (int/ n size))
                (go (int+ start size) size)))))
      (def passes
        (fn (go size)
          (if (int< n size) ()
            (do (blocks 0 size) (go (int* size 2))))))
      (passes 2)))

  ; Bluestein, unscaled. The inverse is the forward transform of the
  ; conjugate, conjugated: the chirp is the forward one either way.
  (method %bluestein! (self re im inverse)
    (let ((n (field 'n)) (inner (field 'inner))
          (wre (field 'wre)) (wim (field 'wim)) (bre (field 'bre)) (bim (field 'bim))
          (z (float-of 0)))
      (let ((m (inner size)))
        (let ((are (Vector make m z)) (aim (Vector make m z)))
          ; a[j] = x[j] w[j], x conjugated for the inverse
          (def load
            (fn (go j)
              (if (int< j n)
                (let ((xr (obj-ref re (int+ j 1)))
                      (xi (if inverse (f-sub z (obj-ref im (int+ j 1))) (obj-ref im (int+ j 1))))
                      (cr (obj-ref wre (int+ j 1))) (ci (obj-ref wim (int+ j 1))))
                  (obj-set! are (int+ j 1) (f-sub (f-mul xr cr) (f-mul xi ci)))
                  (obj-set! aim (int+ j 1) (f-add (f-mul xr ci) (f-mul xi cr)))
                  (go (int+ j 1))))))
          (load 0)
          (inner %radix2! are aim #f)
          ; A B, pointwise
          (def mul
            (fn (go j)
              (if (int< j m)
                (let ((ar (obj-ref are (int+ j 1))) (ai (obj-ref aim (int+ j 1)))
                      (br (obj-ref bre (int+ j 1))) (bi (obj-ref bim (int+ j 1))))
                  (obj-set! are (int+ j 1) (f-sub (f-mul ar br) (f-mul ai bi)))
                  (obj-set! aim (int+ j 1) (f-add (f-mul ar bi) (f-mul ai br)))
                  (go (int+ j 1))))))
          (mul 0)
          (inner %radix2! are aim #t)
          ; X[k] = w[k] c[k] / m, conjugated back for the inverse
          (def store
            (fn (go k f)
              (if (int< k n)
                (let ((cr (f-mul f (obj-ref are (int+ k 1)))) (ci (f-mul f (obj-ref aim (int+ k 1))))
                      (wr (obj-ref wre (int+ k 1))) (wi (obj-ref wim (int+ k 1))))
                  (let ((xi (f-add (f-mul cr wi) (f-mul ci wr))))
                    (obj-set! re (int+ k 1) (f-sub (f-mul cr wr) (f-mul ci wi)))
                    (obj-set! im (int+ k 1) (if inverse (f-sub z xi) xi))
                    (go (int+ k 1) f))))))
          (store 0 (f-div (float-of 1) (float-of m))))))))

(doc (provide x/num/fourier Fourier)
  (example "(Fourier fft #(1 2 3 4))" "#(10.0+0.0i -2.0+2.0i -2.0+0.0i -2.0-2.0i)")
  (example "((Fourier plan 3) size)" "3")
  "The discrete Fourier transform: reusable plans, O(n log n) for every length.")
