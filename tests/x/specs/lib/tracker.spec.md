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
