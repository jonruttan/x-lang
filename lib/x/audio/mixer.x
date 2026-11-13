; mixer.x -- Mixer: voices synthesised from wave tables, mixed to stereo
; signed 16-bit frames, block by block, for a stream to play.
;
; A voice is one oscillator: a wave table read at a pitch, shaped by an
; envelope of straight lines between points, through a one-pole low-pass,
; and placed left or right.  A sound is a list of voices.  A mixer renders
; the voices playing a block at a time into a buffer of frames, with its
; effects over the mix (echoes, a reverb, a phaser), and at each block's
; boundary and at any frame a source asks for, it hands the time to its
; sources (a tracker, a pulse) which start the voices due then.  A mixer's
; pitch and cut move every voice in it, and its effects can be named,
; changed and taken off while it plays.
;
; Everything is integers.  A phase is 32 bits of a cycle, a step the phase
; a frame; a level is 0 to 2^24; a gain or a pan weight is 0 to 256.
; Times in a voice's description are milliseconds, levels percent.
;
; The loops that touch every frame are ten kernels, each written once
; below as an integer function over word addresses.  The pure-x version is
; that form through x/tool/int-form; x/tool/int-form-jit compiles the same
; forms, and the compiled ones are adopted only after they write what the
; pure ones write.  A mixer builds them when it is made: per-frame loops in
; pure x are too slow to keep a stream fed, so (Mixer jit!) answers whether
; a mixer can keep up.
(module x/audio/mixer)

(import x/tool/compiled)
(import x/tool/int-form int-form-pure)
(import x/core/doors int% int& int* int+ int- int/ int< int= int>> int<< obj-make obj-ref obj-set!
  ptr->int ptr-ref-word ptr-set-word! int->ptr str->ptr str-make str-byte-len str-byte-ref char->int mem-copy)
(import x/num/fixed fixed/ fixed*/)

(def %fail (fn (_ what) (Err raise (lit value) (Str8 append "Mixer: " what) ())))

; --- The kernels, as forms -------------------------------------------------
;
; (%mem-ref-at A I) is the word at A + I words; (%mem-set-at! A I V) stores
; V there and answers it.

; Frames I to N of mono buffer M: wave table TAB read at phase PH >> SH,
; PH stepping by ST and ST by DS, at level VOL stepping by DV, through the
; low-pass whose last output is Y and whose coefficient is K (65536 passes
; all).  Answers the phase after the last frame; the low-pass's last
; output is the last frame written.
(def %osc-form
  (lit (fn (self m i n tab sh ph st ds vol dv y k)
    (if (< i n)
      (self m (+ i 1) n tab sh (& (+ ph st) 0xFFFFFFFF) (+ st ds) ds (+ vol dv) dv
            (%mem-set-at! m i (+ y (*>> (- (>> (* (%mem-ref-at tab (& (>> ph sh) (- (<< 1 (- 32 sh)) 1))) (>> vol 8)) 16) y) k 16)))
            k)
      ph))))

; Frames I to N of mono buffer M added into stereo buffer A, left and
; right weighted by GL and GR.
(def %mix-form
  (lit (fn (self m a i n gl gr)
    (if (< i n)
      (do (%mem-set-at! a (<< i 1) (+ (%mem-ref-at a (<< i 1)) (>> (* (%mem-ref-at m i) gl) 8)))
          (%mem-set-at! a (+ (<< i 1) 1) (+ (%mem-ref-at a (+ (<< i 1) 1)) (>> (* (%mem-ref-at m i) gr) 8)))
          (self m a (+ i 1) n gl gr))
      0))))

; Words I to N of stereo buffer X through the delay line R of LEN words
; (an even number, so each channel echoes itself), at P, added into Y: D
; is the word at P, LEN words ago.  Y gets D at WET; the line gets X plus
; the mean of D and the word after it in its channel at FB, a little
; duller each time round.  X and Y the same buffer is an echo over it;
; apart, a comb of a reverb.  Answers the place after the last word.
(def %echo-form
  (lit (fn (self x y r i n p len fb wet d)
    (if (< i n)
      (do (%mem-set-at! r p (+ (%mem-ref-at x i)
                               (>> (* (+ d (%mem-ref-at r (if (< (+ p 2) len) (+ p 2) (- (+ p 2) len)))) fb) 9)))
          (%mem-set-at! y i (+ (%mem-ref-at y i) (>> (* d wet) 8)))
          (self x y r (+ i 1) n (if (< (+ p 1) len) (+ p 1) 0) len fb wet
                (%mem-ref-at r (if (< (+ p 1) len) (+ p 1) 0))))
      p))))

; Words I to N of stereo buffer A through the all-pass of line R, LEN
; words, at P, at G (of 256): every frequency through at the same level,
; each at its own delay, so what passes is smeared, not coloured.  D is
; the word at P.  Answers the place after the last word.
(def %allpass-form
  (lit (fn (self a r i n p len g d)
    (if (< i n)
      (do (%mem-set-at! r p (+ (%mem-ref-at a i) (>> (* d g) 8)))
          (%mem-set-at! a i (- d (>> (* (%mem-ref-at r p) g) 8)))
          (self a r (+ i 1) n (if (< (+ p 1) len) (+ p 1) 0) len g
                (%mem-ref-at r (if (< (+ p 1) len) (+ p 1) 0))))
      p))))

; Words I to N of buffer W added into A at G, and W left zero.
(def %add-form
  (lit (fn (self w a i n g)
    (if (< i n)
      (do (%mem-set-at! a i (+ (%mem-ref-at a i) (>> (* (%mem-ref-at w i) g) 8)))
          (%mem-set-at! w i 0)
          (self w a (+ i 1) n g))
      0))))

; Words I to N of stereo buffer A through the line R, MASK + 1 words, a
; power of two, at P, read DL 65536ths of a frame back, DL stepping by DDL
; a word: the delay swept, read between the two frames it falls between.
; The line gets the mix plus what is read at FB, the mix what is read at
; WET, both of 256 and either negative.  Answers the place after the last
; word.
(def %phase-form
  (lit (fn (self a r i n p mask dl ddl fb wet)
    (if (< i n)
      (do (%mem-set-at! r p (+ (%mem-ref-at a i)
                               (>> (* (>> (+ (* (%mem-ref-at r (& (- p (<< (>> dl 16) 1)) mask)) (- 256 (& (>> dl 8) 255)))
                                             (* (%mem-ref-at r (& (- p (+ (<< (>> dl 16) 1) 2)) mask)) (& (>> dl 8) 255)))
                                          8)
                                      fb)
                                   8)))
          (%mem-set-at! a i (+ (%mem-ref-at a i)
                               (>> (* (>> (+ (* (%mem-ref-at r (& (- p (<< (>> dl 16) 1)) mask)) (- 256 (& (>> dl 8) 255)))
                                             (* (%mem-ref-at r (& (- p (+ (<< (>> dl 16) 1) 2)) mask)) (& (>> dl 8) 255)))
                                          8)
                                      wet)
                                   8)))
          (self a r (+ i 1) n (& (+ p 1) mask) mask (+ dl ddl) ddl fb wet))
      p))))

; Words I to N of buffer A at gain G, clipped to 16 bits, written to O as
; little-endian byte pairs; A is left zero for the next block.
(def %out-form
  (lit (fn (self a o i n g)
    (if (< i n)
      (do (%mem-set-at! a i (>> (* (%mem-ref-at a i) g) 8))
          (%mem-set-at! a i (match ((< 32767 (%mem-ref-at a i)) 32767)
                                   ((< (%mem-ref-at a i) -32768) -32768)
                                   (#t (%mem-ref-at a i))))
          (%mem-byte-set-at! o (<< i 1) (& (%mem-ref-at a i) 255))
          (%mem-byte-set-at! o (+ (<< i 1) 1) (& (>> (%mem-ref-at a i) 8) 255))
          (%mem-set-at! a i 0)
          (self a o (+ i 1) n g))
      0))))

; Words I to N of table T one cycle of a sine, by the rotation that turns
; (C S) by an angle whose E is 2 sin(angle / 2) in 2^30ths: S is the sine
; in 2^30ths, written in 2^15ths.
(def %sine-form
  (lit (fn (self t i n c s e)
    (if (< i n)
      (do (%mem-set-at! t i (>> s 15))
          (self t (+ i 1) n (- c (*>> s e 30)) (+ s (*>> (- c (*>> s e 30)) e 30)) e))
      0))))

; Words I to N of table T added A/256 of harmonic H of the sine S, which
; is MASK + 1 words long.
(def %harm-form
  (lit (fn (self t s i n h a mask)
    (if (< i n)
      (do (%mem-set-at! t i (+ (%mem-ref-at t i) (>> (* (%mem-ref-at s (& (* i h) mask)) a) 8)))
          (self t s (+ i 1) n h a mask))
      0))))

; Words I to N of table T noise from -32768 to 32767, drawn from the
; congruential sequence at X.  Answers the sequence's next.
(def %noise-form
  (lit (fn (self t i n x)
    (if (< i n)
      (do (%mem-set-at! t i (- (& (>> x 15) 65535) 32768))
          (self t (+ i 1) n (& (+ (* x 1103515245) 12345) 2147483647)))
      x))))

(def %forms (list %osc-form %mix-form %echo-form %out-form %sine-form %harm-form %noise-form
                  %allpass-form %add-form %phase-form))

(def %pure (List map int-form-pure %forms))

; --- The kernels in use ----------------------------------------------------

(def %k-osc ())
(def %k-mix ())
(def %k-echo ())
(def %k-out ())
(def %k-sine ())
(def %k-harm ())
(def %k-noise ())
(def %k-allpass ())
(def %k-add ())
(def %k-phase ())

(def %install!
  (fn (_ ks)
    (set! %k-osc (List ref 0 ks))
    (set! %k-mix (List ref 1 ks))
    (set! %k-echo (List ref 2 ks))
    (set! %k-out (List ref 3 ks))
    (set! %k-sine (List ref 4 ks))
    (set! %k-harm (List ref 5 ks))
    (set! %k-noise (List ref 6 ks))
    (set! %k-allpass (List ref 7 ks))
    (set! %k-add (List ref 8 ks))
    (set! %k-phase (List ref 9 ks))))

(%install! %pure)

; --- Word buffers ----------------------------------------------------------

; N zero words; the region is kept by whoever keeps the address's owner.
(def %words
  (fn (_ n)
    (def r (str-make (int+ (int* n %word-size) 8)))
    (def p (str->ptr r))
    (ptr-set-word! p 0 0)
    ((fn (self k)
       (when (int< k (int* n %word-size))
         (do (mem-copy (int->ptr (int+ (ptr->int p) k)) p
                       (if (int< (int* 2 k) (int* n %word-size)) k (int- (int* n %word-size) k)))
             (self (int* 2 k)))))
     %word-size)
    r))

(def %addr (fn (_ r) (ptr->int (str->ptr r))))
(def %wref (fn (_ a i) (ptr-ref-word (int->ptr a) (int* i %word-size))))

; --- The compiled kernels, adopted only when they agree --------------------

(def %check-words
  (fn (_ n seed)
    (def r (%words n))
    (def a (%addr r))
    ((fn (self i x)
       (when (int< i n)
         (do (ptr-set-word! (int->ptr a) (int* i %word-size) (int- (int& (int>> x 9) 65535) 32768))
             (self (int+ i 1) (int& (int+ (int* x 1103515245) seed) 2147483647)))))
     0 seed)
    r))

(def %same?
  (fn (self a b i n)
    (match ((int< i n) (if (int= (%wref a i) (%wref b i)) (self a b (int+ i 1) n) #f))
           (#t #t))))

; Each kernel run pure and by the candidate on copies of the same two
; buffers, both copies compared word for word, and the answers compared.
(def %agrees?
  (fn (_ engine)
    (def runs
      (list (fn (_ k d e) (k d 3 40 e 26 4000000000 123456789 -1000 9000000 -700 55 30000))
            (fn (_ k d e) (k e d 0 30 200 57))
            (fn (_ k d e) (k d d e 0 64 5 60 300 90 (%wref e 5)))
            (fn (_ k d e) (k d e 0 64 300))
            (fn (_ k d _) (k d 0 64 1073709056 0 102943708))
            (fn (_ k d e) (k d e 0 64 3 -90 63))
            (fn (_ k d _) (k d 0 64 977))
            (fn (_ k d e) (k d e 0 64 7 30 179 (%wref e 7)))
            (fn (_ k d e) (k d e 0 64 200))
            (fn (_ k d e) (k d e 0 64 5 63 197208 -300 -150 200))))
    (List all?
      (fn (_ i)
        (def a (%check-words 64 5))
        (def b (%check-words 64 5))
        (def c (%check-words 64 11))
        (def d (%check-words 64 11))
        (def ra ((List ref i runs) (List ref i %pure) (%addr a) (%addr c)))
        (def rb ((List ref i runs) (List ref i engine) (%addr b) (%addr d)))
        (match ((not (= ra rb)) #f)
               ((not (%same? (%addr a) (%addr b) 0 64)) #f)
               (#t (%same? (%addr c) (%addr d) 0 64))))
      (list 0 1 2 3 4 5 6 7 8 9))))

(def %entry ())

(def %jit-try!
  (fn (_)
    (when (null? %entry)
      (set! %entry
        (Compiled make-on-demand (lit audio) %pure
          (fn (_)
            (import x/tool/int-form-jit)
            ((prim-ref (lit int-form) (lit jit-make)) %forms %agrees?))
          %install!)))
    ((fn (_ entry)
       (when (eq? (entry state) (lit interpreted)) (entry compile!))
       (eq? (entry state) (lit compiled)))
     %entry)))

; --- Wave tables -----------------------------------------------------------
;
; A wave is (REGION ADDRESS SHIFT): a table of 2^(32 - SHIFT) words, one
; cycle, each -32768 to 32767.  Tables are shared by every mixer.

(def %cycle-bits 11)
(def %cycle (int<< 1 %cycle-bits))
(def %noise-bits 15)
; 2 sin(pi / 2048) in 2^30ths: the rotation that closes in 2048 steps.
(def %cycle-turn 3294198)

(def %waves (pair () ()))

(def %sine-wave
  (fn (_)
    (def r (%words %cycle))
    (%k-sine (%addr r) 0 %cycle 1073709056 0 %cycle-turn)
    (list r (%addr r) (int- 32 %cycle-bits))))

(def %noise-wave
  (fn (_)
    (def n (int<< 1 %noise-bits))
    (def r (%words n))
    (%k-noise (%addr r) 0 n 20261108)
    (list r (%addr r) (int- 32 %noise-bits))))

(def %abs (fn (_ n) (if (int< n 0) (int- 0 n) n)))

; Harmonics AMPS, the first the fundamental, summed into one cycle, scaled
; so the loudest the sum can be is the sine's.
(def %harmonic-wave
  (fn (_ amps)
    (def total (List fold (fn (_ acc a) (int+ acc (%abs a))) 0 amps))
    (when (int< total 1) (%fail "wave: the harmonics are all zero"))
    (def sine (%wave (lit sine)))
    (def r (%words %cycle))
    (List fold
      (fn (_ h a)
        (unless (int= a 0)
          (%k-harm (%addr r) (List ref 1 sine) 0 %cycle h (int/ (int* a 256) total) (int- %cycle 1)))
        (int+ h 1))
      1 amps)
    (list r (%addr r) (int- 32 %cycle-bits))))

(def %wave
  (fn (_ name)
    (def hit (Assoc entry name (first %waves)))
    (match
      ((not (null? hit)) (rest hit))
      ((eq? name (lit sine)) (%wave-put! name (%sine-wave)))
      ((eq? name (lit noise)) (%wave-put! name (%noise-wave)))
      (#t (%fail (Str8 append "no wave named " (symbol->str name)))))))

(def %wave-put!
  (fn (_ name w)
    (%set-first! %waves (pair (pair name w) (first %waves)))
    w))

; --- Pitch -----------------------------------------------------------------

; The twelve notes of octave 4 in thousandths of a hertz, C first.
(def %octave4
  (list 261626 277183 293665 311127 329628 349228 369994 391995 415305 440000 466164 493883))

(def %letters (list (pair "C" 0) (pair "D" 2) (pair "E" 4) (pair "F" 5) (pair "G" 7) (pair "A" 9) (pair "B" 11)))

; Note NAME, such as "C4", "F#3" or "Bb2", as semitones above C0.
(def %note-semi
  (fn (_ name)
    (def n (str-byte-len name))
    (def letter (if (int< n 2) () (List find (fn (_ e) (str=? (first e) (Str8 sub 0 1 name))) %letters)))
    (when (null? letter) (%fail (Str8 append "not a note: " name)))
    (def accidental (Str8 sub 1 1 name))
    (def shift (match ((str=? accidental "#") 1) ((str=? accidental "b") -1) (#t 0)))
    (def at (if (int= shift 0) 1 2))
    (def octave (if (int= n (int+ at 1)) (int- (char->int (str-byte-ref name at)) 48) -1))
    (when (or (int< octave 0) (int< 9 octave)) (%fail (Str8 append "not a note: " name)))
    (int+ (int* octave 12) (int+ (rest letter) shift))))

; Note NAME as thousandths of a hertz.
(def %note-mhz
  (fn (_ name)
    (def s (%note-semi name))
    (def oct (if (int< s 0) -1 (int/ s 12)))
    (def f (List ref (int- s (int* oct 12)) %octave4))
    (if (int< oct 4) (int>> f (int- 4 oct)) (int<< f (int- oct 4)))))

; The step a frame for thousandths of a hertz MHZ at RATE frames a second.
(def %step (fn (_ mhz rate) (fixed/ mhz (int* rate 1000) 32)))

; A pitch as a voice gives it: a note's name, or (hz N).
(def %pitch-mhz
  (fn (_ p)
    (if (str? p) (%note-mhz p) (int* p 1000))))

; STEP moved CENTS cents, close enough for the few a chorus is detuned.
(def %detune (fn (_ step cents) (int+ step (fixed*/ step (int* cents 5778) 10000000))))

; STEP moved CENTS cents, any number of them: whole octaves by shifting,
; whole semitones by the octave's ratios, the rest by %detune.
(def %shift
  (fn (_ step cents)
    (def oct (if (int< cents 0) (int- 0 (int/ (int+ (int- 0 cents) 1199) 1200)) (int/ cents 1200)))
    (def rem (int- cents (int* oct 1200)))
    (def s (%detune (fixed*/ step (List ref (int/ rem 100) %octave4) (first %octave4))
                    (int- rem (int* 100 (int/ rem 100)))))
    (if (int< oct 0) (int>> s (int- 0 oct)) (int<< s oct))))

; --- Voices ----------------------------------------------------------------
;
; A voice is a vector record: its wave's table and shift, phase, step,
; step's step, level, low-pass output and coefficient, left and right
; weights, the frame it has reached (negative before it starts), its
; envelope's points still ahead, ((FRAME . LEVEL) ...), from its start,
; its wave, its low-pass coefficient before the mixer's cut, and its bend's
; points still ahead, ((FRAME . STEP) ...): the step it is at each point,
; in straight lines between, and held after the last.

(def %vector-type ((prim-ref (lit type) (lit of)) (Vector make 0 ())))
(def %rec (fn (_ n) ((fn (_ r) (do (obj-set! r 0 n) r)) (obj-make %vector-type (int+ n 1)))))
(def %get (fn (_ r k) (obj-ref r (int+ k 1))))
(def %put! (fn (_ r k x) (obj-set! r (int+ k 1) x)))

(def %v-tab 0) (def %v-sh 1) (def %v-ph 2) (def %v-st 3) (def %v-ds 4) (def %v-vol 5)
(def %v-y 6) (def %v-k 7) (def %v-gl 8) (def %v-gr 9) (def %v-t 10) (def %v-env 11) (def %v-wave 12)
(def %v-k0 13) (def %v-bend 14)

; Low-pass coefficient K at CUT percent, never shut.
(def %cut-k (fn (_ k cut) ((fn (_ c) (if (int< c 1) 1 c)) (int/ (int* k cut) 100))))

(def %prop
  (fn (_ spec key default)
    (def hit (List find (fn (_ f) (if (pair? f) (eq? (first f) key) #f)) spec))
    (if (null? hit) default (rest hit))))
(def %prop1 (fn (_ spec key default) ((fn (_ v) (if (null? v) default (first v))) (%prop spec key ()))))

(def %ms (fn (_ ms rate) (fixed*/ ms rate 1000)))
(def %level (fn (_ pct gain) (fixed*/ (int<< pct 24) gain 10000)))

; Voice SPEC at RATE, starting AT frames after the block's start, at GAIN
; percent, moved CENTS cents and its low-pass at CUT percent, the mixer's
; own.  SPEC is a list of (KEY ...): (wave NAME), (env (MS PCT) ...), a
; pitch (note "C4") or (hz N), (slide PITCH), (bend (MS CENTS) ...), (cut
; PCT), (pan -100..100), (gain PCT), (detune CENTS), (at MS).  A bend is
; the pitch's path, CENTS from it at each MS, in straight lines between and
; a jump where two points share an MS; with one, the slide is not used.
(def %voice
  (fn (_ spec rate at gain cents master-cut)
    (def w (%wave (%prop1 spec (lit wave) (lit sine))))
    (def g (int/ (int* gain (%prop1 spec (lit gain) 100)) 100))
    (def env (List map (fn (_ p) (pair (%ms (first p) rate) (%level (first (rest p)) g)))
                   (%prop spec (lit env) (lit ((0 100) (200 0))))))
    (def len (if (null? env) 0 (first (List ref -1 env))))
    (def pitch (%prop1 spec (lit note) ()))
    (def mhz (if (null? pitch) (int* 1000 (%prop1 spec (lit hz) 440)) (%note-mhz pitch)))
    (def moved (fn (_ s) (if (int= cents 0) s (%shift s cents))))
    (def base (%detune (%step mhz rate) (%prop1 spec (lit detune) 0)))
    (def st (moved base))
    (def slide (%prop1 spec (lit slide) ()))
    (def st1 (if (null? slide) st (moved (%detune (%step (%pitch-mhz slide) rate) (%prop1 spec (lit detune) 0)))))
    (def bend (List map (fn (_ p) (pair (%ms (first p) rate) (moved (%shift base (first (rest p))))))
                        (%prop spec (lit bend) ())))
    (def cut (%prop1 spec (lit cut) 100))
    (def pan (%prop1 spec (lit pan) 0))
    (def v (%rec 15))
    (%put! v %v-tab (List ref 1 w))
    (%put! v %v-sh (List ref 2 w))
    (%put! v %v-ph 0)
    (%put! v %v-st st)
    (%put! v %v-ds (if (if (null? bend) (int< 0 len) #f) (int/ (int- st1 st) len) 0))
    (%put! v %v-bend bend)
    (%put! v %v-vol 0)
    (%put! v %v-y 0)
    (%put! v %v-k0 (int/ (int* (if (int< 100 cut) 100 (if (int< cut 1) 1 cut)) 65536) 100))
    (%put! v %v-k (%cut-k (%get v %v-k0) master-cut))
    (%put! v %v-gl (int/ (int* (int- 100 pan) 256) 200))
    (%put! v %v-gr (int/ (int* (int+ 100 pan) 256) 200))
    (%put! v %v-t (int- 0 (int+ at (%ms (%prop1 spec (lit at) 0) rate))))
    (%put! v %v-env env)
    (%put! v %v-wave w)
    v))

; Voice V's bend point P reached: its step taken, and the step's step
; toward the next point, or held.
(def %bend-to!
  (fn (_ v p ahead)
    (%put! v %v-st (rest p))
    (%put! v %v-ds (match ((null? ahead) 0)
                          ((int< (first p) (first (first ahead)))
                            (int/ (int- (rest (first ahead)) (rest p)) (int- (first (first ahead)) (first p))))
                          (#t 0)))
    (%put! v %v-bend ahead)))

; Voice V rendered over frames A to B of the block into mono buffer M and
; added into stereo buffer S, in stretches that end at its envelope's and
; its bend's points.  Answers #t while the voice has more to play.
(def %voice-render!
  (fn (_ v m s a b)
    (def t (%get v %v-t))
    (match
      ((not (int< (int+ t (int- b a)) 1)) ; under way, or starting in this stretch
        ((fn (self from)
           (def env (%get v %v-env))
           (def bend (%get v %v-bend))
           (match
             ((null? env) #f)
             ((not (int< from b)) #t)
             ((if (null? bend) #f (not (int< (%get v %v-t) (first (first bend)))))
               (do (%bend-to! v (first bend) (rest bend)) (self from)))
             (#t
               (do (def tt (%get v %v-t))
                   (def point (first env))
                   (def left (int- (first point) tt))
                   (def until (if (null? bend) left
                                ((fn (_ l) (if (int< l left) l left)) (int- (first (first bend)) tt))))
                   (def to (if (int< (int+ from until) b) (int+ from until) b))
                   (def n (int- to from))
                   (def vol (%get v %v-vol))
                   (if (int< n 1)
                     (do (%put! v %v-vol (rest point)) (%put! v %v-env (rest env)) (self from))
                     (do (def dv (int/ (int- (rest point) vol) left))
                         (%put! v %v-ph
                           (%k-osc m from to (%get v %v-tab) (%get v %v-sh) (%get v %v-ph) (%get v %v-st)
                                   (%get v %v-ds) vol dv (%get v %v-y) (%get v %v-k)))
                         (%put! v %v-st (int+ (%get v %v-st) (int* n (%get v %v-ds))))
                         (%put! v %v-y (%wref m (int- to 1)))
                         (%k-mix m s from to (%get v %v-gl) (%get v %v-gr))
                         (%put! v %v-t (int+ tt n))
                         (if (int= n left)
                           (do (%put! v %v-vol (rest point)) (%put! v %v-env (rest env)))
                           (%put! v %v-vol (int+ vol (int* n dv))))
                         (self to)))))))
         (if (int< t 0) (do (%put! v %v-t 0) (int- a t)) a)))
      (#t (do (%put! v %v-t (int+ t (int- b a))) #t)))))

; --- Mixers ----------------------------------------------------------------
;
; A mixer is a vector record: rate, block frames, the stereo and mono word
; buffers and the frame bytes (regions and addresses), gain, the frame
; count rendered, the voices playing, the sources as ((NEXT . SOURCE) ...),
; the effects in the order they run, a stereo word buffer a reverb's
; combs sum into (region and address), and the pitch in cents and the cut
; in percent every voice is played at.

(def %m-rate 0) (def %m-block 1) (def %m-acc 2) (def %m-acc-a 3) (def %m-mono 4) (def %m-mono-a 5)
(def %m-out 6) (def %m-out-a 7) (def %m-gain 8) (def %m-clock 9) (def %m-voices 10) (def %m-sources 11)
(def %m-effects 12) (def %m-wet 13) (def %m-wet-a 14) (def %m-pitch 15) (def %m-cut 16)

(def %make
  (fn (_ rate block)
    (when (int< rate 1000) (%fail "make: RATE is 1000 frames a second or more"))
    (when (int< block 16) (%fail "make: BLOCK is 16 frames or more"))
    (%jit-try!)
    (def m (%rec 17))
    (def acc (%words (int* 2 block)))
    (def mono (%words block))
    (def wet (%words (int* 2 block)))
    (def out (str-make (int+ (int* 4 block) 8)))
    (%put! m %m-rate rate)
    (%put! m %m-block block)
    (%put! m %m-acc acc) (%put! m %m-acc-a (%addr acc))
    (%put! m %m-mono mono) (%put! m %m-mono-a (%addr mono))
    (%put! m %m-out out) (%put! m %m-out-a (%addr out))
    (%put! m %m-gain 256)
    (%put! m %m-clock 0)
    (%put! m %m-voices ())
    (%put! m %m-sources ())
    (%put! m %m-effects ())
    (%put! m %m-wet wet) (%put! m %m-wet-a (%addr wet))
    (%put! m %m-pitch 0)
    (%put! m %m-cut 100)
    m))

; Voices from the list SPECS started AT frames from now, at GAIN percent.
(def %play!
  (fn (_ m specs at gain)
    (def rate (%get m %m-rate))
    (def cents (%get m %m-pitch))
    (def cut (%get m %m-cut))
    (%put! m %m-voices
      (List fold (fn (_ acc s) (pair (%voice s rate at gain cents cut) acc)) (%get m %m-voices) specs))
    m))

; Every voice of M, playing and to come, moved to CENTS from its own pitch.
(def %pitch!
  (fn (_ m cents)
    (def by (int- cents (%get m %m-pitch)))
    (unless (int= by 0)
      (List for-each
        (fn (_ v)
          (%put! v %v-st (%shift (%get v %v-st) by))
          (%put! v %v-ds (%shift (%get v %v-ds) by))
          (%put! v %v-bend (List map (fn (_ p) (pair (first p) (%shift (rest p) by))) (%get v %v-bend))))
        (%get m %m-voices)))
    (%put! m %m-pitch cents)
    m))

; Every voice of M, playing and to come, its low-pass at PCT of its own.
(def %cut!
  (fn (_ m pct)
    (def cut (if (int< 100 pct) 100 (if (int< pct 1) 1 pct)))
    (List for-each (fn (_ v) (%put! v %v-k (%cut-k (%get v %v-k0) cut))) (%get m %m-voices))
    (%put! m %m-cut cut)
    m))

; --- Effects ---------------------------------------------------------------
;
; An effect is a record of its name (nil for one echo! added), the spec it
; was made from, and its stages, run in order over each block.  A stage is
; a record headed by its kind:
;
;   echo     line region, address, words, place; feedback, wet, and
;            whether it sums into the wet buffer (a reverb's comb) or
;            over the mix (an echo)
;   allpass  line region, address, words, place; gain, over the wet buffer
;   add      the wet buffer into the mix at a gain, the wet buffer cleared
;   phase    line region, address, words (a power of two), place; the
;            delay's least and its sweep in 65536ths of a frame, the sweep's
;            period in frames and the frame it has reached; feedback, wet
;
; Gains are of 256.

(def %e-name 0) (def %e-spec 1) (def %e-stages 2)
(def %s-kind 0) (def %s-line 1) (def %s-addr 2) (def %s-len 3) (def %s-place 4)

(def %pct256 (fn (_ pct) (int/ (int* pct 256) 100)))
(def %clamp (fn (_ lo hi n) (if (int< n lo) lo (if (int< hi n) hi n))))

; A stage of KIND with a line of LEN words and N fields after it.
(def %line-stage
  (fn (_ kind len n)
    (def s (%rec (int+ 5 n)))
    (def line (%words len))
    (%put! s %s-kind kind)
    (%put! s %s-line line) (%put! s %s-addr (%addr line)) (%put! s %s-len len) (%put! s %s-place 0)
    s))

; Fields 5 on: echo feedback wet into-wet?; allpass gain; phase least
; sweep period reached feedback wet.
(def %echo-stage
  (fn (_ frames fb wet into)
    (def s (%line-stage (lit echo) (int* 2 (if (int< frames 1) 1 frames)) 3))
    (%put! s 5 fb) (%put! s 6 wet) (%put! s 7 into)
    s))

(def %allpass-stage
  (fn (_ frames g)
    (def s (%line-stage (lit allpass) (int* 2 (if (int< frames 1) 1 frames)) 1))
    (%put! s 5 g)
    s))

(def %add-stage
  (fn (_ g)
    (def s (%rec 2))
    (%put! s %s-kind (lit add))
    (%put! s 1 g)
    s))

(def %pow2 (fn (self n k) (if (int< k n) (self n (int* k 2)) k)))

(def %phase-stage
  (fn (_ least most period fb wet)
    (def s (%line-stage (lit phase) (%pow2 (int* 2 (int+ (int>> most 16) 2)) 2) 6))
    (%put! s 5 least) (%put! s 6 (int- most least)) (%put! s 7 (if (int< period 2) 2 period)) (%put! s 8 0)
    (%put! s 9 fb) (%put! s 10 wet)
    s))

; The combs of a reverb in tenths of a millisecond at a size of 100, and
; its all-passes': lengths with no common factor, so their repeats never
; line up.
(def %combs (list 297 371 411 437))
(def %allpasses (list 50 17))

; The stages for SPEC at RATE: (echo MS FB WET), (reverb SIZE DECAY WET)
; or (phase LEAST-MS MOST-MS PERIOD-MS FB WET).
(def %stages
  (fn (_ spec rate)
    (def arg (fn (_ i) (List ref (int+ i 1) spec)))
    (def tenths (fn (_ t) (fixed*/ t rate 10000)))
    (match
      ((eq? (first spec) (lit echo))
        (list (%echo-stage (%ms (arg 0) rate) (%pct256 (arg 1)) (%pct256 (arg 2)) #f)))
      ((eq? (first spec) (lit reverb))
        (List append
          (List map (fn (_ c) (%echo-stage (tenths (int/ (int* c (arg 0)) 100)) (%pct256 (%clamp 0 98 (arg 1))) 64 #t))
                    %combs)
          (List map (fn (_ a) (%allpass-stage (tenths a) 179)) %allpasses)
          (list (%add-stage (%pct256 (arg 2))))))
      ((eq? (first spec) (lit phase))
        ((fn (_ least)
           (list (%phase-stage least (%clamp least 1073741824 (int* 65536 (%ms (arg 1) rate))) (%ms (arg 2) rate)
                               (%pct256 (%clamp -95 95 (arg 3))) (%pct256 (%clamp -100 100 (arg 4))))))
         (%clamp 65536 1073741824 (int* 65536 (%ms (arg 0) rate)))))
      (#t (%fail (Str8 append "effect: no effect named " (symbol->str (first spec))))))))

; STAGES with each line the same length as OLD's at the same place taken
; over, with where it had reached: a change of feedback or gain keeps
; what is ringing.
(def %keep-lines
  (fn (self stages old)
    (unless (null? stages)
      (do (def s (first stages))
          (def o (if (null? old) () (first old)))
          (when (if (null? o) #f
                  (if (eq? (%get o %s-kind) (%get s %s-kind))
                    (if (eq? (%get s %s-kind) (lit add)) #f (int= (%get o %s-len) (%get s %s-len)))
                    #f))
            (do (%put! s %s-line (%get o %s-line)) (%put! s %s-addr (%get o %s-addr)) (%put! s %s-place (%get o %s-place))
                (when (eq? (%get s %s-kind) (lit phase)) (%put! s 8 (%get o 8)))))
          (self (rest stages) (if (null? old) () (rest old)))))))

(def %effect-make
  (fn (_ name spec stages)
    (def e (%rec 3))
    (%put! e %e-name name) (%put! e %e-spec spec) (%put! e %e-stages stages)
    e))

; The effect named NAME over M made from SPEC, in its place if it has one
; and else after the rest, or taken off for SPEC nil.
(def %effect!
  (fn (_ m name spec)
    (def old (List find (fn (_ e) (same? (%get e %e-name) name)) (%get m %m-effects)))
    (match
      ((null? spec) (%put! m %m-effects (List filter (fn (_ e) (not (same? (%get e %e-name) name))) (%get m %m-effects))))
      ((null? old) (%put! m %m-effects (List append (%get m %m-effects)
                                         (list (%effect-make name spec (%stages spec (%get m %m-rate)))))))
      (#t (do (def stages (%stages spec (%get m %m-rate)))
              (when (eq? (first spec) (first (%get old %e-spec))) (%keep-lines stages (%get old %e-stages)))
              (%put! old %e-spec spec)
              (%put! old %e-stages stages))))
    m))

(def %echo!
  (fn (_ m ms fb wet)
    (def spec (list (lit echo) ms fb wet))
    (%put! m %m-effects (List append (%get m %m-effects) (list (%effect-make () spec (%stages spec (%get m %m-rate))))))
    m))

; A phase stage's delay at frame T of its sweep, a triangle from its least
; up and back, in 65536ths of a frame.
(def %phase-dl
  (fn (_ s t)
    (def period (%get s 7))
    (def half (int/ period 2))
    (def u (int- t (int* period (int/ t period))))
    (int+ (%get s 5) (fixed*/ (%get s 6) (if (int< u half) u (int- period u)) half))))

; Stage S over words 0 to N of M's block of B frames.
(def %stage!
  (fn (_ m s n b)
    (def acc (%get m %m-acc-a))
    (def wet (%get m %m-wet-a))
    (def kind (%get s %s-kind))
    (def line (%get s %s-addr))
    (match
      ((eq? kind (lit echo))
        (%put! s %s-place (%k-echo acc (if (%get s 7) wet acc) line 0 n (%get s %s-place) (%get s %s-len)
                                   (%get s 5) (%get s 6) (%wref line (%get s %s-place)))))
      ((eq? kind (lit allpass))
        (%put! s %s-place (%k-allpass wet line 0 n (%get s %s-place) (%get s %s-len) (%get s 5)
                                      (%wref line (%get s %s-place)))))
      ((eq? kind (lit add)) (%k-add wet acc 0 n (%get s 1)))
      (#t
        (do (def t (%get s 8))
            (def dl (%phase-dl s t))
            (%put! s %s-place (%k-phase acc line 0 n (%get s %s-place) (int- (%get s %s-len) 1) dl
                                        (int/ (int- (%phase-dl s (int+ t b)) dl) n) (%get s 9) (%get s 10)))
            (%put! s 8 ((fn (_ t1) (int- t1 (int* (%get s 7) (int/ t1 (%get s 7))))) (int+ t b))))))))

; Frames A to B of the block: every voice, then the voices that have ended
; dropped.
(def %stretch!
  (fn (_ m a b)
    (when (int< a b)
      (do (def mono (%get m %m-mono-a))
          (def acc (%get m %m-acc-a))
          (%put! m %m-voices (List filter (fn (_ v) (%voice-render! v mono acc a b)) (%get m %m-voices)))))))

; Sources due at frame NOW: each called, and its answer, the frame it is
; next due or nil for never, kept.
(def %due!
  (fn (_ m now)
    (%put! m %m-sources
      (List filter (fn (_ e) (not (null? (first e))))
        (List map (fn (_ e) (if (int< now (first e)) e (pair ((rest e) m now) (rest e))))
                  (%get m %m-sources))))))

(def %next-due
  (fn (_ m limit)
    (List fold (fn (_ acc e) (if (int< (first e) acc) (first e) acc)) limit (%get m %m-sources))))

; One block: the sources' due frames split it into stretches, the effects
; run over the whole of it, and it is written out at the gain.
(def %block!
  (fn (_ m)
    (def b (%get m %m-block))
    (def t0 (%get m %m-clock))
    (def end (int+ t0 b))
    ((fn (self now)
       (%due! m now)
       (def next (%next-due m end))
       (%stretch! m (int- now t0) (int- next t0))
       (when (int< next end) (self next)))
     t0)
    (List for-each
      (fn (_ e) (List for-each (fn (_ s) (%stage! m s (int* 2 b) b)) (%get e %e-stages)))
      (%get m %m-effects))
    (%k-out (%get m %m-acc-a) (%get m %m-out-a) 0 (int* 2 b) (%get m %m-gain))
    (%put! m %m-clock end)
    (%get m %m-out)))

; Sound SPECS rendered alone, from its first frame to its last voice's
; end, as frame bytes: (REGION . BYTES).
(def %render
  (fn (_ rate specs echoes)
    (def m (%make rate 1024))
    (List for-each (fn (_ e) (%echo! m (List ref 0 e) (List ref 1 e) (List ref 2 e))) echoes)
    (%play! m specs 0 100)
    (def tail (List fold (fn (_ acc e) (int+ acc (%ms (List ref 0 e) rate))) 0 echoes))
    (def frames
      (int+ tail (List fold (fn (_ acc v) (if (int< acc (int- (first (List ref -1 (%get v %v-env))) (%get v %v-t)))
                                            (int- (first (List ref -1 (%get v %v-env))) (%get v %v-t)) acc))
                         0 (List filter (fn (_ v) (not (null? (%get v %v-env)))) (%get m %m-voices)))))
    (def blocks (int/ (int+ frames 1023) 1024))
    (def bytes (int* blocks 4096))
    (def out (str-make (int+ bytes 8)))
    ((fn (self i)
       (when (int< i blocks)
         (do (mem-copy (int->ptr (int+ (%addr out) (int* i 4096))) (str->ptr (%block! m)) 4096)
             (self (int+ i 1)))))
     0)
    (pair out bytes)))

(def-class Mixer ()
  (doc "Voices synthesised from wave tables and mixed, a block at a time, to stereo signed 16-bit frames for (Sdl audio-put!): the sound engine's per-frame loops, compiled and checked against pure x, with the scheduling left to sources that start voices at the frames they choose."
    (example "(List ref 2 (Mixer wave (lit sine)))" "21")
    (see make) (see block!) (see voice) (see source!) (see effect!))
  (static
    (method make (self (param rate INTEGER "Frames a second, 1000 or more")
                       (param block INTEGER "Frames a block, 16 or more"))
      (doc "A mixer with no voices playing, at full gain. Builds the compiled loops the first time, as (Mixer jit!) does."
        (returns VECTOR "The mixer")
        (sample "(Mixer make 44100 512)" "a mixer"))
      (%make rate block))

    (method play! (self (param m VECTOR "A mixer")
                        (param specs LIST "Voices, each a list of (KEY ...): (wave NAME), (env (MS PCT) ...), (note \"C4\") or (hz N), (slide PITCH), (bend (MS CENTS) ...), (cut PCT), (pan -100..100), (gain PCT), (detune CENTS), (at MS)")
                        (param at INTEGER "Frames after the start of the stretch being rendered, 0 at once")
                        (param gain INTEGER "Percent of each voice's own gain"))
      (doc "Start a sound: each voice plays its envelope from AT, its pitch sliding to its slide's over the envelope, or following its bend (CENTS from its pitch at each MS, straight between, a jump where two points share an MS), and ends at the envelope's last point. A voice with no wave is a sine; with no envelope, a 200 ms fade."
        (returns VECTOR "The mixer")
        (sample "(Mixer play! m (list (list (list (lit note) \"A4\") (list (lit env) (list 0 0) (list 5 80) (list 300 0)))) 0 100)" "m"))
      (%play! m specs at gain))

    (method source! (self (param m VECTOR "A mixer")
                          (param f CALLABLE "(fn (_ m now)) starting what is due at frame NOW, answering the frame it is next due, or nil for never")
                          (param at INTEGER "The frame it is first due"))
      (doc "Add a source: at each frame it asks for, the block is split there and F is called before the frames from it are rendered, so a voice it plays with at 0 starts on that frame."
        (returns VECTOR "The mixer")
        (sample "(Mixer source! m (fn (_ m now) (+ now 22050)) 0)" "m"))
      (%put! m %m-sources (pair (pair at f) (%get m %m-sources)))
      m)

    (method echo! (self (param m VECTOR "A mixer")
                        (param ms INTEGER "The delay")
                        (param fb INTEGER "Percent fed back round the line")
                        (param wet INTEGER "Percent of the line added to the mix"))
      (doc "Add an echo over everything the mixer renders, after any effects added before it: the mix delayed by MS, each repeat duller than the last. It has no name, so it stays; effect! adds one that can be changed or taken off."
        (returns VECTOR "The mixer")
        (sample "(Mixer echo! m 370 45 30)" "m"))
      (%echo! m ms fb wet))

    (method effect! (self (param m VECTOR "A mixer")
                          (param name ANY "The effect's name: a symbol, or any object kept to name it, told apart by identity (same?)")
                          (param spec LIST "(echo MS FB WET), (reverb SIZE DECAY WET) or (phase LEAST-MS MOST-MS PERIOD-MS FB WET); nil to take it off"))
      (doc "Put an effect over everything the mixer renders, by name: a new name runs after the effects already there, a name already there is changed in its place, and nil takes it off. An echo is the mix delayed by MS, FB percent fed back and WET percent added, each repeat duller. A reverb is a room: four combs at SIZE percent of a middling room's lengths, DECAY percent fed back (up to 98), through two all-passes, WET percent added. A phase sweeps a short delay from LEAST-MS to MOST-MS and back every PERIOD-MS, FB percent fed back and WET percent added, each -95 to 95 and -100 to 100: a phaser at a millisecond or two, a flanger at more. A change that keeps an effect's kind and its lines' lengths keeps what is ringing in them."
        (returns VECTOR "The mixer")
        (sample "(Mixer effect! m (lit room) (list (lit reverb) 120 80 30))" "m"))
      (%effect! m name spec))

    (method effects (self (param m VECTOR "A mixer"))
      (doc "The effects over the mix, in the order they run: each its name, nil for an echo! one, and the spec it was made from."
        (returns LIST "((NAME . SPEC) ...)")
        (sample "(Mixer effects m)" "((room reverb 120 80 30))"))
      (List map (fn (_ e) (pair (%get e %e-name) (%get e %e-spec))) (%get m %m-effects)))

    (method pitch! (self (param m VECTOR "A mixer")
                         (param cents INTEGER "Cents from each voice's own pitch, below 0 flatter; 1200 an octave"))
      (doc "Move every voice, those playing and those to come, CENTS from its own pitch: a whole song played higher or lower."
        (returns VECTOR "The mixer")
        (sample "(Mixer pitch! m -300)" "m"))
      (%pitch! m cents))

    (method pitch (self (param m VECTOR "A mixer"))
      (doc "The cents every voice is moved from its own pitch."
        (returns INTEGER "Cents")
        (sample "(Mixer pitch m)" "0"))
      (%get m %m-pitch))

    (method cut! (self (param m VECTOR "A mixer")
                       (param pct INTEGER "1 to 100: percent of each voice's own low-pass, 100 as it is"))
      (doc "Close every voice's low-pass, those playing and those to come, to PCT percent of its own: the whole mix duller, as through a wall."
        (returns VECTOR "The mixer")
        (sample "(Mixer cut! m 30)" "m"))
      (%cut! m pct))

    (method cut (self (param m VECTOR "A mixer"))
      (doc "The percent of its own low-pass every voice is played through."
        (returns INTEGER "1 to 100")
        (sample "(Mixer cut m)" "100"))
      (%get m %m-cut))

    (method gain! (self (param m VECTOR "A mixer")
                        (param pct INTEGER "Percent of full scale, 0 for silence"))
      (doc "Set the gain the mix is written out at, after its effects."
        (returns VECTOR "The mixer")
        (sample "(Mixer gain! m 70)" "m"))
      (%put! m %m-gain (int/ (int* pct 256) 100))
      m)

    (method block! (self (param m VECTOR "A mixer"))
      (doc "Render the next block: its frames, the block's frame count times 4 bytes of a region the next block! writes again, left then right a frame, signed 16-bit little-endian."
        (returns STRING "The region; its first 4 x BLOCK bytes are the frames")
        (sample "(Sdl audio-put! s (Mixer block! m) 2048)" "2048"))
      (%block! m))

    (method clock (self (param m VECTOR "A mixer"))
      (doc "Frames rendered so far: the frame the next block starts at."
        (returns INTEGER "The frame")
        (sample "(Mixer clock m)" "0"))
      (%get m %m-clock))

    (method rate (self (param m VECTOR "A mixer"))
      (doc "The mixer's frames a second."
        (returns INTEGER "The rate")
        (sample "(Mixer rate m)" "44100"))
      (%get m %m-rate))

    (method playing (self (param m VECTOR "A mixer"))
      (doc "How many voices are playing or waiting to start."
        (returns INTEGER "The count")
        (sample "(Mixer playing m)" "0"))
      (List length (%get m %m-voices)))

    (method render (self (param rate INTEGER "Frames a second")
                         (param specs LIST "Voices, as play! takes them")
                         (param echoes LIST "Each (MS FB WET), as echo! takes them; () for none"))
      (doc "A sound rendered alone, from its start until its last voice and its echoes have died away, ready to queue whole on a stream: a sound effect made once and played many times."
        (returns PAIR "(REGION . BYTES): BYTES of stereo frames from the region's start")
        (sample "(Mixer render 44100 (list (list (list (lit hz) 220))) ())" "(region . 36864)"))
      (%render rate specs echoes))

    (method wave (self (param name SYMBOL "sine, noise, or a name given to wave!"))
      (doc "A wave table: one cycle of the wave, or for noise 32768 random words, read by a voice at its pitch. Raises a label 'value for a name with no wave."
        (returns LIST "(REGION ADDRESS SHIFT): a voice's phase shifted right by SHIFT is the word to read")
        (example "(List ref 2 (Mixer wave (lit noise)))" "17"))
      (%wave name))

    (method wave! (self (param name SYMBOL "The wave's name")
                        (param amps LIST "Each harmonic's amplitude, from the fundamental: integers, any scale, negative inverted"))
      (doc "Make a wave of harmonics, for voices to name: a sine at each multiple of the pitch, weighted by AMPS and scaled so the sum never passes the sine's peak. (1) is the sine; (4 0 1) a hollow organ; (6 3 2 1) a soft saw."
        (returns SYMBOL "NAME")
        (example "(Mixer wave! (lit hollow) (list 4 0 1))" "'hollow"))
      (%wave-put! name (%harmonic-wave amps))
      name)

    (method semitone (self (param name STRING "A note's name, such as \"A4\", \"F#2\" or \"Bb3\""))
      (doc "A note as semitones above C0: the difference of two is the interval between them. Raises a label 'value for a name that is no note."
        (returns INTEGER "Semitones")
        (example "(list (Mixer semitone \"C4\") (Mixer semitone \"A4\") (Mixer semitone \"Bb3\"))" "(48 57 46)"))
      (%note-semi name))

    (method step (self (param pitch ANY "A note's name, such as \"A4\" or \"F#2\", or hertz")
                       (param rate INTEGER "Frames a second"))
      (doc "The phase a frame a voice steps at for PITCH: 2^32 is a whole cycle."
        (returns INTEGER "The step")
        (example "(Mixer step \"A4\" 44100)" "42852281"))
      (%step (%pitch-mhz pitch) rate))

    (method jit! (self)
      (doc "Build and adopt the compiled loops (JIT; ARM64 and x86-64 backends) now, if they agree with the pure-x loops. Idempotent. Answers #t when they are in use: the pure-x loops make the same frames, but far too slowly to keep a stream playing."
        (returns BOOL "#t when the compiled loops are in use")
        (sample "(Mixer jit!)" "#t"))
      (%jit-try!))))

(doc (provide x/audio/mixer Mixer)
  "Sound synthesised and mixed in x: wave tables, voices with envelopes, pitch slides, low-pass and pan, effects over the mix (echoes, a reverb, a phaser), a pitch and a cut moving every voice, and stereo signed 16-bit frames a block at a time for (Sdl audio-put!), the per-frame loops compiled and checked against pure x."
  (example "(List ref 2 (Mixer wave (lit sine)))" "21"))
