; mixer.x -- Mixer: voices synthesised from wave tables, mixed to stereo
; signed 16-bit frames, block by block, for a stream to play.
;
; A voice is one oscillator: a wave table read at a pitch, shaped by an
; envelope of straight lines between points, through a one-pole low-pass,
; and placed left or right.  A sound is a list of voices.  A mixer renders
; the voices playing a block at a time into a buffer of frames, with
; echoes over the mix, and at each block's boundary and at any frame a
; source asks for, it hands the time to its sources (a tracker, a pulse)
; which start the voices due then.
;
; Everything is integers.  A phase is 32 bits of a cycle, a step the phase
; a frame; a level is 0 to 2^24; a gain or a pan weight is 0 to 256.
; Times in a voice's description are milliseconds, levels percent.
;
; The loops that touch every frame are seven kernels, each written once
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
      (self m (+ i 1) n tab sh (& (+ ph st) 4294967295) (+ st ds) ds (+ vol dv) dv
            (%mem-set-at! m i (+ y (>> (* (- (>> (* (%mem-ref-at tab (>> ph sh)) (>> vol 8)) 16) y) k) 16)))
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

; Words I to N of stereo buffer A through the delay line R of LEN words
; (an even number, so each channel echoes itself), at P: D is the word at
; P, LEN words ago.  The mix gets D at WET; the line gets the mix plus the
; mean of D and the word after it in its channel at FB, a little duller
; each time round.  Answers the place after the last word.
(def %echo-form
  (lit (fn (self a r i n p len fb wet d)
    (if (< i n)
      (do (%mem-set-at! r p (+ (%mem-ref-at a i)
                               (>> (* (+ d (%mem-ref-at r (if (< (+ p 2) len) (+ p 2) (- (+ p 2) len)))) fb) 9)))
          (%mem-set-at! a i (+ (%mem-ref-at a i) (>> (* d wet) 8)))
          (self a r (+ i 1) n (if (< (+ p 1) len) (+ p 1) 0) len fb wet
                (%mem-ref-at r (if (< (+ p 1) len) (+ p 1) 0))))
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
          (self t (+ i 1) n (- c (>> (* s e) 30)) (+ s (>> (* (- c (>> (* s e) 30)) e) 30)) e))
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

(def %forms (list %osc-form %mix-form %echo-form %out-form %sine-form %harm-form %noise-form))

(def %pure (List map int-form-pure %forms))

; --- The kernels in use ----------------------------------------------------

(def %k-osc ())
(def %k-mix ())
(def %k-echo ())
(def %k-out ())
(def %k-sine ())
(def %k-harm ())
(def %k-noise ())

(def %install!
  (fn (_ ks)
    (set! %k-osc (List ref 0 ks))
    (set! %k-mix (List ref 1 ks))
    (set! %k-echo (List ref 2 ks))
    (set! %k-out (List ref 3 ks))
    (set! %k-sine (List ref 4 ks))
    (set! %k-harm (List ref 5 ks))
    (set! %k-noise (List ref 6 ks))))

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
            (fn (_ k d e) (k d e 0 64 5 60 300 90 (%wref e 5)))
            (fn (_ k d e) (k d e 0 64 300))
            (fn (_ k d _) (k d 0 64 1073709056 0 102943708))
            (fn (_ k d e) (k d e 0 64 3 -90 63))
            (fn (_ k d _) (k d 0 64 977))))
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
      (list 0 1 2 3 4 5 6))))

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

; Note NAME, such as "C4", "F#3" or "Bb2", as thousandths of a hertz.
(def %note-mhz
  (fn (_ name)
    (def n (str-byte-len name))
    (def letter (List find (fn (_ e) (str=? (first e) (Str8 sub 0 1 name))) %letters))
    (when (or (null? letter) (int< n 2)) (%fail (Str8 append "not a note: " name)))
    (def accidental (Str8 sub 1 1 name))
    (def shift (match ((str=? accidental "#") 1) ((str=? accidental "b") -1) (#t 0)))
    (def at (if (int= shift 0) 1 2))
    (def octave (if (int= n (int+ at 1)) (int- (char->int (str-byte-ref name at)) 48) -1))
    (when (or (int< octave 0) (int< 9 octave)) (%fail (Str8 append "not a note: " name)))
    (def semi (int+ (rest letter) shift))
    (def oct (int+ octave (match ((int< semi 0) -1) ((int< 11 semi) 1) (#t 0))))
    (def f (List ref (int% (int+ semi 12) 12) %octave4))
    (if (int< oct 4) (int>> f (int- 4 oct)) (int<< f (int- oct 4)))))

; The step a frame for thousandths of a hertz MHZ at RATE frames a second.
(def %step (fn (_ mhz rate) (int/ (int<< mhz 32) (int* rate 1000))))

; A pitch as a voice gives it: a note's name, or (hz N).
(def %pitch-mhz
  (fn (_ p)
    (if (str? p) (%note-mhz p) (int* p 1000))))

; STEP moved CENTS cents, close enough for the few a chorus is detuned.
(def %detune (fn (_ step cents) (int+ step (int/ (int* step (int* cents 5778)) 10000000))))

; --- Voices ----------------------------------------------------------------
;
; A voice is a vector record: its wave's table and shift, phase, step,
; step's step, level, low-pass output and coefficient, left and right
; weights, the frame it has reached (negative before it starts), and its
; envelope's points still ahead, ((FRAME . LEVEL) ...), from its start.

(def %vector-type ((prim-ref (lit type) (lit of)) (Vector make 0 ())))
(def %rec (fn (_ n) ((fn (_ r) (do (obj-set! r 0 n) r)) (obj-make %vector-type (int+ n 1)))))
(def %get (fn (_ r k) (obj-ref r (int+ k 1))))
(def %put! (fn (_ r k x) (obj-set! r (int+ k 1) x)))

(def %v-tab 0) (def %v-sh 1) (def %v-ph 2) (def %v-st 3) (def %v-ds 4) (def %v-vol 5)
(def %v-y 6) (def %v-k 7) (def %v-gl 8) (def %v-gr 9) (def %v-t 10) (def %v-env 11) (def %v-wave 12)

(def %prop
  (fn (_ spec key default)
    (def hit (List find (fn (_ f) (if (pair? f) (eq? (first f) key) #f)) spec))
    (if (null? hit) default (rest hit))))
(def %prop1 (fn (_ spec key default) ((fn (_ v) (if (null? v) default (first v))) (%prop spec key ()))))

(def %ms (fn (_ ms rate) (int/ (int* ms rate) 1000)))
(def %level (fn (_ pct gain) (int/ (int* (int<< pct 24) gain) 10000)))

; Voice SPEC at RATE, starting AT frames after the block's start, at GAIN
; percent.  SPEC is a list of (KEY ...): (wave NAME), (env (MS PCT) ...),
; a pitch (note "C4") or (hz N), (slide PITCH), (cut PCT), (pan -100..100),
; (gain PCT), (detune CENTS), (at MS).
(def %voice
  (fn (_ spec rate at gain)
    (def w (%wave (%prop1 spec (lit wave) (lit sine))))
    (def g (int/ (int* gain (%prop1 spec (lit gain) 100)) 100))
    (def env (List map (fn (_ p) (pair (%ms (first p) rate) (%level (first (rest p)) g)))
                   (%prop spec (lit env) (lit ((0 100) (200 0))))))
    (def len (if (null? env) 0 (first (List ref -1 env))))
    (def pitch (%prop1 spec (lit note) ()))
    (def mhz (if (null? pitch) (int* 1000 (%prop1 spec (lit hz) 440)) (%note-mhz pitch)))
    (def st (%detune (%step mhz rate) (%prop1 spec (lit detune) 0)))
    (def slide (%prop1 spec (lit slide) ()))
    (def st1 (if (null? slide) st (%detune (%step (%pitch-mhz slide) rate) (%prop1 spec (lit detune) 0))))
    (def cut (%prop1 spec (lit cut) 100))
    (def pan (%prop1 spec (lit pan) 0))
    (def v (%rec 13))
    (%put! v %v-tab (List ref 1 w))
    (%put! v %v-sh (List ref 2 w))
    (%put! v %v-ph 0)
    (%put! v %v-st st)
    (%put! v %v-ds (if (int< 0 len) (int/ (int- st1 st) len) 0))
    (%put! v %v-vol 0)
    (%put! v %v-y 0)
    (%put! v %v-k (int/ (int* (if (int< 100 cut) 100 (if (int< cut 1) 1 cut)) 65536) 100))
    (%put! v %v-gl (int/ (int* (int- 100 pan) 256) 200))
    (%put! v %v-gr (int/ (int* (int+ 100 pan) 256) 200))
    (%put! v %v-t (int- 0 (int+ at (%ms (%prop1 spec (lit at) 0) rate))))
    (%put! v %v-env env)
    (%put! v %v-wave w)
    v))

; Voice V rendered over frames A to B of the block into mono buffer M and
; added into stereo buffer S.  Answers #t while the voice has more to play.
(def %voice-render!
  (fn (_ v m s a b)
    (def t (%get v %v-t))
    (match
      ((not (int< (int+ t (int- b a)) 1)) ; under way, or starting in this stretch
        ((fn (self from)
           (def env (%get v %v-env))
           (match
             ((null? env) #f)
             ((not (int< from b)) #t)
             (#t
               (do (def tt (%get v %v-t))
                   (def point (first env))
                   (def left (int- (first point) tt))
                   (def to (if (int< (int+ from left) b) (int+ from left) b))
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
; and the echoes, each a record of its line, place, feedback and wet.

(def %m-rate 0) (def %m-block 1) (def %m-acc 2) (def %m-acc-a 3) (def %m-mono 4) (def %m-mono-a 5)
(def %m-out 6) (def %m-out-a 7) (def %m-gain 8) (def %m-clock 9) (def %m-voices 10) (def %m-sources 11)
(def %m-echoes 12)

(def %make
  (fn (_ rate block)
    (when (int< rate 1000) (%fail "make: RATE is 1000 frames a second or more"))
    (when (int< block 16) (%fail "make: BLOCK is 16 frames or more"))
    (%jit-try!)
    (def m (%rec 13))
    (def acc (%words (int* 2 block)))
    (def mono (%words block))
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
    (%put! m %m-echoes ())
    m))

; Voices from the list SPECS started AT frames from now, at GAIN percent.
(def %play!
  (fn (_ m specs at gain)
    (def rate (%get m %m-rate))
    (%put! m %m-voices
      (List fold (fn (_ acc s) (pair (%voice s rate at gain) acc)) (%get m %m-voices) specs))
    m))

(def %echo!
  (fn (_ m ms fb wet)
    (def len (int* 2 (if (int< 0 (%ms ms (%get m %m-rate))) (%ms ms (%get m %m-rate)) 1)))
    (def e (%rec 6))
    (def line (%words len))
    (%put! e 0 line) (%put! e 1 (%addr line)) (%put! e 2 len) (%put! e 3 0)
    (%put! e 4 (int/ (int* fb 256) 100)) (%put! e 5 (int/ (int* wet 256) 100))
    (%put! m %m-echoes (List append (%get m %m-echoes) (list e)))
    m))

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

; One block: the sources' due frames split it into stretches, the echoes
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
      (fn (_ e)
        (%put! e 3 (%k-echo (%get m %m-acc-a) (%get e 1) 0 (int* 2 b) (%get e 3) (%get e 2) (%get e 4) (%get e 5)
                            (%wref (%get e 1) (%get e 3)))))
      (%get m %m-echoes))
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
    (see make) (see block!) (see voice) (see source!))
  (static
    (method make (self (param rate INTEGER "Frames a second, 1000 or more")
                       (param block INTEGER "Frames a block, 16 or more"))
      (doc "A mixer with no voices playing, at full gain. Builds the compiled loops the first time, as (Mixer jit!) does."
        (returns VECTOR "The mixer")
        (sample "(Mixer make 44100 512)" "a mixer"))
      (%make rate block))

    (method play! (self (param m VECTOR "A mixer")
                        (param specs LIST "Voices, each a list of (KEY ...): (wave NAME), (env (MS PCT) ...), (note \"C4\") or (hz N), (slide PITCH), (cut PCT), (pan -100..100), (gain PCT), (detune CENTS), (at MS)")
                        (param at INTEGER "Frames after the start of the stretch being rendered, 0 at once")
                        (param gain INTEGER "Percent of each voice's own gain"))
      (doc "Start a sound: each voice plays its envelope from AT, its pitch sliding to its slide's over the envelope, and ends at the envelope's last point. A voice with no wave is a sine; with no envelope, a 200 ms fade."
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
      (doc "Add an echo over everything the mixer renders, after any added before it: the mix delayed by MS, each repeat duller than the last."
        (returns VECTOR "The mixer")
        (sample "(Mixer echo! m 370 45 30)" "m"))
      (%echo! m ms fb wet))

    (method gain! (self (param m VECTOR "A mixer")
                        (param pct INTEGER "Percent of full scale, 0 for silence"))
      (doc "Set the gain the mix is written out at, after its echoes."
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
  "Sound synthesised and mixed in x: wave tables, voices with envelopes, pitch slides, low-pass and pan, echoes, and stereo signed 16-bit frames a block at a time for (Sdl audio-put!), the per-frame loops compiled and checked against pure x."
  (example "(List ref 2 (Mixer wave (lit sine)))" "21"))
