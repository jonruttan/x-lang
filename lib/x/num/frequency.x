; frequency.x -- the discrete Fourier transform: a plan per length, any length.
;
; A Frequency plan holds what a length n needs, computed once: the twiddle
; table and bit-reversal table for a power of two (iterative radix-2), or for
; any other n the chirp and the transformed kernel of Bluestein's algorithm,
; which turns the transform into a convolution done by a power-of-two plan.
; Either way a transform is O(n log n). The forward transform is unscaled,
; X[k] = sum x[j] e^(-2 pi i jk/n); the inverse divides by n.
;
; The plan owns its memory: every table and the data being transformed are
; doubles in buffers of its own, as IEEE bits, so a transform makes no
; Float. Two kernels do all the arithmetic, each written once as a word form
; (x/tool/word-form): %radix2, the bit reversal and every butterfly pass of a
; power-of-two transform, and %pointwise, a complex multiply of one buffer
; by another that serves Bluestein's three steps and the inverse's 1/n. The
; inverse is the forward transform with real and imaginary parts swapped
; (swap(DFT(swap x)) is n times the inverse), so no kernel negates.
;
; The kernels run compiled where compile-asm can build them (an 8-byte
; word, an assembler backend) and only after they write the same bits as
; their pure twins; elsewhere the pure twins run. A compiled transform is
; one call per kernel and allocates nothing. A pure one allocates per step,
; so it runs in budgeted calls and the plan collects between them once its
; churn reaches %window steps; the converting doors (forward, inverse,
; forward!) count their churn the same way. Either way a loop of transforms
; holds its heap flat.
;
; Every unit root comes from %unit, which folds its angle into the first
; octant: the quarter points are exact (cos pi/2 is 0, not 6e-17) and the
; table's errors are symmetric.
;
; @copyright 2026 Jon Ruttan
; @license MIT No Attribution (MIT-0)

(module x/num/frequency)
(import x/type/class)
(import x/type/vector)
(import x/type/list)
(import x/sys/gc)
(import x/num/float float float-of f-add f-sub f-mul f-div fsin fcos pi libm-fn)
(import x/num/complex Complex make-complex)
(import x/tool/word-form word-form-pure)
(import x/tool/compiled)
(import x/core/doors int+ int- int* int/ int% int< int= int& int>> obj-ref obj-set!
  mem-cmp ptr->int ptr-ref-word ptr-set-word! str->ptr str-make type-make-instance type-of type?)

(def-class Frequency ()
  (doc "A discrete Fourier transform plan for one length n: forward and inverse transforms in O(n log n) for every n (radix-2 for a power of two, Bluestein's algorithm otherwise). Make one with (Frequency plan n) and reuse it; (Frequency fft v) makes one per call. The plan keeps its tables and data in buffers of its own, its kernels run compiled where the JIT can build them, and it collects its own garbage."
    (known-as "Fourier transform" "FFT" "DFT")
    (note "The forward transform is unscaled, X[k] = sum x[j] e^(-2 pi i jk/n); the inverse divides by n, so (p inverse (p forward v)) is v to rounding.")
    (example "(Frequency fft #(1 2 3 4))" "#(10.0+0.0i -2.0+2.0i -2.0+0.0i -2.0-2.0i)")
    (see plan) (see forward) (see forward!) (see jit!) (see dft))

  n       ; the length
  scr     ; the kernels' scratch: words, then doubles from double 16
  re      ; the data, n doubles: real parts
  im      ;   and imaginary parts
  unit    ; two doubles, 1/n and 0: the inverse's scale
  cos     ; radix-2: cos 2 pi t/n for t in [0, n/2)
  sin     ; radix-2: -sin 2 pi t/n, the forward twiddle's imaginary part
  rev     ; radix-2: the bit-reversal permutation, n words
  inner   ; Bluestein: the power-of-two plan of the convolution, else ()
  wre     ; Bluestein: the chirp e^(-pi i k^2/n), n doubles
  wim
  bre     ; Bluestein: the kernel's transform over m, scaled by 1/m
  bim

  (static
    ; --- the plan ---------------------------------------------------------
    (method plan (self (param n INTEGER "Transform length, at least 1"))
      (doc "A plan for transforms of length n. A power of two runs radix-2; any other n runs Bluestein's algorithm on a power-of-two plan of at least 2n-1 points."
        (returns Frequency "A reusable plan")
        (example "((Frequency plan 6) size)" "6"))
      (if (int< n 1) (Err raise 'value "Frequency plan: n must be at least 1" n) ())
      (self %make n))

    (method fft (self (param v VECTOR|LIST "Numbers: Complex values or reals"))
      (doc "The forward transform of v, through a plan made for its length."
        (returns VECTOR "A vector of Complex values, X[k] = sum v[j] e^(-2 pi i jk/n)")
        (example "(Frequency fft #(1 1 1 1))" "#(4.0+0.0i 0.0+0.0i 0.0+0.0i 0.0+0.0i)"))
      (let ((w (self %vec v)))
        ((self plan (Vector length w)) forward w)))

    (method ifft (self (param v VECTOR|LIST "Numbers: Complex values or reals"))
      (doc "The inverse transform of v, scaled by 1/n, through a plan made for its length."
        (returns VECTOR "A vector of Complex values, x[j] = (1/n) sum v[k] e^(2 pi i jk/n)")
        (example "(Frequency ifft #(4 0 0 0))" "#(1.0+0.0i 1.0+0.0i 1.0+0.0i 1.0+0.0i)"))
      (let ((w (self %vec v)))
        ((self plan (Vector length w)) inverse w)))

    (method dft (self (param v VECTOR|LIST "Numbers: Complex values or reals"))
      (doc "The forward transform by its definition, O(n^2) in Float arithmetic: the reference fft is checked against."
        (returns VECTOR "A vector of Complex values, the same transform as fft")
        (example "(Frequency dft #(1 2 3 4))" "#(10.0+0.0i -2.0+2.0i -2.0+0.0i -2.0-2.0i)"))
      (self %direct (self %vec v) #f))

    (method idft (self (param v VECTOR|LIST "Numbers: Complex values or reals"))
      (doc "The inverse transform by its definition, O(n^2), scaled by 1/n."
        (returns VECTOR "A vector of Complex values, the same transform as ifft")
        (example "(Frequency idft #(4 0 0 0))" "#(1.0+0.0i 1.0+0.0i 1.0+0.0i 1.0+0.0i)"))
      (self %direct (self %vec v) #t))

    ; --- the kernels' lane --------------------------------------------------
    (method jit! (self)
      (doc "Build and adopt the compiled kernels (JIT; ARM64 and x86-64) now, if they transform the check inputs to exactly the bits the pure kernels do. Idempotent. Answers #t when the compiled kernels are active, #f where none can be built; the transforms are the same either way. The transforms call this on their own once the pure kernels have run about as long as building the compiled ones takes."
        (returns BOOL "#t when the compiled kernels are active")
        (sample "(Frequency jit!)" "#t once the compiled kernels have proved themselves on this host, #f elsewhere"))
      ; The cell is marked first: the check's own plans run kernels, and a
      ; step counted there must not start a second build.
      (if (null? (first (self %engine-cell)))
        (do (%set-first! (self %engine-cell) (lit building))
            (%set-first! (self %engine-cell)
              (Compiled make-on-demand (lit frequency) (self %pure)
                (fn (_)
                  (import x/tool/word-form-jit)
                  ((prim-ref (lit word-form) (lit jit-make)) (self %forms)
                   (fn (_ engine) (Frequency %agrees? engine))))
                (fn (_ v) (%set-first! (Frequency %lane-cell) (pair (not (eq? v (Frequency %pure))) v))))))
        ())
      (let ((e (first (self %engine-cell))))
        (if (eq? e (lit building)) #f
          (do (if (eq? (e state) (lit interpreted)) (e compile!) ())
              (eq? (e state) (lit compiled))))))

    (method compiled? (self)
      (doc "Whether the compiled kernels are the ones transforms run on."
        (returns BOOL "#t when the compiled kernels are active")
        (sample "(Frequency compiled?)" "#t after (Frequency jit!) has succeeded on this host"))
      (first (self %kernels)))

    ; The kernels the plans run, (COMPILED? RADIX2 POINTWISE): Compiled
    ; installs a version into the lane cell, the pure one before a state
    ; image is written, so no compiled code outlives its process.
    (%lane-cell (pair () ()))
    (method %kernels (self)
      (let ((k (first (self %lane-cell))))
        (if (null? k)
          (do (%set-first! (self %lane-cell) (pair #f (self %pure))) (first (self %lane-cell)))
          k)))

    (method %pure (self)
      (if (null? (first (self %pure-cell)))
        (%set-first! (self %pure-cell) (List map word-form-pure (self %forms)))
        ())
      (first (self %pure-cell)))

    ; The compiled kernels against the pure ones: a radix-2 plan and a
    ; Bluestein one each transform the same input under both, and every
    ; byte of the results must agree.
    (method %agrees? (self engine)
      (let ((ok (List map (fn (_ n) (self %agrees-at? n (pair #t engine))) (list 8 5))))
        (if (first ok) (if (first (rest ok)) #t #f) #f)))

    (method %agrees-at? (self n kern)
      (let ((a (self %make n)) (b (self %make n)))
        (a %fill-check!) (b %fill-check!)
        (a %forward-at! (a %addr 're) (a %addr 'im) kern)
        (b %forward-at! (b %addr 're) (b %addr 'im) (pair #f (self %pure)))
        (if (int= (mem-cmp (str->ptr (a %field 're)) (str->ptr (b %field 're)) (int* 8 n)) 0)
          (int= (mem-cmp (str->ptr (a %field 'im)) (str->ptr (b %field 'im)) (int* 8 n)) 0)
          #f)))

    ; --- memory and the lane --------------------------------------------
    ; Everything a transform allocates is owed, in objects, and the plan
    ; collects once the debt passes %window. The window is sha256.x's: its
    ; digest collects every 8 blocks, ~4.4M objects of churn. The costs,
    ; measured by heap counts around each part: a pure kernel step
    ; %step-cost objects, a converted element %elem-cost, a kernel run's
    ; dispatch %run-cost, a planned element %plan-cost, a term of the
    ; definition %term-cost. A pure kernel runs in calls of %window /
    ; %step-cost steps, its debt paid between them. The first figure of
    ; each is arm64's; the second armv7's, where a double is a two-word
    ; Vector: a step there measured 7.7 times arm64's, and 9400 covers a
    ; whole 256- or 512-point transform on its own.
    ;
    ; The lane: a compile measured 1.8 s and a pure step 70 us, so once the
    ; process has run %jit-after pure steps (a compile's worth) the next
    ; kernel call builds the compiled kernels, and a run in progress
    ; carries on in them, since its state is all in its scratch.
    (%window 4400000)
    (%step-cost (if (int= %word-size 8) 1023 9400))
    (%elem-cost (if (int= %word-size 8) 190 280))
    (%run-cost 7000)
    (%plan-cost (if (int= %word-size 8) 1300 1930))
    (%term-cost (if (int= %word-size 8) 2240 3880))
    (%jit-after 25000)
    (%debt-cell (pair 0 ()))
    (%steps-cell (pair 0 ()))
    (%engine-cell (pair () ()))
    (%pure-cell (pair () ()))

    (method %owe! (self k)
      (let ((d (int+ (first (self %debt-cell)) k)))
        (if (int< d (self %window))
          (%set-first! (self %debt-cell) d)
          (do (%set-first! (self %debt-cell) 0) (Heap collect)))))

    ; Run kernel WHICH (1 radix-2, 2 pointwise) over scratch S (a pointer)
    ; to its end. KERN is the kernels to run, or () for the lane's own,
    ; asked again after each pure call. The budget is scratch word 12.
    (method %drive (self kern which s)
      (let ((addr (ptr->int s)) (at (int* 12 %word-size)))
        (def go
          (fn (go ks)
            (let ((b (if (first ks) 1073741823 (int/ (self %window) (self %step-cost)))))
              (ptr-set-word! s at b)
              (let ((r ((if (int= which 1) (first (rest ks)) (first (rest (rest ks)))) addr)))
                (if (first ks) () (self %ran! kern (int- b (ptr-ref-word s at))))
                (if (int= r 0) (go (if (null? kern) (self %kernels) ks)) ())))))
        (go (if (null? kern) (self %kernels) kern))
        (self %owe! (self %run-cost))))

    ; Steps the pure kernels ran: owed, and counted toward the compile.
    (method %ran! (self kern steps)
      (self %owe! (int* steps (self %step-cost)))
      (if (null? kern)
        (let ((t (int+ (first (self %steps-cell)) steps)))
          (%set-first! (self %steps-cell) t)
          (if (int< t (self %jit-after)) () (if (null? (first (self %engine-cell))) (self jit!) ())))
        ()))

    ; --- the kernels, written once --------------------------------------
    ; Slot names stand in the forms for their indices, words first; a double
    ; slot is a double index past the words, so on either word width it
    ; lies beyond them.
    (method %slots (self)
      (list (pair 'RE 0) (pair 'IM 1) (pair 'COS 2) (pair 'SIN 3) (pair 'REV 4) (pair 'N 5)
            (pair 'PHASE 6) (pair 'I 7) (pair 'SIZE 8) (pair 'START 9) (pair 'K 10) (pair 'STEP 11)
            (pair 'BUDGET 12) (pair 'A 13) (pair 'B 14) (pair 'T 15)
            (pair 'OR 0) (pair 'OI 1) (pair 'XR 2) (pair 'XI 3) (pair 'YR 4) (pair 'YI 5)
            (pair 'YS 6) (pair 'CNT 7) (pair 'LEN 8) (pair 'J 9) (pair 'YJ 13)
            (pair 'T0 16) (pair 'ZERO 16) (pair 'TR 17) (pair 'TI 18)))

    (method %fill-slots (self form)
      (match
        ((pair? form) (pair (self %fill-slots (first form)) (self %fill-slots (rest form))))
        ((symbol? form) (let ((e (Assoc entry form (self %slots)))) (if (null? e) form (rest e))))
        (#t form)))

    (method %forms (self)
      (List map (fn (_ f) (self %fill-slots f)) (list (self %radix2-form) (self %pointwise-form))))

    ; The radix-2 transform in place: phase 0 swaps each i with its bit
    ; reversal, phase 1 runs the butterflies, a pass of span SIZE taking
    ; every STEP-th twiddle. Answers 1 when done, 0 when its budget is spent.
    (method %radix2-form (self)
      (lit
        (fn (self s)
          (match
            ((= (%mem-ref s BUDGET) 0) 0)
            ((= (%mem-ref s PHASE) 0)
              (do (if (< (%mem-ref s I) (%mem-ref s N))
                    (do (if (< (%mem-ref s I) (%mem-ref-at (%mem-ref s REV) (%mem-ref s I)))
                          (do (f-set! s T0 (f-ref (%mem-ref s RE) (%mem-ref s I)))
                              (f-set! (%mem-ref s RE) (%mem-ref s I)
                                (f-ref (%mem-ref s RE) (%mem-ref-at (%mem-ref s REV) (%mem-ref s I))))
                              (f-set! (%mem-ref s RE) (%mem-ref-at (%mem-ref s REV) (%mem-ref s I)) (f-ref s T0))
                              (f-set! s T0 (f-ref (%mem-ref s IM) (%mem-ref s I)))
                              (f-set! (%mem-ref s IM) (%mem-ref s I)
                                (f-ref (%mem-ref s IM) (%mem-ref-at (%mem-ref s REV) (%mem-ref s I))))
                              (f-set! (%mem-ref s IM) (%mem-ref-at (%mem-ref s REV) (%mem-ref s I)) (f-ref s T0)))
                          0)
                        (%mem-set! s I (+ (%mem-ref s I) 1)))
                    (%mem-set! s PHASE 1))
                  (%mem-set! s BUDGET (- (%mem-ref s BUDGET) 1))
                  (self s)))
            ((< (%mem-ref s N) (%mem-ref s SIZE)) 1)
            ((< (%mem-ref s START) (%mem-ref s N))
              (match
                ((< (%mem-ref s K) (>> (%mem-ref s SIZE) 1))
                  (do (%mem-set! s A (+ (%mem-ref s START) (%mem-ref s K)))
                      (%mem-set! s B (+ (%mem-ref s A) (>> (%mem-ref s SIZE) 1)))
                      (%mem-set! s T (* (%mem-ref s K) (%mem-ref s STEP)))
                      (f-set! s TR (f- (f* (f-ref (%mem-ref s COS) (%mem-ref s T)) (f-ref (%mem-ref s RE) (%mem-ref s B)))
                                         (f* (f-ref (%mem-ref s SIN) (%mem-ref s T)) (f-ref (%mem-ref s IM) (%mem-ref s B)))))
                      (f-set! s TI (f+ (f* (f-ref (%mem-ref s COS) (%mem-ref s T)) (f-ref (%mem-ref s IM) (%mem-ref s B)))
                                         (f* (f-ref (%mem-ref s SIN) (%mem-ref s T)) (f-ref (%mem-ref s RE) (%mem-ref s B)))))
                      (f-set! (%mem-ref s RE) (%mem-ref s B) (f- (f-ref (%mem-ref s RE) (%mem-ref s A)) (f-ref s TR)))
                      (f-set! (%mem-ref s IM) (%mem-ref s B) (f- (f-ref (%mem-ref s IM) (%mem-ref s A)) (f-ref s TI)))
                      (f-set! (%mem-ref s RE) (%mem-ref s A) (f+ (f-ref (%mem-ref s RE) (%mem-ref s A)) (f-ref s TR)))
                      (f-set! (%mem-ref s IM) (%mem-ref s A) (f+ (f-ref (%mem-ref s IM) (%mem-ref s A)) (f-ref s TI)))
                      (%mem-set! s K (+ (%mem-ref s K) 1))
                      (%mem-set! s BUDGET (- (%mem-ref s BUDGET) 1))
                      (self s)))
                (#t (do (%mem-set! s START (+ (%mem-ref s START) (%mem-ref s SIZE)))
                        (%mem-set! s K 0)
                        (self s)))))
            (#t (do (%mem-set! s SIZE (+ (%mem-ref s SIZE) (%mem-ref s SIZE)))
                    (%mem-set! s STEP (>> (%mem-ref s STEP) 1))
                    (%mem-set! s START 0)
                    (%mem-set! s K 0)
                    (self s)))))))

    ; OUT[j] = X[j] Y[j YS] for j < CNT, then zeros to LEN. OUT may be X.
    ; Answers 1 when done, 0 when its budget is spent.
    (method %pointwise-form (self)
      (lit
        (fn (self s)
          (match
            ((= (%mem-ref s BUDGET) 0) 0)
            ((< (%mem-ref s J) (%mem-ref s CNT))
              (do (%mem-set! s YJ (* (%mem-ref s J) (%mem-ref s YS)))
                  (f-set! s TR (f- (f* (f-ref (%mem-ref s XR) (%mem-ref s J)) (f-ref (%mem-ref s YR) (%mem-ref s YJ)))
                                     (f* (f-ref (%mem-ref s XI) (%mem-ref s J)) (f-ref (%mem-ref s YI) (%mem-ref s YJ)))))
                  (f-set! s TI (f+ (f* (f-ref (%mem-ref s XR) (%mem-ref s J)) (f-ref (%mem-ref s YI) (%mem-ref s YJ)))
                                     (f* (f-ref (%mem-ref s XI) (%mem-ref s J)) (f-ref (%mem-ref s YR) (%mem-ref s YJ)))))
                  (f-set! (%mem-ref s OR) (%mem-ref s J) (f-ref s TR))
                  (f-set! (%mem-ref s OI) (%mem-ref s J) (f-ref s TI))
                  (%mem-set! s J (+ (%mem-ref s J) 1))
                  (%mem-set! s BUDGET (- (%mem-ref s BUDGET) 1))
                  (self s)))
            ((< (%mem-ref s J) (%mem-ref s LEN))
              (do (f-set! (%mem-ref s OR) (%mem-ref s J) (f-ref s ZERO))
                  (f-set! (%mem-ref s OI) (%mem-ref s J) (f-ref s ZERO))
                  (%mem-set! s J (+ (%mem-ref s J) 1))
                  (%mem-set! s BUDGET (- (%mem-ref s BUDGET) 1))
                  (self s)))
            (#t 1)))))

    ; --- doubles in buffers -------------------------------------------------
    ; The double at A + 8I, as the kernels read and write it on this word.
    (%doubles-cell (pair () ()))
    (method %doubles (self)
      (if (null? (first (self %doubles-cell)))
        (%set-first! (self %doubles-cell)
          (pair (word-form-pure (lit (fn (_ a i) (f-ref a i))))
                (word-form-pure (lit (fn (_ a i v) (f-set! a i v))))))
        ())
      (first (self %doubles-cell)))
    ; (bits x): a real number's double bits. A Float's are its payload and
    ; a machine integer's come from float.x's "i->d" stub; anything else
    ; converts.
    (%bits-cell (pair () ()))
    (method %bits (self)
      (if (null? (first (self %bits-cell)))
        (%set-first! (self %bits-cell)
          (let ((i->d (libm-fn (lit %frequency-i->d) "i->d" ())) (int-t (type-of 0)))
            (fn (_ x)
              (match
                ((type? x float) (first x))
                ((type? x int-t) (i->d x))
                (#t (first (float-of x)))))))
        ())
      (first (self %bits-cell)))
    (method %fget (self a i) ((first (self %doubles)) a i))
    (method %fset! (self a i v) ((rest (self %doubles)) a i v))

    (method %buf (self doubles)
      (str-make (int* 8 (if (int< doubles 1) 1 doubles))))
    (method %at (self buf) (ptr->int (str->ptr buf)))
    (method %zeros! (self buf n)
      (let ((a (self %at buf)) (z (first (float-of 0))) (fset (rest (self %doubles))))
        (def go (fn (go i) (if (int< i n) (do (fset a i z) (go (int+ i 1))) ())))
        (go 0)))

    ; --- construction ------------------------------------------------------
    (method %vec (self v)
      (if (Vector vector? v) v (Vector from-list v)))

    (method %pow2? (self n)
      (int= (int& n (int- n 1)) 0))

    (method %make (self n)
      (if (self %pow2? n) (self %radix2-plan n) (self %bluestein-plan n)))

    ; (unit t m) is e^(2 pi i t/m) as (cos . sin), t in [0, m), a closure so
    ; a table's loop pays no dispatch per entry. The angle's quadrant comes
    ; off as a rotation, its remainder r/m of a quarter turn folds at the
    ; octant (r past m/2 reads as m - r with cos and sin exchanged), so the
    ; libm call sees an angle in [0, pi/4] and r = 0 is exact.
    (method %unit (self)
      (let ((z (float-of 0)))
        (fn (_ t m)
          (let ((quad (int/ (int* 4 t) m)))
            (let ((r (int- (int* 4 t) (int* quad m))))
              (let ((fold (int< m (int* 2 r))))
                (let ((a (f-div (f-mul pi (float-of (if fold (int- m r) r)))
                                (float-of (int* 2 m)))))
                  (let ((c (if fold (fsin a) (fcos a))) (s (if fold (fcos a) (fsin a))))
                    (match
                      ((int= quad 0) (pair c s))
                      ((int= quad 1) (pair (f-sub z s) c))
                      ((int= quad 2) (pair (f-sub z c) (f-sub z s)))
                      (#t (pair s (f-sub z c))))))))))))

    ; The scratch with 0.0 at its double 16, the data, and 1/n beside 0.
    (method %base (self n)
      (let ((unit (self %buf 2)) (scr (str-make 256)))
        (self %fset! (self %at unit) 0 (first (f-div (float-of 1) (float-of n))))
        (self %fset! (self %at unit) 1 (first (float-of 0)))
        (self %fset! (self %at scr) 16 (first (float-of 0)))
        (list 'n n 'scr scr 're (self %buf n) 'im (self %buf n) 'unit unit)))

    (method %radix2-plan (self n)
      (let ((half (int>> n 1)) (cs (self %buf (int>> n 1))) (sn (self %buf (int>> n 1)))
            (rev (str-make (int* %word-size (if (int< n 1) 1 n))))
            (unit (self %unit)) (fset (rest (self %doubles))) (z (float-of 0)))
        (let ((ca (self %at cs)) (sa (self %at sn)) (rp (str->ptr rev)))
          (def table
            (fn (go t)
              (if (int< t half)
                (let ((u (unit t n)))
                  (fset ca t (first (first u)))
                  (fset sa t (first (f-sub z (rest u))))
                  (go (int+ t 1)))
                ())))
          (table 0)
          (def bits
            (fn (go i r b)
              (if (int< b n) (go (int>> i 1) (int+ (int* r 2) (int& i 1)) (int* b 2)) r)))
          (def fill
            (fn (go i)
              (if (int< i n)
                (do (ptr-set-word! rp (int* i %word-size) (bits i 0 1)) (go (int+ i 1)))
                ())))
          (fill 0))
        (self %owe! (int* n (self %plan-cost)))
        (new-from self (List append (self %base n) (list 'cos cs 'sin sn 'rev rev 'inner ())))))

    ; Bluestein: jk = (j^2 + k^2 - (k-j)^2)/2, so with the chirp
    ; w[k] = e^(-pi i k^2/n) the transform is X[k] = w[k] (a * b)[k], the
    ; convolution of a[j] = x[j] w[j] with the kernel b[j] = conj(w[|j|]),
    ; wrapped round m >= 2n - 1 points. The plan keeps B, the kernel's
    ; transform, scaled by 1/m for the inverse transform the convolution
    ; ends with. k^2 is taken mod 2n before it becomes an angle, so a long
    ; n keeps its precision.
    (method %bluestein-plan (self n)
      (let ((m (self %pow2-at-least (int- (int* 2 n) 1) 1)))
        (let ((inner (self %radix2-plan m))
              (wre (self %buf n)) (wim (self %buf n)) (bre (self %buf m)) (bim (self %buf m))
              (unit (self %unit)) (fset (rest (self %doubles))) (z (float-of 0)))
          (self %zeros! bre m)
          (self %zeros! bim m)
          (let ((wr (self %at wre)) (wi (self %at wim)) (br (self %at bre)) (bi (self %at bim)))
            (def chirp
              (fn (go k)
                (if (int< k n)
                  (let ((u (unit (int% (int* k k) (int* 2 n)) (int* 2 n))))
                    (fset wr k (first (first u)))
                    (fset wi k (first (f-sub z (rest u))))
                    (fset br k (first (first u)))
                    (fset bi k (first (rest u)))
                    (if (int< 0 k)
                      (do (fset br (int- m k) (first (first u)))
                          (fset bi (int- m k) (first (rest u))))
                      ())
                    (go (int+ k 1)))
                  ())))
            (chirp 0)
            (self %owe! (int* n (self %plan-cost)))
            (inner %radix2-at! br bi ())
            (inner %scale-at! br bi ()))
          (new-from self (List append (self %base n)
                           (list 'inner inner 'wre wre 'wim wim 'bre bre 'bim bim))))))

    (method %pow2-at-least (self n m)
      (if (int< m n) (self %pow2-at-least n (int* m 2)) m))

    ; The definition, O(n^2) in Float arithmetic, sign -1 forward and +1
    ; inverse (then / n).
    (method %direct (self v inverse)
      (let ((n (Vector length v)) (z (float-of 0)) (unit (self %unit)))
        (let ((re (self %reals v)) (im (self %imags v)) (out (Vector make n ())))
          (def term
            (fn (go j k sr si)
              (if (int< j n)
                (let ((u (unit (int% (int* j k) n) n)))
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
                (do (obj-set! out (int+ k 1) (term 0 k z z))
                    (self %owe! (int* n (self %term-cost)))
                    (go (int+ k 1)))
                ())))
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
      (example "((Frequency plan 8) size)" "8"))
    (field 'n))

  (method forward (self (param v VECTOR|LIST "n numbers: Complex values or reals"))
    (doc "The forward transform of v: X[k] = sum v[j] e^(-2 pi i jk/n), unscaled."
      (returns VECTOR "A vector of n Complex values")
      (example "((Frequency plan 2) forward #(1 2))" "#(3.0+0.0i -1.0+0.0i)"))
    (self %load! v)
    (self %forward-at! (self %addr 're) (self %addr 'im) ())
    (self %unload))

  (method inverse (self (param v VECTOR|LIST "n numbers: Complex values or reals"))
    (doc "The inverse transform of v: x[j] = (1/n) sum v[k] e^(2 pi i jk/n)."
      (returns VECTOR "A vector of n Complex values")
      (example "((Frequency plan 2) inverse #(3 -1))" "#(1.0+0.0i 2.0+0.0i)"))
    (self %load! v)
    (self %inverse-at! ())
    (self %unload))

  (method forward! (self (param re VECTOR "n floats, the real parts") (param im VECTOR "n floats, the imaginary parts"))
    (doc "The forward transform in place on split form: re and im are overwritten with the real and imaginary parts of X. The vectors are reused, so a stream of transforms keeps its buffers."
      (returns Frequency "self, for chaining")
      (example "(let ((re (Vector of 1.0 2.0)) (im (Vector of 0.0 0.0))) ((Frequency plan 2) forward! re im) re)" "#(3.0 -1.0)"))
    (self %split-in! re im)
    (self %forward-at! (self %addr 're) (self %addr 'im) ())
    (self %split-out! re im)
    self)

  (method inverse! (self (param re VECTOR "n floats, the real parts") (param im VECTOR "n floats, the imaginary parts"))
    (doc "The inverse transform in place on split form, scaled by 1/n."
      (returns Frequency "self, for chaining")
      (example "(let ((re (Vector of 3.0 -1.0)) (im (Vector of 0.0 0.0))) ((Frequency plan 2) inverse! re im) re)" "#(1.0 2.0)"))
    (self %split-in! re im)
    (self %inverse-at! ())
    (self %split-out! re im)
    self)

  (method %field (self name) (field name))
  (method %addr (self name) (Frequency %at (field name)))

  ; --- converting in and out ------------------------------------------------
  ; The doors are fetched once a call: a class dispatch per element would
  ; cost more than the element.
  (method %load! (self v)
    (let ((w (Frequency %vec v)) (n (field 'n)) (re (self %addr 're)) (im (self %addr 'im))
          (ct (Complex type)) (fset (rest (Frequency %doubles))) (zero (first (float-of 0))))
      (if (int= (Vector length w) n) ()
        (Err raise 'value "Frequency: input length is not the plan's" (Vector length w)))
      (def bits (Frequency %bits))
      (def go
        (fn (go i)
          (if (int< i n)
            (let ((x (obj-ref w (int+ i 1))))
              (if (type? x ct)
                (do (fset re i (bits (Complex real-part x)))
                    (fset im i (bits (Complex imag-part x))))
                (do (fset re i (bits x))
                    (fset im i zero)))
              (go (int+ i 1)))
            ())))
      (go 0)
      (Frequency %owe! (int* n (Frequency %elem-cost)))))

  (method %unload (self)
    (let ((n (field 'n)) (re (self %addr 're)) (im (self %addr 'im)) (fget (first (Frequency %doubles))))
      (Frequency %owe! (int* n (Frequency %elem-cost)))
      (Vector build n
        (fn (_ k) (make-complex (type-make-instance float (fget re k)) (type-make-instance float (fget im k)))))))

  (method %split-in! (self re im)
    (let ((n (field 'n)) (ra (self %addr 're)) (ia (self %addr 'im)) (fset (rest (Frequency %doubles))))
      (if (if (int= (Vector length re) n) (int= (Vector length im) n) #f) ()
        (Err raise 'value "Frequency: split vectors must both have the plan's length" n))
      (def bits (Frequency %bits))
      (def go
        (fn (go i)
          (if (int< i n)
            (do (fset ra i (bits (obj-ref re (int+ i 1))))
                (fset ia i (bits (obj-ref im (int+ i 1))))
                (go (int+ i 1)))
            ())))
      (go 0)))

  (method %split-out! (self re im)
    (let ((n (field 'n)) (ra (self %addr 're)) (ia (self %addr 'im)) (fget (first (Frequency %doubles))))
      (def go
        (fn (go i)
          (if (int< i n)
            (do (obj-set! re (int+ i 1) (type-make-instance float (fget ra i)))
                (obj-set! im (int+ i 1) (type-make-instance float (fget ia i)))
                (go (int+ i 1)))
            ())))
      (go 0)
      (Frequency %owe! (int* n (Frequency %elem-cost)))))

  (method %fill-check! (self)
    (let ((n (field 'n)) (re (self %addr 're)) (im (self %addr 'im)) (fset (rest (Frequency %doubles))))
      (def go
        (fn (go i)
          (if (int< i n)
            (do (fset re i (first (float-of (int- (int* i i) 3))))
                (fset im i (first (f-div (float-of (int- 2 i)) (float-of 3))))
                (go (int+ i 1)))
            ())))
      (go 0)))

  ; --- the algorithms, on addresses ---------------------------------------
  ; Forward, unscaled, in place on the n doubles at RE and IM.
  (method %forward-at! (self re im kern)
    (if (null? (field 'inner))
      (self %radix2-at! re im kern)
      (self %bluestein-at! re im kern)))

  ; The inverse: the forward transform with the parts swapped, then 1/n.
  (method %inverse-at! (self kern)
    (self %forward-at! (self %addr 'im) (self %addr 're) kern)
    (self %scale-at! (self %addr 're) (self %addr 'im) kern))

  (method %scale-at! (self re im kern)
    (let ((u (self %addr 'unit)) (n (field 'n)))
      (self %pointwise! kern re im re im u (int+ u 8) 0 n n)))

  ; The scratch's first words, from word 0, one value each.
  (method %words! (self vs)
    (let ((s (str->ptr (field 'scr))))
      (def go
        (fn (go i vs)
          (if (null? vs) s
            (do (ptr-set-word! s (int* i %word-size) (first vs)) (go (int+ i 1) (rest vs))))))
      (go 0 vs)))

  (method %radix2-at! (self re im kern)
    (let ((n (field 'n)))
      (Frequency %drive kern 1
        (self %words! (list re im (ptr->int (str->ptr (field 'cos))) (ptr->int (str->ptr (field 'sin)))
                            (ptr->int (str->ptr (field 'rev))) n 0 0 2 0 0 (int>> n 1))))))

  ; OUT = X Y[j ys] over cnt, zeros to len. The zeros are the plan's
  ; double 16, written when it was made: no radix-2 run shares this
  ; scratch with a pointwise one that reads them.
  (method %pointwise! (self kern ore oim xr xi yr yi ys cnt len)
    (Frequency %drive kern 2 (self %words! (list ore oim xr xi yr yi ys cnt len 0))))

  (method %bluestein-at! (self re im kern)
    (let ((n (field 'n)) (inner (field 'inner))
          (wre (self %addr 'wre)) (wim (self %addr 'wim)) (bre (self %addr 'bre)) (bim (self %addr 'bim)))
      (let ((m (inner size)) (ar (inner %addr 're)) (ai (inner %addr 'im)))
        (self %pointwise! kern ar ai re im wre wim 1 n m)
        (inner %radix2-at! ar ai kern)
        (self %pointwise! kern ar ai ar ai bre bim 1 m m)
        (inner %radix2-at! ai ar kern)
        (self %pointwise! kern re im ar ai wre wim 1 n n)))))

(doc (provide x/num/frequency Frequency)
  (example "(Frequency fft #(1 2 3 4))" "#(10.0+0.0i -2.0+2.0i -2.0+0.0i -2.0-2.0i)")
  (example "((Frequency plan 3) size)" "3")
  "The discrete Fourier transform: reusable plans, O(n log n) for every length, on compiled kernels where the JIT can build them.")
