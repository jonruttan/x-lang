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
