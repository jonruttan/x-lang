# Mixer: voices from wave tables, mixed to stereo signed 16-bit frames
# @weight 3

A mixer renders a block of frames at a time. The cases read the frames
back as signed 16-bit words; the last section renders one scene with the
pure-x loops and again with the compiled ones, byte for byte.

## pitch and waves

### a note's step is its share of a cycle a frame

```x
(do (import x/audio/mixer)
  (list (Mixer step "A4" 44100) (Mixer step "A3" 44100) (Mixer step "C#5" 48000) (Mixer step 1000 44100)))
```
---
    (42852281 21426140 49603830 97391548)

### a name that is no note raises

```x
(do (import x/audio/mixer)
  (guard (e (Err text e)) (Mixer step "H4" 44100)))
```
---
    "Mixer: not a note: H4"

### the sine is zero, its peak, zero and its trough a quarter cycle apart

```x
(do (import x/audio/mixer) (import x/core/doors ptr-ref-word int->ptr)
  (def w (Mixer wave (lit sine)))
  (def at (fn (_ i) (ptr-ref-word (int->ptr (List ref 1 w)) (* i %word-size))))
  (list (at 0) (< 32700 (at 512)) (< (at 1024) 50) (< -50 (at 1024)) (< (at 1536) -32700)))
```
---
    (0 #t #t #t #t)

### harmonics are scaled so their sum never passes the sine's peak

```x
(do (import x/audio/mixer) (import x/core/doors ptr-ref-word int->ptr)
  (Mixer wave! (lit square3) (list 3 0 1))
  (def w (Mixer wave (lit square3)))
  (def peak (let go ((i 0) (m 0))
              (if (< i 2048) (go (+ i 1) ((fn (_ v) (if (< m v) v m)) (ptr-ref-word (int->ptr (List ref 1 w)) (* i %word-size)))) m)))
  (list (< peak 32768) (< 20000 peak)))
```
---
    (#t #t)

### a square is high for half the cycle and low for the other half

```x
(do (import x/audio/mixer) (import x/core/doors ptr-ref-word int->ptr)
  (def w (Mixer wave (lit square)))
  (let go ((i 0) (hi 0) (lo 0))
    (if (< i 2048)
      ((fn (_ v) (go (+ i 1) (if (= v 32767) (+ hi 1) hi) (if (= v -32767) (+ lo 1) lo))) (ptr-ref-word (int->ptr (List ref 1 w)) (* i %word-size)))
      (list hi lo))))
```
---
    (1024 1024)

### a triangle rises to full scale at a quarter cycle and falls to its floor at three quarters

```x
(do (import x/audio/mixer) (import x/core/doors ptr-ref-word int->ptr)
  (def w (Mixer wave (lit triangle)))
  (def at (fn (_ i) (ptr-ref-word (int->ptr (List ref 1 w)) (* i %word-size))))
  (list (at 0) (at 256) (at 512) (at 1024) (at 1536) (at 1792)))
```
---
    (0 16384 32767 0 -32767 -16384)

### a saw rises and drops at half cycle, and the inverse saw is its negative word for word

```x
(do (import x/audio/mixer) (import x/core/doors ptr-ref-word int->ptr)
  (def saw (Mixer wave (lit saw)))
  (def inv (Mixer wave (lit inverse-saw)))
  (def at (fn (_ w i) (ptr-ref-word (int->ptr (List ref 1 w)) (* i %word-size))))
  (list (at saw 512) (at saw 1023) (at saw 1024)
        (let go ((i 0)) (if (< i 2048) (if (= 0 (+ (at saw i) (at inv i))) (go (+ i 1)) i) #t))))
```
---
    (16384 32735 -32767 #t)

### metal is 127 steps of full-scale noise in a table of 128 words, repeating

```x
(do (import x/audio/mixer) (import x/core/doors ptr-ref-word int->ptr)
  (def w (Mixer wave (lit metal)))
  (def at (fn (_ i) (ptr-ref-word (int->ptr (List ref 1 w)) (* i %word-size))))
  (list (List ref 2 w) (= (at 0) (at 127))
        (let go ((i 0) (n 0)) (if (< i 127) (go (+ i 1) (if (= 32767 (at i)) (+ n 1) n)) n))
        (let go ((i 0)) (if (< i 128) (if (= 32767 ((fn (_ v) (if (< v 0) (- 0 v) v)) (at i))) (go (+ i 1)) #f) #t))))
```
---
    (25 #t 64 #t)

### a wave drawn by points: straight lines, jumps where two points share a position

```x
(do (import x/audio/mixer) (import x/core/doors ptr-ref-word int->ptr)
  (Mixer shape! (lit ramp) (list (list 0 -50) (list 1 50) (list 1 0) (list 4 0)))
  (def w (Mixer wave (lit ramp)))
  (def at (fn (_ i) (ptr-ref-word (int->ptr (List ref 1 w)) (* i %word-size))))
  (list (at 0) (at 256) (at 511) (at 512) (at 2047)))
```
---
    (-16383 0 16319 0 0)

### points out of order or range raise

```x
(do (import x/audio/mixer)
  (def tries (fn (_ points) (guard (e (Err text e)) (Mixer shape! (lit bad) points))))
  (List map tries (list (list (list 1 0) (list 2 0))
                        (list (list 0 0) (list 2 50) (list 1 0))
                        (list (list 0 0) (list 1 101))
                        (list (list 0 0))
                        (list 3))))
```
---
    ("Mixer: wave: the first point is at position 0" "Mixer: wave: positions never fall" "Mixer: wave: levels are -100 to 100" "Mixer: wave: the last point's position is past 0" "Mixer: wave: points are (POSITION LEVEL) pairs of integers")

### a song's voice plays a shaped wave by name, its low half the mirror of its high

```x
(do (import x/audio/mixer) (import x/core/doors ptr-ref str->ptr)
  (def m (Mixer make 8000 256))
  (Mixer play! m (list (list (list (lit wave) (lit square)) (list (lit hz) 250) (list (lit env) (list 0 100) (list 100 100)))) 0 100)
  (def b (Mixer block! m))
  (def word (fn (_ i) ((fn (_ u) (if (< 32767 u) (- u 65536) u)) (+ (ptr-ref (str->ptr b) (* 4 i) 1) (* 256 (ptr-ref (str->ptr b) (+ (* 4 i) 1) 1))))))
  (def mirror (fn (_ a b) (if (< (+ a b) 3) (< -3 (+ a b)) #f)))
  (list (< 0 (word 4)) (< 0 (word 10)) (mirror (word 4) (word 20)) (mirror (word 10) (word 26))))
```
---
    (#t #t #t #t)

### a pulse is the saw at a width: high for that share of the cycle, within a frame at its band-limited edges, and a moving width sweeps it

```x
(do (import x/audio/mixer) (import x/core/doors ptr-ref str->ptr)
  (def word (fn (_ b i) ((fn (_ u) (if (< 32767 u) (- u 65536) u)) (+ (ptr-ref (str->ptr b) (* 4 i) 1) (* 256 (ptr-ref (str->ptr b) (+ (* 4 i) 1) 1))))))
  (def highs (fn (_ b from) (let go ((i from) (n 0)) (if (< i (+ from 32)) (go (+ i 1) (if (< 0 (word b i)) (+ n 1) n)) n))))
  (def pulse (fn (_ keys)
               (def m (Mixer make 8000 256))
               (Mixer play! m (list (List append (list (list (lit wave) (lit pulse)) (list (lit hz) 250) (list (lit env) (list 0 100) (list 100 100))) keys)) 0 100)
               (def a (highs (Mixer block! m) 0))
               (list a (highs (Mixer block! m) 0))))
  (def fixed (pulse (list (list (lit width) (list 0 25)))))
  (def square (pulse ()))
  (def sweep (pulse (list (list (lit width) (list 0 25) (list 32 75)))))
  (def near (fn (_ n want) (if (< (- want 2) n) (< n (+ want 2)) #f)))
  (list (near (first fixed) 8) (near (first square) 16) (near (first sweep) 8) (near (List ref 1 sweep) 24)))
```
---
    (#t #t #t #t)

### a square at a quarter of the frame rate plays as its fundamental alone, rising from zero

```x
(do (import x/audio/mixer) (import x/core/doors ptr-ref str->ptr)
  (def m (Mixer make 8000 256))
  (Mixer play! m (list (list (list (lit wave) (lit square)) (list (lit hz) 2000) (list (lit env) (list 0 100) (list 100 100)))) 0 100)
  (def b (Mixer block! m))
  (def word (fn (_ i) ((fn (_ u) (if (< 32767 u) (- u 65536) u)) (+ (ptr-ref (str->ptr b) (* 4 i) 1) (* 256 (ptr-ref (str->ptr b) (+ (* 4 i) 1) 1))))))
  (def small (fn (_ v) (if (< -300 v) (< v 300) #f)))
  (list (small (word 8)) (< 1000 (word 9)) (small (word 10)) (< (+ (word 9) (word 11)) 3) (< -3 (+ (word 9) (word 11)))))
```
---
    (#t #t #t #t #t)

## samples and cycles

### a sample at its root plays its frames as they are, once, and the voice ends with it

```x
(do (import x/audio/mixer) (import x/codec/bytes) (import x/core/doors ptr-ref str->ptr)
  (Mixer sample! (lit spec-hit) (first (Bytes of-hex "803e80c1401f0000")) 4 8000 "C4")
  (def m (Mixer make 8000 256))
  (Mixer play! m (list (list (list (lit wave) (lit spec-hit)) (list (lit note) "C4"))) 0 100)
  (def b (Mixer block! m))
  (def word (fn (_ i) ((fn (_ u) (if (< 32767 u) (- u 65536) u)) (+ (ptr-ref (str->ptr b) (* 4 i) 1) (* 256 (ptr-ref (str->ptr b) (+ (* 4 i) 1) 1))))))
  (list (< 1000 (word 0)) (= (word 1) (- 0 (word 0))) (= (* 2 (word 2)) (word 0)) (word 3) (word 4) (word 40) (Mixer playing m)))
```
---
    (#t #t #t 0 0 0 0)

### an octave above its root, a sample reads every other frame

```x
(do (import x/audio/mixer) (import x/codec/bytes) (import x/core/doors ptr-ref str->ptr)
  (Mixer sample! (lit spec-hit) (first (Bytes of-hex "803e80c1401f0000")) 4 8000 "C4")
  (def m (Mixer make 8000 256))
  (Mixer play! m (list (list (list (lit wave) (lit spec-hit)) (list (lit note) "C5"))) 0 100)
  (def b (Mixer block! m))
  (def word (fn (_ i) ((fn (_ u) (if (< 32767 u) (- u 65536) u)) (+ (ptr-ref (str->ptr b) (* 4 i) 1) (* 256 (ptr-ref (str->ptr b) (+ (* 4 i) 1) 1))))))
  (list (< 1000 (word 0)) (= (* 2 (word 1)) (word 0)) (word 2) (word 3)))
```
---
    (#t #t 0 0)

### a looped sample goes back to its loop's start at its end, until its envelope ends

```x
(do (import x/audio/mixer) (import x/codec/bytes) (import x/core/doors ptr-ref str->ptr)
  (Mixer sample! (lit spec-loop) (first (Bytes of-hex "803e80c1401f0000")) 4 8000 "C4" 1 3)
  (def m (Mixer make 8000 256))
  (Mixer play! m (list (list (list (lit wave) (lit spec-loop)) (list (lit note) "C4") (list (lit env) (list 0 100) (list 100 100)))) 0 100)
  (def b (Mixer block! m))
  (def word (fn (_ i) ((fn (_ u) (if (< 32767 u) (- u 65536) u)) (+ (ptr-ref (str->ptr b) (* 4 i) 1) (* 256 (ptr-ref (str->ptr b) (+ (* 4 i) 1) 1))))))
  (list (< (word 1) 0) (= (word 3) (word 1)) (= (word 4) (word 2)) (= (word 5) (word 1)) (= (word 255) (word 1)) (Mixer playing m)))
```
---
    (#t #t #t #t #t 1)

### a recorded cycle plays band-limited: at a quarter of the frame rate, its fundamental alone, at the cycle's phase

```x
(do (import x/audio/mixer) (import x/codec/bytes) (import x/core/doors ptr-ref str->ptr)
  (Mixer cycle! (lit spec-eight) (first (Bytes of-hex "ff7fff7fff7fff7f0180018001800180")) 8)
  (def m (Mixer make 8000 256))
  (Mixer play! m (list (list (list (lit wave) (lit spec-eight)) (list (lit hz) 2000) (list (lit env) (list 0 100) (list 100 100)))) 0 100)
  (def b (Mixer block! m))
  (def word (fn (_ i) ((fn (_ u) (if (< 32767 u) (- u 65536) u)) (+ (ptr-ref (str->ptr b) (* 4 i) 1) (* 256 (ptr-ref (str->ptr b) (+ (* 4 i) 1) 1))))))
  (def mirror (fn (_ a b) (if (< (+ a b) 3) (< -3 (+ a b)) #f)))
  (list (< 0 (word 8)) (< (word 8) (word 9)) (mirror (word 8) (word 10)) (mirror (word 9) (word 11))))
```
---
    (#t #t #t #t)

### a recorded cycle is drawn as straight lines between its frames across the whole table

```x
(do (import x/audio/mixer) (import x/codec/bytes) (import x/core/doors ptr-ref-word int->ptr)
  (Mixer cycle! (lit spec-ramp) (first (Bytes of-hex "00000020004000600080")) 5)
  (def w (Mixer wave (lit spec-ramp)))
  (def at (fn (_ i) (ptr-ref-word (int->ptr (List ref 1 w)) (* i %word-size))))
  (list (List ref 2 w) (< (at 0) (at 400)) (< (at 400) (at 800)) (< (at 1640) (at 0))))
```
---
    (21 #t #t #t)

### a loop out of the sound, and a cycle too short to hold a harmonic, raise

```x
(do (import x/audio/mixer) (import x/codec/bytes)
  (def pcm (first (Bytes of-hex "803e80c1401f0000")))
  (list (guard (e (Err text e)) (Mixer sample! (lit spec-bad) pcm 4 8000 "C4" 2 9))
        (guard (e (Err text e)) (Mixer sample! (lit spec-bad) pcm 4 8000 "C4" 3 1))
        (guard (e (Err text e)) (Mixer cycle! (lit spec-bad) pcm 2))))
```
---
    ("Mixer: sample: a loop's start is before its end, both within the sound" "Mixer: sample: a loop's start is before its end, both within the sound" "Mixer: cycle: a cycle needs at least 3 frames")

## rendering

### a voice plays from its start, and the block is silent after it ends

```x
(do (import x/audio/mixer) (import x/core/doors ptr-ref str->ptr)
  (def m (Mixer make 8000 256))
  (Mixer play! m (list (list (list (lit hz) 500) (list (lit env) (list 0 100) (list 10 100) (list 20 0)))) 40 100)
  (def b (str->ptr (Mixer block! m)))
  (def s16 (fn (_ i) ((fn (_ u) (if (< u 32768) u (- u 65536))) (+ (ptr-ref b (* 2 i) 1) (* 256 (ptr-ref b (+ 1 (* 2 i)) 1))))))
  (def loud (fn (self i n acc) (if (< i n) (self (+ i 1) n (+ acc (if (= 0 (s16 i)) 0 1))) acc)))
  (list (loud 0 80 0) (< 100 (loud 80 400 0)) (loud 400 512 0) (Mixer playing m)))
```
---
    (0 #t 0 0)

### pan sends a voice to one side

```x
(do (import x/audio/mixer) (import x/core/doors ptr-ref str->ptr)
  (def m (Mixer make 8000 256))
  (Mixer play! m (list (list (list (lit hz) 400) (list (lit pan) -100) (list (lit env) (list 0 100) (list 30 100)))) 0 100)
  (def b (str->ptr (Mixer block! m)))
  (def side (fn (self i ch acc) (if (< i 256) (self (+ i 1) ch (+ acc (if (= 0 (+ (ptr-ref b (+ ch (* 4 i)) 1) (ptr-ref b (+ ch 1 (* 4 i)) 1))) 0 1))) acc)))
  (list (< 200 (side 0 0 0)) (side 0 2 0)))
```
---
    (#t 0)

### a source is called at the frames it asks for

```x
(do (import x/audio/mixer)
  (def m (Mixer make 8000 256))
  (def seen (pair () ()))
  (Mixer source! m (fn (_ m now) (do (%set-first! seen (pair now (first seen))) (if (< now 600) (+ now 100) ()))) 30)
  (Mixer block! m) (Mixer block! m) (Mixer block! m)
  (List reverse (first seen)))
```
---
    (30 130 230 330 430 530 630)

### a sound rendered alone lasts its longest voice, in whole blocks

```x
(do (import x/audio/mixer)
  (rest (Mixer render 8000 (list (list (list (lit env) (list 0 0) (list 300 0))) (list (list (lit at) 100) (list (lit env) (list 0 0) (list 200 0)))) ())))
```
---
    12288

## the mixer's pitch and cut

### a pitch an octave down plays A4 as A3, set before the note or while it plays

```x
(do (import x/audio/mixer) (import x/core/doors mem-cmp str->ptr)
  (def tone (fn (_ note) (list (list (list (lit note) note) (list (lit env) (list 0 90) (list 100 90))))))
  (def a3 (Mixer make 8000 256))
  (Mixer play! a3 (tone "A3") 0 100)
  (def before (Mixer make 8000 256))
  (Mixer pitch! before -1200)
  (Mixer play! before (tone "A4") 0 100)
  (def during (Mixer make 8000 256))
  (Mixer play! during (tone "A4") 0 100)
  (Mixer pitch! during -1200)
  (def want (Mixer block! a3))
  (list (mem-cmp (str->ptr want) (str->ptr (Mixer block! before)) 1024)
        (mem-cmp (str->ptr want) (str->ptr (Mixer block! during)) 1024)
        (Mixer pitch before)))
```
---
    (0 0 -1200)

### a pitch up a fifth plays C4 as G4, to within a step's rounding

```x
(do (import x/audio/mixer) (import x/core/doors ptr-ref str->ptr)
  (def tone (fn (_ note) (list (list (list (lit note) note) (list (lit env) (list 0 90) (list 100 90))))))
  (def g4 (Mixer make 8000 256))
  (Mixer play! g4 (tone "G4") 0 100)
  (def up (Mixer make 8000 256))
  (Mixer pitch! up 700)
  (Mixer play! up (tone "C4") 0 100)
  (def s16 (fn (_ r i) ((fn (_ u) (if (< u 32768) u (- u 65536))) (+ (ptr-ref (str->ptr r) (* 2 i) 1) (* 256 (ptr-ref (str->ptr r) (+ 1 (* 2 i)) 1))))))
  (def a (Mixer block! g4))
  (def b (Mixer block! up))
  ((fn (self i worst) (if (< i 512) (self (+ i 1) ((fn (_ d) (if (< worst d) d worst)) ((fn (_ d) (if (< d 0) (- 0 d) d)) (- (s16 a i) (s16 b i))))) (< worst 64)))
   0 0))
```
---
    #t

### a cut of half plays every voice as its own cut of half would

```x
(do (import x/audio/mixer) (import x/core/doors mem-cmp str->ptr)
  (def voice (fn (_ cut) (list (list (list (lit wave) (lit noise)) (list (lit hz) 3000) (list (lit cut) cut) (list (lit env) (list 0 90) (list 100 90))))))
  (def own (Mixer make 8000 256))
  (Mixer play! own (voice 50) 0 100)
  (def cut (Mixer make 8000 256))
  (Mixer cut! cut 50)
  (Mixer play! cut (voice 100) 0 100)
  (def open (Mixer make 8000 256))
  (Mixer play! open (voice 100) 0 100)
  (def a (Mixer block! own))
  (list (mem-cmp (str->ptr a) (str->ptr (Mixer block! cut)) 1024)
        (= 0 (mem-cmp (str->ptr a) (str->ptr (Mixer block! open)) 1024))
        (Mixer cut cut)))
```
---
    (0 #f 50)

### a bend holds its pitch to its point, then jumps

```x
(do (import x/audio/mixer) (import x/core/doors mem-cmp str->ptr)
  (def env (list (lit env) (list 0 90) (list 100 90)))
  (def low (Mixer make 8000 800))
  (Mixer play! low (list (list (list (lit note) "A3") env)) 0 100)
  (def bent (Mixer make 8000 800))
  (Mixer play! bent (list (list (list (lit note) "A4") env (list (lit bend) (list 0 -1200) (list 50 -1200) (list 50 0)))) 0 100)
  (def a (Mixer block! low))
  (def b (Mixer block! bent))
  (list (mem-cmp (str->ptr a) (str->ptr b) 1600) (= 0 (mem-cmp (str->ptr a) (str->ptr b) 3200))))
```
---
    (0 #f)

### a filter held at a percent plays as a cut of that percent, and a closing one dulls the voice

```x
(do (import x/audio/mixer) (import x/core/doors mem-cmp ptr-ref str->ptr)
  (def peak (fn (_ r) ((fn (self i acc) (if (< i 1024) (self (+ i 2) ((fn (_ v) (if (< acc v) v acc)) ((fn (_ w) (if (< w 0) (- 0 w) w)) ((fn (_ u) (if (< 32767 u) (- u 65536) u)) (+ (ptr-ref (str->ptr r) i 1) (* 256 (ptr-ref (str->ptr r) (+ i 1) 1))))))) acc)) 0 0)))
  (def tone (list (list (lit wave) (lit noise)) (list (lit hz) 2000) (list (lit env) (list 0 90) (list 200 90))))
  (def run (fn (_ v) (do (def m (Mixer make 8000 256)) (Mixer play! m (list v) 0 100) (Mixer block! m) (Mixer block! m))))
  (def closing (Mixer make 8000 256))
  (Mixer play! closing (list (pair (list (lit filter) (list 0 100) (list 64 2)) tone)) 0 100)
  (list (mem-cmp (str->ptr (run (pair (list (lit cut) 40) tone)))
                 (str->ptr (run (pair (list (lit filter) (list 0 40)) tone))) 1024)
        ((fn (_ a b c) (if (< b a) (< (* 10 c) a) #f)) (peak (Mixer block! closing)) (peak (Mixer block! closing)) (peak (Mixer block! closing)))))
```
---
    (0 #t)

### a resonant filter's low-pass dulls noise and its high-pass keeps the top, resonance rings at the cutoff, and a moving cutoff sweeps

```x
(do (import x/audio/mixer) (import x/core/doors mem-cmp ptr-ref str->ptr)
  (def word (fn (_ r i) ((fn (_ u) (if (< 32767 u) (- u 65536) u)) (+ (ptr-ref (str->ptr r) i 1) (* 256 (ptr-ref (str->ptr r) (+ i 1) 1))))))
  (def level (fn (_ r) ((fn (self i acc) (if (< i 1024) (self (+ i 2) ((fn (_ w) (+ acc (if (< w 0) (- 0 w) w))) (word r i))) acc)) 0 0)))
  (def run (fn (_ v) (do (def m (Mixer make 8000 256)) (Mixer play! m (list v) 0 100) (Mixer block! m) (Mixer block! m))))
  (def noise (list (list (lit wave) (lit noise)) (list (lit hz) 2000) (list (lit env) (list 0 90) (list 200 90))))
  (def tone (list (list (lit hz) 500) (list (lit env) (list 0 30) (list 200 30))))
  (def plain (level (run noise)))
  (list (< (* 4 (level (run (List append (list (list (lit cutoff) (list 0 150))) noise)))) plain)
        (< plain (* 2 (level (run (List append (list (list (lit cutoff) (list 0 150)) (list (lit pass) (lit high))) noise)))))
        (< (* 2 (level (run (List append (list (list (lit cutoff) (list 0 500))) tone))))
           (level (run (List append (list (list (lit cutoff) (list 0 500)) (list (lit res) 90)) tone))))
        (not (= 0 (mem-cmp (str->ptr (run (List append (list (list (lit cutoff) (list 0 300))) noise)))
                           (str->ptr (run (List append (list (list (lit cutoff) (list 0 300) (list 30 1000))) noise)))
                           1024)))))
```
---
    (#t #t #t #t)

### a ring turns the wave over with its modulator, its level kept, and a sync plays the wave until the modulator's cycle ends, then starts it again

```x
(do (import x/audio/mixer) (import x/core/doors mem-cmp ptr-ref str->ptr)
  (def word (fn (_ r i) ((fn (_ u) (if (< 32767 u) (- u 65536) u)) (+ (ptr-ref (str->ptr r) i 1) (* 256 (ptr-ref (str->ptr r) (+ i 1) 1))))))
  (def level (fn (_ r) ((fn (self i acc) (if (< i 1024) (self (+ i 2) ((fn (_ w) (+ acc (if (< w 0) (- 0 w) w))) (word r i))) acc)) 0 0)))
  (def run (fn (_ v) (do (def m (Mixer make 8000 256)) (Mixer play! m (list v) 0 100) (Mixer block! m))))
  (def tri (list (list (lit wave) (lit triangle)) (list (lit hz) 100) (list (lit env) (list 0 80) (list 200 80))))
  (def plain (run tri))
  (def ringed (run (pair (list (lit ring) 1200) tri)))
  (def synced (run (pair (list (lit sync) 1200) tri)))
  (list (= (level plain) (level ringed))
        (not (= 0 (mem-cmp (str->ptr plain) (str->ptr ringed) 1024)))
        (mem-cmp (str->ptr plain) (str->ptr synced) 156)
        (not (= 0 (mem-cmp (str->ptr plain) (str->ptr synced) 1024)))))
```
---
    (#t #t 0 #t)

## effects

### an effect is named, changed in its place and taken off

```x
(do (import x/audio/mixer)
  (def m (Mixer make 8000 256))
  (Mixer echo! m 40 50 30)
  (Mixer effect! m (lit room) (list (lit reverb) 100 80 30))
  (Mixer effect! m (lit sweep) (list (lit phase) 1 4 2000 50 70))
  (Mixer effect! m (lit room) (list (lit reverb) 100 60 20))
  (def changed (List map first (Mixer effects m)))
  (Mixer effect! m (lit room) ())
  (list changed (Mixer effects m)))
```
---
    ((() 'room 'sweep) ((() 'echo 40 50 30) ('sweep 'phase 1 4 2000 50 70)))

### an echo by name renders as echo! does

```x
(do (import x/audio/mixer) (import x/core/doors mem-cmp str->ptr)
  (def scene
    (fn (_ add!)
      (def m (Mixer make 8000 256))
      (add! m)
      (Mixer play! m (list (list (list (lit hz) 300) (list (lit env) (list 0 90) (list 20 0)))) 0 100)
      (Mixer block! m) (Mixer block! m)))
  (mem-cmp (str->ptr (scene (fn (_ m) (Mixer echo! m 25 50 40))))
           (str->ptr (scene (fn (_ m) (Mixer effect! m (lit e) (list (lit echo) 25 50 40)))))
           1024))
```
---
    0

### a convolve with a lone click gives back the dry sound at its wet

`click` makes a sample of FRAMES frames, silent but for LEVEL at frame
AT. A click at frame 0 at 100 wet adds the mix to itself, so it renders as
the mix without it at twice the gain, byte for byte, whatever the click's
level.

```x
(do (import x/audio/mixer) (import x/core/doors mem-cmp mem-copy mem-set ptr-set! str->ptr str-make int& int>>)
  (def keep (fn (_ r) (def c (str-make 1024)) (mem-copy (str->ptr c) (str->ptr r) 1024) c))
  (def click (fn (_ name frames at level)
    (def pcm (str-make (* 2 frames)))
    (mem-set (str->ptr pcm) 0 (* 2 frames))
    (ptr-set! (str->ptr pcm) (* 2 at) (int& level 255) 1)
    (ptr-set! (str->ptr pcm) (+ (* 2 at) 1) (int& (int>> level 8) 255) 1)
    (Mixer sample! name pcm frames 8000 "C4")))
  (def tone (list (list (list (lit hz) 300) (list (lit env) (list 0 40) (list 60 0)))))
  (def blocks (fn (_ m) (list (keep (Mixer block! m)) (keep (Mixer block! m)) (keep (Mixer block! m)))))
  (def same (fn (_ a b) (List all? (fn (_ k) (= 0 (mem-cmp (str->ptr (List ref k a)) (str->ptr (List ref k b)) 1024))) (list 0 1 2))))
  (def dry (fn (_)
    (def m (Mixer make 8000 256))
    (Mixer gain! m 200)
    (Mixer play! m tone 0 100)
    (blocks m)))
  (def wet (fn (_ name)
    (def m (Mixer make 8000 256))
    (Mixer effect! m (lit room) (list (lit convolve) name 100))
    (Mixer play! m tone 0 100)
    (blocks m)))
  (click (lit spec-click) 10 0 9000)
  (click (lit spec-soft) 10 0 3)
  (list (same (dry) (wet (lit spec-click))) (same (dry) (wet (lit spec-soft)))))
```
---
    (#t #t)

### a delayed click is an echo

A click at frame 300, past the first block of 256: the mix convolved with
it is the dry mix plus the dry mix 300 frames on, both channels, through
four blocks. At a gain of 100 a block's samples are the mix's words, so
the dry render's samples give the sum exactly; each block's count of
samples that differ from it is 0.

```x
(do (import x/audio/mixer) (import x/core/doors mem-copy mem-set ptr-ref ptr-set! str->ptr str-make)
  (def keep (fn (_ r) (def c (str-make 1024)) (mem-copy (str->ptr c) (str->ptr r) 1024) c))
  (def pcm (str-make 800))
  (mem-set (str->ptr pcm) 0 800)
  (ptr-set! (str->ptr pcm) 600 64 1)
  (Mixer sample! (lit spec-late) pcm 400 8000 "C4")
  (def tone (list (list (list (lit hz) 440) (list (lit pan) -30) (list (lit env) (list 0 50) (list 40 0)))))
  (def run (fn (_ m) ((fn (self k acc) (if (< k 4) (self (+ k 1) (pair (keep (Mixer block! m)) acc)) (List reverse acc))) 0 ())))
  (def s16 (fn (_ bs g)
    (def r (List ref (/ g 512) bs))
    (def i (* 2 (% g 512)))
    ((fn (_ v) (if (< 32767 v) (- v 65536) v)) (+ (ptr-ref (str->ptr r) i 1) (* 256 (ptr-ref (str->ptr r) (+ i 1) 1))))))
  (def a (Mixer make 8000 256))
  (Mixer effect! a (lit hall) (list (lit convolve) (lit spec-late) 100))
  (Mixer play! a tone 0 100)
  (def b (Mixer make 8000 256))
  (Mixer play! b tone 0 100)
  (def wet (run a))
  (def dry (run b))
  (def want (fn (_ g) (+ (s16 dry g) (if (< g 600) 0 (s16 dry (- g 600))))))
  (List map (fn (_ k) ((fn (self g n) (if (< g (* 512 (+ k 1))) (self (+ g 1) (if (= (s16 wet g) (want g)) n (+ n 1))) n)) (* 512 k) 0))
    (list 0 1 2 3)))
```
---
    (0 0 0 0)

### a convolve names a sample, takes a block of a power of two, and an impulse that is not silent

```x
(do (import x/audio/mixer) (import x/core/doors mem-set str->ptr str-make)
  (def pcm (str-make 16))
  (mem-set (str->ptr pcm) 0 16)
  (Mixer sample! (lit spec-hush) pcm 8 8000 "C4")
  (def try (fn (_ block name)
    (guard (e (Err text e)) (Mixer effect! (Mixer make 8000 block) (lit c) (list (lit convolve) name 50)))))
  (list (try 256 (lit sine)) (try 250 (lit spec-hush)) (try 256 (lit spec-hush))))
```
---
    ("Mixer: convolve: the wave is not a sample" "Mixer: convolve: the mixer's block is not a power of two" "Mixer: convolve: the sample is silent")

### a reverb rings on after the voice, and a phase changes what is heard

```x
(do (import x/audio/mixer) (import x/core/doors ptr-ref mem-cmp str->ptr)
  (def loud (fn (_ r) ((fn (self i acc) (if (< i 1024) (self (+ i 2) (+ acc (if (= 0 (+ (ptr-ref (str->ptr r) i 1) (ptr-ref (str->ptr r) (+ i 1) 1))) 0 1))) acc)) 0 0)))
  (def mixer
    (fn (_ spec)
      (def m (Mixer make 8000 256))
      (unless (null? spec) (Mixer effect! m (lit fx) spec))
      (Mixer play! m (list (list (list (lit wave) (lit noise)) (list (lit hz) 2000) (list (lit env) (list 0 90) (list 30 0)))) 0 100)
      m))
  (def tail (fn (_ m) (do (Mixer block! m) (list (loud (Mixer block! m)) (loud (Mixer block! m))))))
  (list (tail (mixer ()))
        (List all? (fn (_ n) (< 100 n)) (tail (mixer (list (lit reverb) 100 85 50))))
        (= 0 (mem-cmp (str->ptr (Mixer block! (mixer ()))) (str->ptr (Mixer block! (mixer (list (lit phase) 1 3 500 60 80)))) 1024))))
```
---
    ((0 0) #t #f)

### a drive rounds a loud mix off at two thirds of full scale, and a limit holds it under its ceiling

```x
(do (import x/audio/mixer) (import x/core/doors ptr-ref str->ptr)
  (def peak (fn (_ r) ((fn (self i acc) (if (< i 1024) (self (+ i 2) ((fn (_ v) (if (< acc v) v acc)) ((fn (_ w) (if (< w 0) (- 0 w) w)) ((fn (_ u) (if (< 32767 u) (- u 65536) u)) (+ (ptr-ref (str->ptr r) i 1) (* 256 (ptr-ref (str->ptr r) (+ i 1) 1))))))) acc)) 0 0)))
  (def run
    (fn (_ specs)
      (def m (Mixer make 8000 256))
      (List for-each (fn (_ s) (Mixer effect! m (first s) s)) specs)
      (Mixer play! m (list (list (list (lit hz) 300) (list (lit env) (list 0 100) (list 200 100)))) 0 100)
      (Mixer block! m)
      (peak (Mixer block! m))))
  (list (run ()) (run (list (list (lit drive) 800 100))) (run (list (list (lit limit) 20 100)))
        (run (list (list (lit drive) 800 100) (list (lit limit) 50 100)))))
```
---
    (16384 21888 6552 16383)

### a crush, a chorus and a sweep each change what is heard

```x
(do (import x/audio/mixer) (import x/core/doors mem-cmp str->ptr)
  (def run
    (fn (_ spec)
      (def m (Mixer make 8000 256))
      (unless (null? spec) (Mixer effect! m (lit fx) spec))
      (Mixer play! m (list (list (list (lit hz) 300) (list (lit env) (list 0 60) (list 200 60)))) 0 100)
      (Mixer block! m)
      (Mixer block! m)))
  (def dry (run ()))
  (List map (fn (_ s) (= 0 (mem-cmp (str->ptr dry) (str->ptr (run s)) 1024)))
    (list (list (lit crush) 4 0) (list (lit crush) 16 1000) (list (lit chorus) 3 20 5 1000 60) (list (lit sweep) 200 1500 500 40))))
```
---
    (#f #f #f #f)

## the compiled loops

### built where there is a JIT, they render a scene byte for byte as the pure loops do

```x
(do (import x/audio/mixer) (import x/tool/compiled) (import x/core/doors mem-cmp str->ptr)
  (Mixer wave! (lit organ) (list 4 0 2 0 1))
  (def scene
    (fn (_)
      (def m (Mixer make 22050 512))
      (Mixer echo! m 40 50 35)
      (Mixer effect! m (lit room) (list (lit reverb) 80 70 30))
      (Mixer effect! m (lit sweep) (list (lit phase) 1 3 300 50 60))
      (Mixer play! m (list (list (list (lit wave) (lit organ)) (list (lit note) "C3") (list (lit cut) 40) (list (lit pan) -60)
                                 (list (lit env) (list 0 0) (list 8 90) (list 60 40) (list 90 0)))
                           (list (list (lit wave) (lit noise)) (list (lit hz) 2000) (list (lit slide) 200) (list (lit cut) 10)
                                 (list (lit at) 13) (list (lit env) (list 0 100) (list 70 0))))
                  37 80)
      (Mixer block! m) (Mixer block! m)
      (Mixer block! m)))
  (if (Mixer jit!)
    (do ((Compiled named (lit audio)) interpret!)
        (def pure (scene))
        ((Compiled named (lit audio)) compile!)
        (mem-cmp (str->ptr pure) (str->ptr (scene)) 2048))
    0))
```
---
    0

### built where there is a JIT, they render the newer effects, a filter, a resonant filter, a ring and a sync byte for byte as the pure loops do

```x
(do (import x/audio/mixer) (import x/tool/compiled) (import x/core/doors mem-cmp str->ptr)
  (def scene
    (fn (_)
      (def m (Mixer make 22050 512))
      (Mixer effect! m (lit a) (list (lit drive) 300 70))
      (Mixer effect! m (lit b) (list (lit chorus) 3 15 4 700 50))
      (Mixer effect! m (lit c) (list (lit sweep) 300 3000 400 60))
      (Mixer effect! m (lit d) (list (lit crush) 8 6000))
      (Mixer effect! m (lit e) (list (lit limit) 60 80))
      (Mixer play! m (list (list (list (lit note) "C3") (list (lit filter) (list 0 100) (list 40 10) (list 60 80))
                                 (list (lit env) (list 0 0) (list 8 90) (list 60 40) (list 90 0)))
                           (list (list (lit wave) (lit noise)) (list (lit hz) 2000) (list (lit at) 13) (list (lit env) (list 0 100) (list 70 0))
                                 (list (lit cutoff) (list 0 3000) (list 50 300)) (list (lit res) 80) (list (lit pass) (lit low) (lit high)))
                           (list (list (lit wave) (lit triangle)) (list (lit note) "A2") (list (lit ring) 700) (list (lit sync) -500)
                                 (list (lit bend) (list 0 0) (list 60 1200)) (list (lit env) (list 0 80) (list 80 0))))
                  37 80)
      (Mixer block! m)
      (Mixer cut! m 50)
      (Mixer block! m)
      (Mixer block! m)))
  (if (Mixer jit!)
    (do ((Compiled named (lit audio)) interpret!)
        (def pure (scene))
        ((Compiled named (lit audio)) compile!)
        (mem-cmp (str->ptr pure) (str->ptr (scene)) 2048))
    0))
```
---
    0
