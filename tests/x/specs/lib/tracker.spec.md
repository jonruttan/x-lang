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

## a cell's effects

### a cell's effect that is no letter, or a number that is none, raises

```x
(do (import x/audio/tracker)
  (def make (fn (_ cells) (guard (e (Err text e)) (Tracker name (Tracker make (list (lit song) "s" (lit (instrument a)) (list (lit pattern) (lit p) (list (lit a) cells)) (lit (order p))))))))
  (list (make "A3/x1") (make "A3/v3a") (make "A3/v30,4 ./s-200 -")))
```
---
    ("Tracker: no effect x1" "Tracker: not a number: 3a" "s")

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
