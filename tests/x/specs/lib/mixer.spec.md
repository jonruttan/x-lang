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

## the compiled loops

### built where there is a JIT, they render a scene byte for byte as the pure loops do

```x
(do (import x/audio/mixer) (import x/tool/compiled) (import x/core/doors mem-cmp str->ptr)
  (Mixer wave! (lit organ) (list 4 0 2 0 1))
  (def scene
    (fn (_)
      (def m (Mixer make 22050 512))
      (Mixer echo! m 40 50 35)
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
