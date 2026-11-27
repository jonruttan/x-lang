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
; Float. Seven kernels do all the arithmetic, each written once as a word form
; (x/tool/word-form): %radix2, the bit reversal and every butterfly pass of a
; power-of-two transform, and %pointwise, a complex multiply of one buffer
; by another that serves Bluestein's three steps and the inverse's 1/n. The
; inverse is the forward transform with real and imaginary parts swapped
; (swap(DFT(swap x)) is n times the inverse), so no kernel negates.
;
; spectrum! takes sound straight from memory, as a mixer's block of signed
; 16-bit stereo frames: %frames reads a channel (or both added) through the
; plan's Hann window into the data, and after the forward transform %bands
; sums each band's power, re^2 + im^2 over a range of bins. The bands are
; spaced evenly in log frequency from bin 1 (bin 0, the constant, is left
; out) to bin n/2. Only the bands become Floats, so a transform a mixer
; block costs the kernels and one call.
;
; A convolver is a plan of twice a block's frames holding an impulse cut
; into pieces of a block, each transformed once: uniformly partitioned
; convolution. convolve! takes a block of one channel of a stereo word
; buffer, as a mixer mixes into: %words reads it into the next slot of a
; ring of the last pieces' worth of blocks, transformed there; %mac sums
; each slot's spectrum times its piece's; the inverse transform (the
; forward one with the parts swapped) gives the result times n; and
; %overlap adds its first half and the last block's second half into the
; buffer at a gain, rounded, and keeps the second half for the next block.
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
(import x/num/float Float float float-of f-add f-sub f-mul f-div fsin fcos pi libm-fn)
(import x/num/complex Complex make-complex)
(import x/tool/word-form word-form-pure)
(import x/tool/compiled)
(import x/core/doors int+ int- int* int/ int% int< int= int& int>> obj-ref obj-set!
  mem-cmp mem-set int->ptr ptr->int ptr-ref-word ptr-set! ptr-set-word! str->ptr str-make type-make-instance type-of type?)

(def-class Frequency ()
  (doc "A discrete Fourier transform plan for one length n: forward and inverse transforms in O(n log n) for every n (radix-2 for a power of two, Bluestein's algorithm otherwise). Make one with (Frequency plan n) and reuse it; (Frequency fft v) makes one per call. The plan keeps its tables and data in buffers of its own, its kernels run compiled where the JIT can build them, and it collects its own garbage."
    (known-as "Fourier transform" "FFT" "DFT")
    (note "The forward transform is unscaled, X[k] = sum x[j] e^(-2 pi i jk/n); the inverse divides by n, so (p inverse (p forward v)) is v to rounding.")
    (example "(Frequency fft #(1 2 3 4))" "#(10.0+0.0i -2.0+2.0i -2.0+0.0i -2.0-2.0i)")
    (see plan) (see forward) (see forward!) (see spectrum!) (see convolver) (see jit!) (see dft))

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
  win     ; spectrum!: the Hann window over wlen frames, doubles, else ()
  wlen
  edges   ; spectrum!: the nb bands' bin edges, nb + 1 words, else ()
  nb
  bands   ; spectrum!: the bands' power, nb doubles
  blk     ; convolver: frames a block, n/2, else ()
  parts   ; convolver: the impulse's pieces of blk frames
  head    ; convolver: the ring's slot the next block's spectrum takes
  hre     ; convolver: each piece's transform, parts spectra of n doubles
  him
  xre     ; convolver: the ring of the last parts blocks' transforms
  xim
  ov      ; convolver: the half of the last block's result still to come, blk doubles

  (static
    ; --- the plan ---------------------------------------------------------
    (method plan (self (param n INTEGER "Transform length, at least 1"))
      (doc "A plan for transforms of length n. A power of two runs radix-2; any other n runs Bluestein's algorithm on a power-of-two plan of at least 2n-1 points."
        (returns Frequency "A reusable plan")
        (example "((Frequency plan 6) size)" "6"))
      (if (int< n 1) (Err raise 'value "Frequency plan: n must be at least 1" n) ())
      (self %make n))

    (method convolver (self (param impulse STRING|INTEGER "The impulse response, one machine word a frame: a region or its address")
                            (param count INTEGER "The impulse's frames, at least 1")
                            (param block INTEGER "Frames a block, a power of two: what each convolve! takes"))
      (doc "A convolver: a plan of 2 BLOCK points holding the impulse cut into pieces of BLOCK frames, each transformed once, for uniformly partitioned convolution. convolve! then takes one channel of a stereo word buffer a block at a time and adds in the block convolved with the impulse, the tail running on through the blocks after it. It adds no latency of its own: a block's convolution starts in that block. The impulse is read when the convolver is made and not after; twin makes the convolver for a second channel over the same pieces."
        (returns Frequency "A convolver")
        (sample "(Frequency convolver ir 88200 1024)" "a convolver of a 2 s impulse at 44100 Hz, 87 pieces of 1024 frames"))
      (if (if (int< block 1) #t (not (self %pow2? block)))
        (Err raise 'value "Frequency convolver: block must be a power of two" block) ())
      (if (int< count 1) (Err raise 'value "Frequency convolver: count must be at least 1" count) ())
      (self %convolver-of (if (type? impulse (type-of 0)) impulse (ptr->int (str->ptr impulse))) count block ()))

    (method fft(self (param v VECTOR|LIST "Numbers: Complex values or reals"))
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

    ; The kernels the plans run, (COMPILED? RADIX2 POINTWISE FRAMES BANDS
    ; WORDS MAC OVERLAP): Compiled installs a version into the lane cell,
    ; the pure one before a state image is written, so no compiled code
    ; outlives its process.
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
    ; Bluestein one each transform the same input under both, and a
    ; radix-2 plan takes the same frames to bands under both; every byte of
    ; the results must agree.
    (method %agrees? (self engine)
      (let ((ok (List map (fn (_ n) (self %agrees-at? n (pair #t engine))) (list 8 5))))
        (if (if (first ok) (first (rest ok)) #f)
          (if (self %agrees-spectrum? (pair #t engine)) (self %agrees-convolver? (pair #t engine)) #f)
          #f)))

    ; A convolver of four-frame blocks over a six-word impulse, two pieces,
    ; takes two blocks of one channel of eight stereo words: the words
    ; after both and the overlap compared.
    (method %agrees-convolver? (self kern)
      (def run
        (fn (_ k)
          (let ((imp (str-make (int* 6 %word-size))) (mix (str-make (int* 8 %word-size))))
            (def put
              (fn (go b i n f)
                (if (int< i n) (do (ptr-set-word! (str->ptr b) (int* i %word-size) (f i)) (go b (int+ i 1) n f)) ())))
            (put imp 0 6 (fn (_ i) (int- (int* i 37) 100)))
            (put mix 0 8 (fn (_ i) (int- (int* i 1234) 5000)))
            (let ((c (self %convolver-of (ptr->int (str->ptr imp)) 6 4 k)))
              (c %convolve-at! (ptr->int (str->ptr mix)) 2 0 1 k)
              (c %convolve-at! (ptr->int (str->ptr mix)) 2 0 1 k)
              (pair mix c)))))
      (let ((a (run kern)) (b (run (pair #f (self %pure)))))
        (if (int= (mem-cmp (str->ptr (first a)) (str->ptr (first b)) (int* 8 %word-size)) 0)
          (int= (mem-cmp (str->ptr ((rest a) %field 'ov)) (str->ptr ((rest b) %field 'ov)) 32) 0)
          #f)))

    ; Eight frames whose samples cover both signs and both bytes, as both
    ; channels added, into three bands: the data and the bands compared.
    (method %agrees-spectrum? (self kern)
      (let ((a (self %make 8)) (b (self %make 8)) (fr (str-make 32)))
        (def fill
          (fn (go i)
            (if (int< i 16)
              (let ((v (int& (int- (int* i 4099) 30000) 65535)))
                (ptr-set! (str->ptr fr) (int* 2 i) (int& v 255) 1)
                (ptr-set! (str->ptr fr) (int+ (int* 2 i) 1) (int>> v 8) 1)
                (go (int+ i 1)))
              ())))
        (fill 0)
        (a %spectrum-at! (ptr->int (str->ptr fr)) 8 0 1 3 kern)
        (b %spectrum-at! (ptr->int (str->ptr fr)) 8 0 1 3 (pair #f (self %pure)))
        (if (int= (mem-cmp (str->ptr (a %field 're)) (str->ptr (b %field 're)) 64) 0)
          (if (int= (mem-cmp (str->ptr (a %field 'im)) (str->ptr (b %field 'im)) 64) 0)
            (int= (mem-cmp (str->ptr (a %field 'bands)) (str->ptr (b %field 'bands)) 24) 0)
            #f)
          #f)))

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
    ; definition %term-cost, a convolver's block %block-cost and its piece
    ; made %piece-cost. A pure kernel runs in calls of %window /
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
    (%block-cost 14000)
    (%piece-cost 1410)
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

    ; Run kernel WHICH (1 radix-2, 2 pointwise, 3 frames, 4 bands, 5 words,
    ; 6 mac, 7 overlap) over scratch S (a pointer) to its end. KERN is the
    ; kernels to run, or () for the lane's own, asked again after each pure
    ; call. The budget is scratch word 12.
    (method %drive (self kern which s)
      (let ((addr (ptr->int s)) (at (int* 12 %word-size)))
        (def go
          (fn (go ks)
            (let ((b (if (first ks) 1073741823 (int/ (self %window) (self %step-cost)))))
              (ptr-set-word! s at b)
              (let ((r ((List ref which ks) addr)))
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
            (pair 'FA 2) (pair 'WIN 3) (pair 'CHAN 4) (pair 'BOTH 5) (pair 'FV 13) (pair 'FW 14)
            (pair 'EDGES 2) (pair 'OUT 3)
            (pair 'WA 2) (pair 'STRIDE 3) (pair 'OFF 4)
            (pair 'HR 4) (pair 'HI 5) (pair 'MN 6) (pair 'PARTS 7) (pair 'FULL 8) (pair 'P 9) (pair 'SLOT 11)
            (pair 'XO 13) (pair 'HO 14) (pair 'MK 15)
            (pair 'OV 2) (pair 'MA 3) (pair 'MS 4) (pair 'MO 5) (pair 'BLK 7) (pair 'MV 13)
            (pair 'ZERO 16) (pair 'TR 17) (pair 'TI 18) (pair 'GAIN 19) (pair 'HALF 20) (pair 'T0 21)))

    (method %fill-slots (self form)
      (match
        ((pair? form) (pair (self %fill-slots (first form)) (self %fill-slots (rest form))))
        ((symbol? form) (let ((e (Assoc entry form (self %slots)))) (if (null? e) form (rest e))))
        (#t form)))

    (method %forms (self)
      (List map (fn (_ f) (self %fill-slots f))
        (list (self %radix2-form) (self %pointwise-form) (self %frames-form) (self %bands-form)
              (self %words-form) (self %mac-form) (self %overlap-form))))

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

    ; RE[j] = WIN[j] times frame j's sample for j < CNT, IM[j] = 0, then
    ; zeros to LEN. Frames are 4 bytes from FA, two signed 16-bit
    ; little-endian samples; the sample read is CHAN bytes in (0 left, 2
    ; right), with the right one added when BOTH is 1. Answers 1 when done,
    ; 0 when its budget is spent.
    (method %frames-form (self)
      (lit
        (fn (self s)
          (match
            ((= (%mem-ref s BUDGET) 0) 0)
            ((< (%mem-ref s J) (%mem-ref s CNT))
              (do (%mem-set! s FV (+ (%mem-byte-ref-at (%mem-ref s FA) (+ (<< (%mem-ref s J) 2) (%mem-ref s CHAN)))
                                     (<< (%mem-byte-ref-at (%mem-ref s FA) (+ (+ (<< (%mem-ref s J) 2) (%mem-ref s CHAN)) 1)) 8)))
                  (if (< 32767 (%mem-ref s FV)) (%mem-set! s FV (- (%mem-ref s FV) 65536)) 0)
                  (%mem-set! s FW (+ (%mem-byte-ref-at (%mem-ref s FA) (+ (<< (%mem-ref s J) 2) 2))
                                     (<< (%mem-byte-ref-at (%mem-ref s FA) (+ (<< (%mem-ref s J) 2) 3)) 8)))
                  (if (< 32767 (%mem-ref s FW)) (%mem-set! s FW (- (%mem-ref s FW) 65536)) 0)
                  (%mem-set! s FV (+ (%mem-ref s FV) (* (%mem-ref s FW) (%mem-ref s BOTH))))
                  (f-set! (%mem-ref s RE) (%mem-ref s J) (f* (i->f (%mem-ref s FV)) (f-ref (%mem-ref s WIN) (%mem-ref s J))))
                  (f-set! (%mem-ref s IM) (%mem-ref s J) (f-ref s ZERO))
                  (%mem-set! s J (+ (%mem-ref s J) 1))
                  (%mem-set! s BUDGET (- (%mem-ref s BUDGET) 1))
                  (self s)))
            ((< (%mem-ref s J) (%mem-ref s LEN))
              (do (f-set! (%mem-ref s RE) (%mem-ref s J) (f-ref s ZERO))
                  (f-set! (%mem-ref s IM) (%mem-ref s J) (f-ref s ZERO))
                  (%mem-set! s J (+ (%mem-ref s J) 1))
                  (%mem-set! s BUDGET (- (%mem-ref s BUDGET) 1))
                  (self s)))
            (#t 1)))))

    ; OUT[j] = the sum of RE[k]^2 + IM[k]^2 over EDGES[j] <= k < EDGES[j+1],
    ; for the CNT bands; K starts at EDGES[0] and TR at 0. Answers 1 when
    ; done, 0 when its budget is spent.
    (method %bands-form (self)
      (lit
        (fn (self s)
          (match
            ((= (%mem-ref s BUDGET) 0) 0)
            ((< (%mem-ref s J) (%mem-ref s CNT))
              (if (< (%mem-ref s K) (%mem-ref-at (%mem-ref s EDGES) (+ (%mem-ref s J) 1)))
                (do (f-set! s TR (f+ (f-ref s TR)
                                     (f+ (f* (f-ref (%mem-ref s RE) (%mem-ref s K)) (f-ref (%mem-ref s RE) (%mem-ref s K)))
                                         (f* (f-ref (%mem-ref s IM) (%mem-ref s K)) (f-ref (%mem-ref s IM) (%mem-ref s K))))))
                    (%mem-set! s K (+ (%mem-ref s K) 1))
                    (%mem-set! s BUDGET (- (%mem-ref s BUDGET) 1))
                    (self s))
                (do (f-set! (%mem-ref s OUT) (%mem-ref s J) (f-ref s TR))
                    (f-set! s TR (f-ref s ZERO))
                    (%mem-set! s J (+ (%mem-ref s J) 1))
                    (%mem-set! s BUDGET (- (%mem-ref s BUDGET) 1))
                    (self s))))
            (#t 1)))))

    ; RE[j] = the word at WA + (STRIDE j + OFF) words as a double, IM[j] = 0,
    ; for j < CNT, then zeros to LEN: one channel of a mixer's stereo words,
    ; or an impulse's piece. Answers 1 when done, 0 when its budget is
    ; spent.
    (method %words-form (self)
      (lit
        (fn (self s)
          (match
            ((= (%mem-ref s BUDGET) 0) 0)
            ((< (%mem-ref s J) (%mem-ref s CNT))
              (do (f-set! (%mem-ref s RE) (%mem-ref s J)
                    (i->f (%mem-ref-at (%mem-ref s WA) (+ (* (%mem-ref s J) (%mem-ref s STRIDE)) (%mem-ref s OFF)))))
                  (f-set! (%mem-ref s IM) (%mem-ref s J) (f-ref s ZERO))
                  (%mem-set! s J (+ (%mem-ref s J) 1))
                  (%mem-set! s BUDGET (- (%mem-ref s BUDGET) 1))
                  (self s)))
            ((< (%mem-ref s J) (%mem-ref s LEN))
              (do (f-set! (%mem-ref s RE) (%mem-ref s J) (f-ref s ZERO))
                  (f-set! (%mem-ref s IM) (%mem-ref s J) (f-ref s ZERO))
                  (%mem-set! s J (+ (%mem-ref s J) 1))
                  (%mem-set! s BUDGET (- (%mem-ref s BUDGET) 1))
                  (self s)))
            (#t 1)))))

    ; OUT = the sum over pieces P < PARTS of the ring's spectrum at SLOT
    ; times piece P's: SLOT starts at the newest block's and steps back a
    ; block a piece, round the ring of PARTS. The ring's spectra are XR and
    ; XI, the pieces' HR and HI, both PARTS spectra of FULL points end to
    ; end. Piece 0 sets OUT and the rest add to it. Every spectrum is of
    ; real data, so only bins below MN, FULL/2 + 1, are summed; bins MK =
    ; MN on are then the conjugates of FULL - MK's. Answers 1 when done, 0
    ; when its budget is spent.
    (method %mac-form (self)
      (lit
        (fn (self s)
          (match
            ((= (%mem-ref s BUDGET) 0) 0)
            ((< (%mem-ref s P) (%mem-ref s PARTS))
              (if (< (%mem-ref s K) (%mem-ref s MN))
                (do (%mem-set! s XO (+ (* (%mem-ref s SLOT) (%mem-ref s FULL)) (%mem-ref s K)))
                    (%mem-set! s HO (+ (* (%mem-ref s P) (%mem-ref s FULL)) (%mem-ref s K)))
                    (f-set! s TR (f- (f* (f-ref (%mem-ref s XR) (%mem-ref s XO)) (f-ref (%mem-ref s HR) (%mem-ref s HO)))
                                     (f* (f-ref (%mem-ref s XI) (%mem-ref s XO)) (f-ref (%mem-ref s HI) (%mem-ref s HO)))))
                    (f-set! s TI (f+ (f* (f-ref (%mem-ref s XR) (%mem-ref s XO)) (f-ref (%mem-ref s HI) (%mem-ref s HO)))
                                     (f* (f-ref (%mem-ref s XI) (%mem-ref s XO)) (f-ref (%mem-ref s HR) (%mem-ref s HO)))))
                    (if (= (%mem-ref s P) 0)
                      (do (f-set! (%mem-ref s OR) (%mem-ref s K) (f-ref s TR))
                          (f-set! (%mem-ref s OI) (%mem-ref s K) (f-ref s TI)))
                      (do (f-set! (%mem-ref s OR) (%mem-ref s K) (f+ (f-ref (%mem-ref s OR) (%mem-ref s K)) (f-ref s TR)))
                          (f-set! (%mem-ref s OI) (%mem-ref s K) (f+ (f-ref (%mem-ref s OI) (%mem-ref s K)) (f-ref s TI)))))
                    (%mem-set! s K (+ (%mem-ref s K) 1))
                    (%mem-set! s BUDGET (- (%mem-ref s BUDGET) 1))
                    (self s))
                (do (%mem-set! s P (+ (%mem-ref s P) 1))
                    (%mem-set! s K 0)
                    (if (= (%mem-ref s SLOT) 0)
                      (%mem-set! s SLOT (- (%mem-ref s PARTS) 1))
                      (%mem-set! s SLOT (- (%mem-ref s SLOT) 1)))
                    (self s))))
            ((< (%mem-ref s MK) (%mem-ref s FULL))
              (do (f-set! (%mem-ref s OR) (%mem-ref s MK) (f-ref (%mem-ref s OR) (- (%mem-ref s FULL) (%mem-ref s MK))))
                  (f-set! (%mem-ref s OI) (%mem-ref s MK)
                    (f- (f-ref s ZERO) (f-ref (%mem-ref s OI) (- (%mem-ref s FULL) (%mem-ref s MK)))))
                  (%mem-set! s MK (+ (%mem-ref s MK) 1))
                  (%mem-set! s BUDGET (- (%mem-ref s BUDGET) 1))
                  (self s)))
            (#t 1)))))

    ; For j < BLK: (RE[j] + OV[j]) GAIN, rounded half away from zero, added
    ; into the word at MA + (MS j + MO) words, and OV[j] = RE[j + BLK], the
    ; half the next block adds. Answers 1 when done, 0 when its budget is
    ; spent.
    (method %overlap-form (self)
      (lit
        (fn (self s)
          (match
            ((= (%mem-ref s BUDGET) 0) 0)
            ((< (%mem-ref s J) (%mem-ref s BLK))
              (do (f-set! s TR (f* (f+ (f-ref (%mem-ref s RE) (%mem-ref s J)) (f-ref (%mem-ref s OV) (%mem-ref s J)))
                                   (f-ref s GAIN)))
                  (if (f< (f-ref s TR) (f-ref s ZERO))
                    (f-set! s TR (f- (f-ref s TR) (f-ref s HALF)))
                    (f-set! s TR (f+ (f-ref s TR) (f-ref s HALF))))
                  (%mem-set! s MV (+ (* (%mem-ref s J) (%mem-ref s MS)) (%mem-ref s MO)))
                  (%mem-set-at! (%mem-ref s MA) (%mem-ref s MV)
                    (+ (%mem-ref-at (%mem-ref s MA) (%mem-ref s MV)) (f->i (f-ref s TR))))
                  (f-set! (%mem-ref s OV) (%mem-ref s J) (f-ref (%mem-ref s RE) (+ (%mem-ref s J) (%mem-ref s BLK))))
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

    ; A convolver over COUNT words at IA in pieces of BLK frames, its
    ; kernels KERN.
    (method %convolver-of (self ia count blk kern)
      (let ((c (self %radix2-plan (int* 2 blk))))
        (c %convolver! ia count blk kern)
        c))

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

  (method spectrum! (self (param frames STRING|INTEGER "Signed 16-bit little-endian stereo frames, left then right: a region, as (Mixer block! m) answers, or its address")
                          (param count INTEGER "Frames to read, 1 to n; fewer than n are padded with zeros")
                          (param channel SYMBOL "left, right, or both, the two added")
                          (param out VECTOR "1 to n/2 elements, one a band: overwritten"))
    (doc "The power of the sound in FRAMES, band by band, into OUT: COUNT frames of CHANNEL through a Hann window of COUNT points, the forward transform, and for each band the sum of re^2 + im^2 over its bins, a Float. The bands are spaced evenly in log frequency from bin 1 to bin n/2, at least one bin each; bin 0, the constant, is left out. The frames are read in place and only the bands become Floats, so a plan can take every block of a mixer as it plays. For decibels, 10 log10 of a band."
      (returns VECTOR "out")
      (sample "((Frequency plan 2048) spectrum! (Mixer block! m) 1024 'both (Vector make 64 ()))" "64 Floats, the bands' power, lowest band first"))
    (let ((n (field 'n)) (nb (Vector length out)))
      (if (if (int< count 1) #t (int< n count))
        (Err raise 'value "Frequency spectrum!: count must be 1 to the plan's length" count) ())
      (if (if (int< nb 1) #t (int< (int>> n 1) nb))
        (Err raise 'value "Frequency spectrum!: out must have 1 to n/2 elements" nb) ())
      (let ((chan (match ((eq? channel 'left) 0) ((eq? channel 'right) 2) ((eq? channel 'both) 0)
                         (#t (Err raise 'value "Frequency spectrum!: channel must be left, right or both" channel))))
            (fa (if (type? frames (type-of 0)) frames (ptr->int (str->ptr frames)))))
        (self %spectrum-run! fa count chan (if (eq? channel 'both) 1 0) nb)
        ; On an 8-byte word a double's bits are the word, read by the door;
        ; on a 4-byte one through the pure f-ref.
        (let ((ba (ptr->int (str->ptr (field 'bands))))
              (bits (if (int= %word-size 8)
                      (fn (_ a i) (ptr-ref-word (int->ptr a) (int* 8 i)))
                      (first (Frequency %doubles)))))
          (def go
            (fn (go i)
              (if (int< i nb)
                (do (obj-set! out (int+ i 1) (type-make-instance float (bits ba i))) (go (int+ i 1)))
                ())))
          (go 0))
        (Frequency %owe! (int* nb (Frequency %elem-cost)))
        out)))

  ; COUNT frames at address FA into the data (CHAN and BOTH as %frames
  ; takes them), transformed, and summed into NB bands. With the lane
  ; compiled and a radix-2 plan, the three kernels are called straight,
  ; their budget unbounded: %drive's dispatch measured more than the
  ; kernels at 2048 points. Otherwise every kernel runs through %drive.
  (method %spectrum-run! (self fa count chan both nb)
    (let ((ks (Frequency %kernels)))
      (if (if (first ks) (null? (field 'inner)) #f)
        (let ((re (ptr->int (str->ptr (field 're)))) (im (ptr->int (str->ptr (field 'im)))) (big 1073741823))
          (self %window! count)
          (self %edges! nb)
          (let ((s (ptr->int (self %frames-words fa count chan both big))))
            ((List ref 3 ks) s)
            (self %words! (self %radix2-words re im big))
            ((List ref 1 ks) s)
            (Frequency %fset! s 17 (first (float-of 0)))
            (self %words! (self %bands-words nb big))
            ((List ref 4 ks) s))
          (Frequency %owe! (int* 3 (Frequency %run-cost))))
        (self %spectrum-at! fa count chan both nb ()))))

  (method %spectrum-at! (self fa count chan both nb kern)
    (let ((re (self %addr 're)) (im (self %addr 'im)))
      (self %window! count)
      (self %edges! nb)
      (Frequency %drive kern 3 (self %frames-words fa count chan both 0))
      (self %forward-at! re im kern)
      (Frequency %fset! (self %addr 'scr) 17 (first (float-of 0)))
      (Frequency %drive kern 4 (self %words! (self %bands-words nb 0)))))

  ; The frames and bands kernels' scratch words, written for %frames and
  ; listed for %bands, the budget BUDGET.
  ; A field's address read through the doors: %addr is a class dispatch,
  ; which these run once a block.
  (method %frames-words (self fa count chan both budget)
    (self %words! (list (ptr->int (str->ptr (field 're))) (ptr->int (str->ptr (field 'im))) fa
                        (ptr->int (str->ptr (field 'win))) chan both 0 count (field 'n) 0 0 0 budget 0 0)))
  (method %bands-words (self nb budget)
    (list (ptr->int (str->ptr (field 're))) (ptr->int (str->ptr (field 'im))) (ptr->int (str->ptr (field 'edges)))
          (ptr->int (str->ptr (field 'bands))) 0 0 0 nb 0 0 1 0 budget))

  ; The Hann window over COUNT frames, 1/2 - 1/2 cos(2 pi j/COUNT), made
  ; when the count changes.
  (method %window! (self count)
    (if (if (null? (field 'win)) #f (int= (field 'wlen) count)) ()
      (let ((buf (Frequency %buf count)) (unit (Frequency %unit)) (fset (rest (Frequency %doubles)))
            (half (f-div (float-of 1) (float-of 2))))
        (let ((a (Frequency %at buf)))
          (def go
            (fn (go j)
              (if (int< j count)
                (do (fset a j (first (f-sub half (f-mul half (first (unit j count)))))) (go (int+ j 1)))
                ())))
          (go 0))
        (Frequency %owe! (int* count (Frequency %plan-cost)))
        (set-field! 'win buf)
        (set-field! 'wlen count))))

  ; NB bands' edges, NB + 1 words: band b is bins [e(b), e(b+1)). With
  ; h = n/2 + 1, e(0) is 1, e(NB) is h, and e(b) between is the floor of
  ; h^(b/NB), at least one past e(b-1) and room left for a bin a band
  ; after it. Made when the count changes, with the bands' doubles.
  (method %edges! (self nb)
    (if (if (null? (field 'edges)) #f (int= (field 'nb) nb)) ()
      (let ((h (int+ (int>> (field 'n) 1) 1)) (buf (str-make (int* %word-size (int+ nb 1)))))
        (let ((p (str->ptr buf)))
          (ptr-set-word! p 0 1)
          (def go
            (fn (go b prev)
              (if (int< b nb)
                (let ((g (Float ->int (Float pow (float-of h) (f-div (float-of b) (float-of nb))))))
                  (let ((e ((fn (_ e cap) (if (int< cap e) cap e))
                            (if (int< g (int+ prev 1)) (int+ prev 1) g) (int- h (int- nb b)))))
                    (ptr-set-word! p (int* b %word-size) e)
                    (go (int+ b 1) e)))
                ())))
          (go 1 1)
          (ptr-set-word! p (int* nb %word-size) h))
        (set-field! 'edges buf)
        (set-field! 'nb nb)
        (set-field! 'bands (Frequency %buf nb)))))

  (method convolve! (self (param mix STRING|INTEGER "Machine words, as a mixer mixes into: a region or its address")
                          (param stride INTEGER "Words from one frame's sample to the next's, at least 1: 2 for a stereo buffer")
                          (param offset INTEGER "The channel's word in a frame, from 0: 0 left and 1 right in a stereo buffer")
                          (param gain NUMBER "What the convolved block is scaled by before it is added"))
    (doc "One block through the convolver: the block's frames of the channel at OFFSET, every STRIDE words from MIX, convolved with the impulse, scaled by GAIN, rounded, and added into the same words. A block's convolution runs past its end; the convolver keeps that and adds it to the blocks that follow, so a stream of blocks gets the stream convolved. Only the words read are written. The doubles are the convolver's own; the buffer stays integers."
      (returns Frequency "self")
      (sample "(c convolve! mix 2 0 (/ 3 10))" "the left channel of a 1024-frame stereo mix with 30% of the room added"))
    (if (null? (field 'blk)) (Err raise 'value "Frequency convolve!: the plan is not a convolver" ()) ())
    (if (int< stride 1) (Err raise 'value "Frequency convolve!: stride must be at least 1" stride) ())
    (if (int< offset 0) (Err raise 'value "Frequency convolve!: offset must be at least 0" offset) ())
    (self %convolve-at! (if (type? mix (type-of 0)) mix (ptr->int (str->ptr mix))) stride offset gain ()))

  (method twin (self)
    (doc "A second convolver over the same impulse: the pieces' spectra shared, the ring of blocks, the overlap and the scratch its own. For a stereo mix's other channel."
      (returns Frequency "A new convolver")
      (sample "((Frequency convolver ir 88200 1024) twin)" "a convolver for the right channel, sharing the left one's pieces"))
    (if (null? (field 'blk)) (Err raise 'value "Frequency twin: the plan is not a convolver" ()) ())
    (let ((c (new-from Frequency (List append (Frequency %base (field 'n))
               (list 'cos (field 'cos) 'sin (field 'sin) 'rev (field 'rev) 'inner ()
                     'blk (field 'blk) 'parts (field 'parts) 'hre (field 'hre) 'him (field 'him))))))
      (c %ring!)
      c))

  ; The pieces of COUNT words at IA, BLK frames each, the last padded, each
  ; read by %words into its place in hre and him and transformed there. The
  ; setup around the pieces measured under a block's %block-cost.
  (method %convolver! (self ia count blk kern)
    (let ((n (field 'n)) (parts (int/ (int+ count (int- blk 1)) blk)))
      (let ((hre (Frequency %buf (int* parts n))) (him (Frequency %buf (int* parts n))))
        (set-field! 'blk blk)
        (set-field! 'parts parts)
        (set-field! 'hre hre)
        (set-field! 'him him)
        (self %ring!)
        (let ((hr (ptr->int (str->ptr hre))) (hi (ptr->int (str->ptr him))) (run (self %runner kern)))
          (def piece
            (fn (go p)
              (if (int< p parts)
                (let ((at (int* p (int* 8 n))) (left (int- count (int* p blk))))
                  (run 5 (list (int+ hr at) (int+ hi at) ia 1 (int* p blk) 0 0 (if (int< blk left) blk left) n 0 0 0 0))
                  (run 1 (self %radix2-words (int+ hr at) (int+ hi at) 0))
                  (go (int+ p 1)))
                ())))
          (piece 0)
          (Frequency %owe! (int+ (Frequency %block-cost) (int* parts (Frequency %piece-cost))))))))

  ; A ring of PARTS spectra and an overlap, all zeros (0.0's bits), the
  ; head at slot 0, and 1/2 at the scratch's double 20 for %overlap.
  (method %ring! (self)
    (let ((ring (int* 8 (int* (field 'parts) (field 'n)))) (ov (int* 8 (field 'blk))))
      (let ((xre (str-make ring)) (xim (str-make ring)) (o (str-make ov)))
        (mem-set (str->ptr xre) 0 ring)
        (mem-set (str->ptr xim) 0 ring)
        (mem-set (str->ptr o) 0 ov)
        (set-field! 'xre xre)
        (set-field! 'xim xim)
        (set-field! 'ov o)
        (set-field! 'head 0)
        (Frequency %fset! (ptr->int (str->ptr (field 'scr))) 20 (first (f-div (float-of 1) (float-of 2)))))))

  ; One block: the channel into the ring's head slot and transformed
  ; there, the pieces' products summed into the data, the inverse by the
  ; parts swapped (n times the convolution, in re), and %overlap at
  ; GAIN / n into the words.
  (method %convolve-at! (self ma stride offset gain kern)
    (let ((n (field 'n)) (blk (field 'blk)) (parts (field 'parts)) (head (field 'head))
          (re (ptr->int (str->ptr (field 're)))) (im (ptr->int (str->ptr (field 'im))))
          (xr (ptr->int (str->ptr (field 'xre)))) (xi (ptr->int (str->ptr (field 'xim))))
          (tables (list (ptr->int (str->ptr (field 'cos))) (ptr->int (str->ptr (field 'sin))) (ptr->int (str->ptr (field 'rev)))))
          (run (self %runner kern)))
      (def radix2 (fn (_ a b) (run 1 (pair a (pair b (List append tables (list n 0 0 2 0 0 (int>> n 1) 0)))))))
      (let ((at (int* head (int* 8 n))))
        (run 5 (list (int+ xr at) (int+ xi at) ma stride offset 0 0 blk n 0 0 0 0))
        (radix2 (int+ xr at) (int+ xi at)))
      (run 6 (list re im xr xi (ptr->int (str->ptr (field 'hre))) (ptr->int (str->ptr (field 'him)))
                   (int+ (int>> n 1) 1) parts n 0 0 head 0 0 0 (int+ (int>> n 1) 1)))
      (radix2 im re)
      (Frequency %fset! (ptr->int (str->ptr (field 'scr))) 19 (first (f-div (float-of gain) (float-of n))))
      (run 7 (list re 0 (ptr->int (str->ptr (field 'ov))) ma stride offset 0 blk 0 0 0 0 0))
      (set-field! 'head (if (int= (int+ head 1) parts) 0 (int+ head 1)))
      (Frequency %owe! (Frequency %block-cost))
      self))

  ; (run WHICH VS) writes the words VS into the scratch from word 0 and
  ; runs kernel WHICH to its end: with the lane compiled and no KERN,
  ; called straight on an unbounded budget, as %spectrum-run! does, and
  ; otherwise through %drive. Made once a block, so a kernel run costs no
  ; class dispatch.
  (method %runner (self kern)
    (let ((s (str->ptr (field 'scr))) (ks (if (null? kern) (Frequency %kernels) kern)))
      (let ((sa (ptr->int s)) (straight (if (null? kern) (first ks) #f)) (budget (int* 12 %word-size)))
        (def put
          (fn (go i vs)
            (if (null? vs) () (do (ptr-set-word! s (int* i %word-size) (first vs)) (go (int+ i 1) (rest vs))))))
        (def nth (fn (go i l) (if (int= i 0) (first l) (go (int- i 1) (rest l)))))
        (fn (_ which vs)
          (put 0 vs)
          (if straight
            (do (ptr-set-word! s budget 1073741823) ((nth which ks) sa))
            (Frequency %drive kern which s))))))

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
    (Frequency %drive kern 1 (self %words! (self %radix2-words re im 0))))

  ; The radix-2 kernel's scratch words for the data at RE and IM, the
  ; budget BUDGET (%drive sets its own over a 0).
  (method %radix2-words (self re im budget)
    (let ((n (field 'n)))
      (list re im (ptr->int (str->ptr (field 'cos))) (ptr->int (str->ptr (field 'sin)))
            (ptr->int (str->ptr (field 'rev))) n 0 0 2 0 0 (int>> n 1) budget)))

  ; OUT = X Y[j ys] over cnt, zeros to len. The zeros are the scratch's
  ; double 16, written when the plan was made and by no kernel after: the
  ; radix-2 swap keeps its double in T0, 21.
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
