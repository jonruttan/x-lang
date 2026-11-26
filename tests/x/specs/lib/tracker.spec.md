# Tracker: a song of patterns played into a mixer row by row
# @weight 3

A song is the forms a .xon file reads as. The cases play songs into a
mixer at 8000 frames a second, 256 a block, and read where they have
reached and what is sounding.

## songs

### a song's tempo is its rows a beat at its beats a minute, faster with tension

```x
(do (import x/audio/tracker)
  (def t (Tracker make (lit (song "s" (bpm 60) (rows 4) (tension-bpm 60) (instrument a) (pattern p (a "A3")) (order p)))))
  (def calm (Tracker row-ms t))
  (Tracker tension! t 50)
  (def half (Tracker row-ms t))
  (Tracker tension! t 400)
  (list calm half (Tracker tension t) (Tracker row-ms t)))
```
---
    (250 166 100 125)

### a pace plays the song slower or faster, over the tension's tempo

```x
(do (import x/audio/tracker)
  (def t (Tracker make (lit (song "s" (bpm 60) (rows 4) (tension-bpm 60) (instrument a) (pattern p (a "A3")) (order p)))))
  (Tracker pace! t 50)
  (def slow (Tracker row-ms t))
  (Tracker tension! t 100)
  (def tense (Tracker row-ms t))
  (Tracker pace! t 1000)
  (list slow tense (Tracker pace t) (Tracker row-ms t)))
```
---
    (500 250 400 31)

### a song's tick rate counts its rows at the pace, tension leaves it, and a song of beats a minute has one

```x
(do (import x/audio/tracker)
  (def t (Tracker make (lit (song "s" (tick-rate 50) (ticks 6) (tension-bpm 60) (instrument a) (pattern p (a "A3")) (order p)))))
  (def own (Tracker row-ms t))
  (Tracker tension! t 100)
  (def tense (Tracker row-ms t))
  (Tracker pace! t 50)
  (def slow (Tracker row-ms t))
  (def b (Tracker make (lit (song "b" (bpm 125) (rows 4) (ticks 6) (instrument a) (pattern p (a "A3")) (order p)))))
  (def f (Tracker make (lit (song "f" (tick-rate 100 3) (ticks 1) (instrument a) (pattern p (a "A3")) (order p)))))
  (list own tense slow (Tracker row-ms b) (Tracker row-ms f)))
```
---
    (120 120 240 120 30)

### a song that gives bpm and tick-rate, or a time that is none, raises

```x
(do (import x/audio/tracker)
  (def make (fn (_ props cells) (guard (e (Err text e)) (Tracker name (Tracker make (List append (list (lit song) "s") props (list (lit (instrument a)) (list (lit pattern) (lit p) (list (lit a) cells)) (lit (order p)))))))))
  (list (make (lit ((bpm 60) (tick-rate 50))) "A3")
        (make (lit ((tick-rate 0))) "A3")
        (make (lit ((tick-rate 50 0))) "A3")
        (make (lit ((ticks 0))) "A3")
        (make () "A3/m0")
        (make () "A3/m")
        (make () "A3/k0")
        (make () "A3/h-1")
        (make () "A3/kticks")
        (make () "A3/m50,2/k3/h")))
```
---
    ("Tracker: a song gives bpm or tick-rate, not both" "Tracker: tick-rate is NUM or NUM,DEN, each above 0" "Tracker: tick-rate is NUM or NUM,DEN, each above 0" "Tracker: a song's ticks are 1 or more" "Tracker: m is NUM or NUM,DEN, each above 0" "Tracker: m is NUM or NUM,DEN, each above 0" "Tracker: k is N, 1 or more" "Tracker: h is N, 0 or more" "Tracker: k is N, 1 or more" "s")

### a song's names follow its time: a tick rate's beats a minute, and the ticks a k sets

```x
(do (import x/audio/tracker) (import x/audio/mixer)
  (def m (Mixer make 1000 20))
  (def t (Tracker make (lit (song "s" (tick-rate 50) (ticks 6) (rows 4) (instrument a) (pattern p (a "- -/k3 -")) (order p)))))
  (def pick (fn (_) (List map (fn (_ k) (rest (Assoc entry k (Tracker names t)))) (lit (bpm ticks row tick)))))
  (def before (pick))
  (Tracker play! t m)
  (Mixer block! m)
  (def at-row-0 (pick))
  (List for-each (fn (_ k) (Mixer block! m)) (lit (1 2 3 4 5 6)))
  (list before at-row-0 (pick)))
```
---
    ((125 6 120 20) (125 6 120 20) (250 3 60 20))

### a song that names what it does not have raises

```x
(do (import x/audio/tracker)
  (list (guard (e (Err text e)) (Tracker make (lit (song "s" (instrument a) (pattern p (b "A3")) (order p)))))
        (guard (e (Err text e)) (Tracker make (lit (song "s" (instrument a) (pattern p (a "A3")) (order q)))))
        (guard (e (Err text e)) (Tracker make (lit (song "s" (instrument a) (pattern p (a "A3"))))))))
```
---
    ("Tracker: no instrument named b" "Tracker: no pattern named q" "Tracker: the song has no order")

## playing

### rows are played a row's length apart, and the order wraps

```x
(do (import x/audio/tracker) (import x/audio/mixer)
  (def m (Mixer make 8000 256))
  (def t (Tracker make (lit (song "s" (bpm 60) (rows 4)
                              (instrument a (env (0 100) (100 50)) (release 50))
                              (pattern p (a "A3 . - ."))
                              (pattern q (a "C4 E4"))
                              (order p q)))))
  (Tracker play! t m)
  (def after (fn (self n) (if (< 0 n) (do (Mixer block! m) (self (- n 1))) (Tracker place t))))
  (list (after 1) (after 8) (after 16) (after 16)))
```
---
    ((0 . 1) (0 . 2) (1 . 0) (0 . 0))

### rows start at the frame their exact time falls in, so a minute of rows a third of a second long ends on the minute

```x
(do (import x/audio/tracker) (import x/audio/mixer)
  (def m (Mixer make 1000 250))
  (def t (Tracker make (lit (song "s" (tick-rate 3) (ticks 1) (instrument a) (pattern p (a "- - -")) (pattern q (a "- - -")) (order p q)))))
  (Tracker play! t m)
  (def after (fn (self n) (if (< 0 n) (do (Mixer block! m) (self (- n 1))) (Tracker place t))))
  (list (after 240) (after 1)))
```
---
    ((0 . 0) (0 . 1))

### a k sets the ticks a row and an m the tick rate, from their row on, whichever channel they are in

```x
(do (import x/audio/tracker) (import x/audio/mixer)
  (def m (Mixer make 1000 20))
  (def t (Tracker make (lit (song "s" (tick-rate 50) (ticks 6) (instrument a) (instrument b)
                              (pattern p (a "- - . - -") (b "- -/k3 - -/m25 -"))
                              (order p)))))
  (Tracker play! t m)
  (def after (fn (self n) (if (< 0 n) (do (Mixer block! m) (self (- n 1))) (pair (Tracker place t) (Tracker row-ms t)))))
  (list (after 6) (after 1) (after 3) (after 3) (after 6)))
```
---
    (((0 . 1) . 120) ((0 . 2) . 60) ((0 . 3) . 60) ((0 . 4) . 120) ((0 . 0) . 120))

### an h holds its row more rows, the note in it held and not struck again

```x
(do (import x/audio/tracker) (import x/audio/mixer)
  (def m (Mixer make 1000 40))
  (def t (Tracker make (lit (song "s" (tick-rate 50) (ticks 6)
                              (instrument a (env (0 100)) (release 10))
                              (pattern p (a "A3/h2 . - - - - -"))
                              (order p)))))
  (Tracker play! t m)
  (def count (fn (self n acc) (if (< 0 n) (do (Mixer block! m) (self (- n 1) (pair (Mixer playing m) acc))) (List reverse acc))))
  (def sounding (count 14 ()))
  (list sounding (Tracker place t)))
```
---
    ((1 1 1 1 1 1 1 1 1 1 1 1 0 0) (0 . 3))

### a note sounds until the next cell that is not ".", then its release

```x
(do (import x/audio/tracker) (import x/audio/mixer)
  (def m (Mixer make 8000 250))
  (def t (Tracker make (lit (song "s" (bpm 60) (rows 4)
                              (instrument a (env (0 100)) (release 125))
                              (pattern p (a "A3 . - . . . . ."))
                              (order p)))))
  (Tracker play! t m)
  (def count (fn (self n acc) (if (< 0 n) (do (Mixer block! m) (self (- n 1) (pair (Mixer playing m) acc))) (List reverse acc))))
  (count 22 ()))
```
---
    (1 1 1 1 1 1 1 1 1 1 1 1 1 1 1 1 1 1 1 0 0 0)

### a calm layer goes as the tension comes, and a tension layer comes with it

```x
(do (import x/audio/tracker) (import x/audio/mixer)
  (def song (lit (song "s" (bpm 60) (rows 4)
                   (instrument calm (layer calm) (env (0 100)) (release 10))
                   (instrument tense (layer tension) (env (0 100)) (release 10))
                   (pattern p (calm "A3 A3") (tense "E4 E4"))
                   (order p))))
  (def voices (fn (_ tension)
    (do (def m (Mixer make 8000 256))
        (def t (Tracker tension! (Tracker make song) tension))
        (Tracker play! t m)
        (Mixer block! m)
        (Mixer playing m))))
  (list (voices 0) (voices 50) (voices 100)))
```
---
    (1 2 1)

### an instrument's voices each play, its shared props under each

```x
(do (import x/audio/tracker) (import x/audio/mixer)
  (def m (Mixer make 8000 256))
  (def t (Tracker make (lit (song "s" (instrument pad (env (0 100)) (voice (detune -7)) (voice (detune 7)) (voice (wave noise) (gain 10)))
                              (pattern p (pad "C3:50"))
                              (order p)))))
  (Tracker play! t m)
  (Mixer block! m)
  (Mixer playing m))
```
---
    3

### a song changed waits for the pattern playing to end

```x
(do (import x/audio/tracker) (import x/audio/mixer)
  (def m (Mixer make 8000 250))
  (def t (Tracker make (lit (song "one" (bpm 60) (rows 4) (instrument a) (pattern p (a "A3 . . .")) (order p p)))))
  (Tracker play! t m)
  (Mixer block! m)
  (Tracker song! t (lit (song "two" (bpm 60) (rows 4) (instrument b) (pattern q (b "C3 .")) (order q))))
  (def a (Tracker name t))
  (def go (fn (self n) (when (< 0 n) (do (Mixer block! m) (self (- n 1))))))
  (go 31)
  (list a (Tracker name t) (Tracker place t)))
```
---
    ("one" "two" (0 . 0))

### a song's effects go over the mixer, and the next song's take their places

```x
(do (import x/audio/tracker) (import x/audio/mixer)
  (def m (Mixer make 8000 256))
  (def t (Tracker make (lit (song "one" (bpm 600) (rows 4) (echo 30 40 20) (phase 1 3 500 40 50) (drive 200 50)
                                  (instrument a) (pattern p (a "A3")) (order p)))))
  (Tracker play! t m)
  (Tracker play! t m)
  (def one (List map rest (Mixer effects m)))
  (Tracker song! t (lit (song "two" (bpm 600) (rows 4) (reverb 100 70 30) (limit 90 100) (instrument b) (pattern q (b "C3")) (order q))))
  (Mixer block! m) (Mixer block! m)
  (list one (Tracker name t) (List map rest (Mixer effects m))))
```
---
    ((('echo 30 40 20) ('phase 1 3 500 40 50) ('drive 200 50)) "two" (('reverb 100 70 30) ('limit 90 100)))

## names

### a song's own names follow its tempo, tension and pace, and its lets are worked out from them in order

```x
(do (import x/audio/tracker)
  (def t (Tracker make (lit (song "s" (bpm 60) (rows 4) (ticks 5) (tension-bpm 60)
                                  (let gap (* 2 row)) (let half (/ gap 2)) (let most (max 10 (- beat 900) 3)) (let low (min 7 -2))
                                  (instrument a) (pattern p (a "A3")) (order p)))))
  (def calm (List map rest (Tracker names t)))
  (Tracker tension! t 100)
  (def tense (List map rest (Tracker names t)))
  (Tracker pace! t 50)
  (list (List map first (Tracker names t)) calm tense (List map rest (Tracker names t))))
```
---
    (('bpm 'rows 'ticks 'row 'beat 'tick 'gap 'half 'most 'low) (60 4 5 250 1000 50 500 250 100 -2) (120 4 5 125 500 25 250 125 10 -2) (60 4 5 250 1000 50 500 250 100 -2))

### a let of the names before it is kept; one that is not (let NAME EXPR), names a name twice or one of the song's own, or uses a name not yet defined, raises

```x
(do (import x/audio/tracker)
  (def %let-raised (fn (_ lets) (guard (e #t) (do (Tracker make (List append (list (lit song) "s") lets (lit ((instrument a) (pattern p (a "A3")) (order p))))) #f))))
  (list (%let-raised (lit ((let a 1) (let b (+ a row)))))
        (%let-raised (lit ((let a))))
        (%let-raised (lit ((let a 1) (let a 2))))
        (%let-raised (lit ((let row 3))))
        (%let-raised (lit ((let b (+ a 1)) (let a 1))))
        (%let-raised (lit ((let a sine))))
        (%let-raised (lit ((echo (* 2 gap) 40 20))))
        (%let-raised (lit ((instrument b (gain (+ 10 nowhere))))))))
```
---
    (#f #t #t #t #t #t #t #t)

### an instrument's props take names and sums, worked out as each note starts with the tempo then; its words are never names

```x
(do (import x/audio/tracker) (import x/audio/mixer) (import x/core/doors ptr-ref str->ptr)
  (def song (fn (_ at) (list (lit song) "s" (lit (bpm 60)) (lit (rows 4)) (lit (ticks 4)) (lit (tension-bpm 60)) (lit (let sine 2))
                             (list (lit instrument) (lit a) (lit (wave sine)) (lit (env (0 100) ((* 4 sine) 100))) (lit (release 10)) (list (lit at) at))
                             (lit (pattern p (a "C4 . . ."))) (lit (order p)))))
  (def loud (fn (_ r) ((fn (self i acc) (if (< i 512) (self (+ i 2) (+ acc (if (= 0 (+ (ptr-ref (str->ptr r) i 1) (ptr-ref (str->ptr r) (+ i 1) 1))) 0 1))) acc)) 0 0)))
  (def heard
    (fn (_ at tension)
      (def m (Mixer make 8000 256))
      (def t (Tracker make (song at)))
      (Tracker tension! t tension)
      (Tracker play! t m)
      ((fn (self k acc) (if (< k 5) (self (+ k 1) (pair (< 0 (loud (Mixer block! m))) acc)) (List reverse acc))) 0 ())))
  (list (heard 125 0) (heard (lit (* 2 tick)) 0) (heard (lit (* 2 tick)) 100)))
```
---
    ((#f #f #f #f #t) (#f #f #f #f #t) (#f #f #t #t #t))

### a cell's effect takes a name for a number, worked out as the note starts

```x
(do (import x/audio/tracker) (import x/audio/mixer)
  (def started
    (fn (_ cells)
      (def m (Mixer make 8000 256))
      (Tracker play! (Tracker make (list (lit song) "s" (lit (bpm 60)) (lit (rows 4)) (lit (let gap (* 4 tick))) (lit (let three 3))
                                         (lit (instrument a (wave sine) (env (0 100) (10 100)) (release 10)))
                                         (list (lit pattern) (lit p) (list (lit a) cells)) (lit (order p))))
                     m)
      (Mixer block! m)
      (Mixer playing m)))
  (list (started "C4/egap,50,3") (started "C4/e100,50,three") (started "C4/egap,50,0")))
```
---
    (4 4 1)

### a song effect that uses a name is put again when the tempo changes it, and left as it is when the tempo does not

```x
(do (import x/audio/tracker) (import x/audio/mixer)
  (def m (Mixer make 8000 256))
  (def t (Tracker make (lit (song "s" (bpm 60) (rows 4) (tension-bpm 60) (echo (* 2 row) 40 20) (reverb 100 70 30)
                                  (instrument a) (pattern p (a "A3 . . .")) (order p)))))
  (Tracker play! t m)
  (def blocks (fn (self n) (when (< 0 n) (do (Mixer block! m) (self (- n 1))))))
  (blocks 10)
  (def calm (List map rest (Mixer effects m)))
  (Tracker tension! t 100)
  (blocks 10)
  (list calm (List map rest (Mixer effects m))))
```
---
    ((('echo 500 40 20) ('reverb 100 70 30)) (('echo 250 40 20) ('reverb 100 70 30)))

## a cell's effects

### a cell's effect that is no letter, or a number that is none, raises

```x
(do (import x/audio/tracker)
  (def make (fn (_ cells) (guard (e (Err text e)) (Tracker name (Tracker make (list (lit song) "s" (lit (instrument a)) (list (lit pattern) (lit p) (list (lit a) cells)) (lit (order p))))))))
  (list (make "A3/z1") (make "A3/v3a") (make "A3/v30,4 ./s-200 -")))
```
---
    ("Tracker: no effect z1" "Tracker: not a number: 3a" "s")

### an arpeggio of nothing sounds as the plain note, and each pitch and level effect changes it

```x
(do (import x/audio/tracker) (import x/audio/mixer) (import x/core/doors ptr-ref str->ptr)
  (def song (fn (_ cells) (list (lit song) "s" (lit (bpm 60)) (lit (rows 4)) (lit (ticks 4))
                                (lit (instrument a (wave sine) (env (0 100) (10 100)) (release 20)))
                                (list (lit pattern) (lit p) (list (lit a) cells)) (lit (order p)))))
  (def s16 (fn (_ r i) ((fn (_ u) (if (< u 32768) u (- u 65536))) (+ (ptr-ref (str->ptr r) (* 2 i) 1) (* 256 (ptr-ref (str->ptr r) (+ 1 (* 2 i)) 1))))))
  (def worst
    (fn (_ a b)
      (def ma (Mixer make 8000 256))
      (def mb (Mixer make 8000 256))
      (Tracker play! (Tracker make (song a)) ma)
      (Tracker play! (Tracker make (song b)) mb)
      ((fn (self n w)
         (if (< n 1) w
           ((fn (_ ra rb)
              (self (- n 1) ((fn (self i w) (if (< i 512) (self (+ i 1) ((fn (_ d) (if (< w d) d w)) ((fn (_ d) (if (< d 0) (- 0 d) d)) (- (s16 ra i) (s16 rb i))))) w)) 0 w)))
            (Mixer block! ma) (Mixer block! mb))))
       12 0)))
  (def plain "C4 . . .")
  (list (< (worst plain "C4/a0,0 . . .") 8)
        (List all? (fn (_ c) (< 1000 (worst plain c)))
          (list "C4/a12 . . ." "C4/v50,4 . . ." "C4 ./s-1200 . ." "G3 C4/p4 . ." "C4/t90,2 . . ." "C4/f0 . . ." "C4/l3 . . ."))))
```
---
    (#t #t)

### a width effect moves a pulse's width from its own: to its own width it sounds as it was

```x
(do (import x/audio/tracker) (import x/audio/mixer) (import x/core/doors ptr-ref str->ptr)
  (def song (fn (_ inst cells) (list (lit song) "s" (lit (bpm 60)) (lit (rows 4)) (lit (ticks 4))
                                     (pair (lit instrument) (pair (lit a) inst))
                                     (list (lit pattern) (lit p) (list (lit a) cells)) (lit (order p)))))
  (def s16 (fn (_ r i) ((fn (_ u) (if (< u 32768) u (- u 65536))) (+ (ptr-ref (str->ptr r) (* 2 i) 1) (* 256 (ptr-ref (str->ptr r) (+ 1 (* 2 i)) 1))))))
  (def worst
    (fn (_ inst a b)
      (def ma (Mixer make 8000 256))
      (def mb (Mixer make 8000 256))
      (Tracker play! (Tracker make (song inst a)) ma)
      (Tracker play! (Tracker make (song inst b)) mb)
      ((fn (self n w)
         (if (< n 1) w
           ((fn (_ ra rb)
              (self (- n 1) ((fn (self i w) (if (< i 512) (self (+ i 1) ((fn (_ d) (if (< w d) d w)) ((fn (_ d) (if (< d 0) (- 0 d) d)) (- (s16 ra i) (s16 rb i))))) w)) 0 w)))
            (Mixer block! ma) (Mixer block! mb))))
       12 0)))
  (def p50 (lit ((wave pulse) (env (0 100) (10 100)) (release 20))))
  (def p20 (lit ((wave pulse) (width (0 20)) (env (0 100) (10 100)) (release 20))))
  (def smooth (lit ((wave sine) (env (0 100) (10 100)) (release 20))))
  (list (< (worst p50 "C4 . . ." "C4/w50 . . .") 8)
        (< (worst p20 "C4 . . ." "C4/w20 . . .") 8)
        (< 1000 (worst p50 "C4 . . ." "C4/w10 . . ."))
        (< 1000 (worst p50 "C4 . . ." "C4 ./w90 . ."))
        (< 1000 (worst p20 "C4 . . ." "C4/w50 . . ."))
        (< (worst smooth "C4 . . ." "C4/w10 . . .") 8)))
```
---
    (#t #t #t #t #t #t)

### a cutoff effect moves a resonant filter's cutoff from its own: to its own it sounds as it was, and a voice with none is untouched

```x
(do (import x/audio/tracker) (import x/audio/mixer) (import x/core/doors ptr-ref str->ptr)
  (def song (fn (_ inst cells) (list (lit song) "s" (lit (bpm 60)) (lit (rows 4)) (lit (ticks 4))
                                     (pair (lit instrument) (pair (lit a) inst))
                                     (list (lit pattern) (lit p) (list (lit a) cells)) (lit (order p)))))
  (def s16 (fn (_ r i) ((fn (_ u) (if (< u 32768) u (- u 65536))) (+ (ptr-ref (str->ptr r) (* 2 i) 1) (* 256 (ptr-ref (str->ptr r) (+ 1 (* 2 i)) 1))))))
  (def worst
    (fn (_ inst a b)
      (def ma (Mixer make 8000 256))
      (def mb (Mixer make 8000 256))
      (Tracker play! (Tracker make (song inst a)) ma)
      (Tracker play! (Tracker make (song inst b)) mb)
      ((fn (self n w)
         (if (< n 1) w
           ((fn (_ ra rb)
              (self (- n 1) ((fn (self i w) (if (< i 512) (self (+ i 1) ((fn (_ d) (if (< w d) d w)) ((fn (_ d) (if (< d 0) (- 0 d) d)) (- (s16 ra i) (s16 rb i))))) w)) 0 w)))
            (Mixer block! ma) (Mixer block! mb))))
       12 0)))
  (def low (lit ((wave saw) (cutoff (0 300)) (res 50) (env (0 100) (10 100)) (release 20))))
  (def smooth (lit ((wave saw) (env (0 100) (10 100)) (release 20))))
  (list (< (worst low "C4 . . ." "C4/o300 . . .") 8)
        (< 300 (worst low "C4 . . ." "C4/o1100 . . ."))
        (< 300 (worst low "C4 . . ." "C4 ./o1100 . ."))
        (< (worst smooth "C4 . . ." "C4/o1100 . . .") 8)))
```
---
    (#t #t #t #t)

### a ring and a sync effect couple the note to a modulator, as the instrument's own ring and sync would

```x
(do (import x/audio/tracker) (import x/audio/mixer) (import x/core/doors ptr-ref str->ptr)
  (def song (fn (_ inst cells) (list (lit song) "s" (lit (bpm 60)) (lit (rows 4)) (lit (ticks 4))
                                     (pair (lit instrument) (pair (lit a) inst))
                                     (list (lit pattern) (lit p) (list (lit a) cells)) (lit (order p)))))
  (def s16 (fn (_ r i) ((fn (_ u) (if (< u 32768) u (- u 65536))) (+ (ptr-ref (str->ptr r) (* 2 i) 1) (* 256 (ptr-ref (str->ptr r) (+ 1 (* 2 i)) 1))))))
  (def worst
    (fn (_ ia a ib b)
      (def ma (Mixer make 8000 256))
      (def mb (Mixer make 8000 256))
      (Tracker play! (Tracker make (song ia a)) ma)
      (Tracker play! (Tracker make (song ib b)) mb)
      ((fn (self n w)
         (if (< n 1) w
           ((fn (_ ra rb)
              (self (- n 1) ((fn (self i w) (if (< i 512) (self (+ i 1) ((fn (_ d) (if (< w d) d w)) ((fn (_ d) (if (< d 0) (- 0 d) d)) (- (s16 ra i) (s16 rb i))))) w)) 0 w)))
            (Mixer block! ma) (Mixer block! mb))))
       12 0)))
  (def tri (lit ((wave triangle) (env (0 100) (10 100)) (release 20))))
  (def rung (lit ((wave triangle) (ring 1200) (env (0 100) (10 100)) (release 20))))
  (def synced (lit ((wave triangle) (sync 700) (env (0 100) (10 100)) (release 20))))
  (list (< 1000 (worst tri "C4 . . ." tri "C4/x1200 . . ."))
        (< (worst rung "C4 . . ." tri "C4/x1200 . . .") 8)
        (< 1000 (worst tri "C4 . . ." tri "C4/y700 . . ."))
        (< (worst synced "C4 . . ." tri "C4/y700 . . .") 8)
        (< 1000 (worst synced "C4 . . ." synced "C4/y-500 . . ."))))
```
---
    (#t #t #t #t #t)

### a delay starts the note late, a cut lets it go early, and a retrigger starts it again

```x
(do (import x/audio/tracker) (import x/audio/mixer) (import x/core/doors ptr-ref str->ptr)
  (def song (fn (_ cells) (list (lit song) "s" (lit (bpm 60)) (lit (rows 4)) (lit (ticks 4))
                                (lit (instrument a (wave sine) (env (0 100) (10 100)) (release 10)))
                                (list (lit pattern) (lit p) (list (lit a) cells)) (lit (order p)))))
  (def loud (fn (_ r) ((fn (self i acc) (if (< i 1024) (self (+ i 2) (+ acc (if (= 0 (+ (ptr-ref (str->ptr r) i 1) (ptr-ref (str->ptr r) (+ i 1) 1))) 0 1))) acc)) 0 0)))
  (def heard
    (fn (_ cells n)
      (def m (Mixer make 8000 256))
      (Tracker play! (Tracker make (song cells)) m)
      ((fn (self k acc) (if (< k n) (self (+ k 1) (pair (< 0 (loud (Mixer block! m))) acc)) (List reverse acc))) 0 ())))
  (def started
    (fn (_ cells)
      (def m (Mixer make 8000 256))
      (Tracker play! (Tracker make (song cells)) m)
      (Mixer block! m)
      (Mixer playing m)))
  (list (heard "C4/d2 . . ." 4) (heard "C4/c1 . . ." 8) (started "C4") (started "C4/r1")))
```
---
    ((#f #f #f #t) (#t #t #t #f #f #f #f #f) 1 5)

### an echo plays the note again later, quieter, as many times as it says

```x
(do (import x/audio/tracker) (import x/audio/mixer)
  (def song (fn (_ cells) (list (lit song) "s" (lit (bpm 60)) (lit (rows 4)) (lit (ticks 4))
                                (lit (instrument a (wave sine) (env (0 100) (10 100)) (release 10)))
                                (list (lit pattern) (lit p) (list (lit a) cells)) (lit (order p)))))
  (def started
    (fn (_ cells)
      (def m (Mixer make 8000 256))
      (Tracker play! (Tracker make (song cells)) m)
      (Mixer block! m)
      (Mixer playing m)))
  (def %echo-raised (fn (_ cells) (guard (e #t) (do (Tracker make (song cells)) #f))))
  (list (started "C4") (started "C4/e340,100") (started "C4/e100") (started "C4/e100,50,3") (started "C4/e100,0,3")
        (started "C4/e100,50,0") (%echo-raised "C4/e100,x")))
```
---
    (1 2 2 4 1 1 #t)
