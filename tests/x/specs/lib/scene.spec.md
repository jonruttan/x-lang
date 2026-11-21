# Scene: figures and animations drawn as a frame
# @weight 2

A frame is a black canvas with each figure drawn on it, then each
animation's figure at one progress.

## smooth

### slow at both ends, a half at a half

```x
(import x/gfx/scene)
(do
  (list (Scene smooth 0) (Scene smooth 0.25) (Scene smooth 0.5) (Scene smooth 1)))
```
---
    (0.0 0.15625 0.5 1.0)

## frame

### figures are drawn in order on black, animations after them

Four pixels a unit: a square from 8 to 24, a square from 12 to 20 over it,
and a third that size fading out over both.

```x
(import x/gfx/canvas)
(import x/gfx/figure)
(import x/gfx/scene)
(do
  (def sc-big (Figure fill (Figure square 4) (list 9 8 7)))
  (def sc-small (Figure fill (Figure square 2) (list 1 2 3)))
  (def sc-gone (Figure fade-out (Figure fill (Figure square 2) (list 200 100 50))))
  (def sc-at (fn (_ t x y) (Canvas pixel (Scene frame (list sc-big sc-small) (list sc-gone) t 32 32) x y)))
  (list (sc-at 1 0 0) (sc-at 1 10 10) (sc-at 1 16 16) (sc-at 0 16 16)))
```
---
    ((0 0 0 255) (9 8 7 255) (1 2 3 255) (200 100 50 255))

## after

### the figures, then each animation's figure at its end

```x
(import x/gfx/figure)
(import x/gfx/scene)
(do
  (def sc-end (Scene after (list (Figure square 2)) (list (Figure morph (Figure square 2) (Figure square 4)))))
  (list (List length sc-end) (Figure bounds (first sc-end)) (Figure bounds (List ref 1 sc-end))))
```
---
    (2 (-1.0 -1.0 1.0 1.0) (-2.0 -2.0 2.0 2.0))

## a stage

The cases play on a front end of their own, which counts the frames shown,
keeps the last and answers the events it is given.

### open asks the front for a window the frame's size

```x
(import x/gfx/figure)
(import x/gfx/scene)
(def sc-shown (pair 0 ()))
(def sc-last (pair () ()))
(def sc-events (pair () ()))
(def sc-closed (pair #f ()))
(def-class ScFront ()
  (static
    (method open (self title w h scale) (list title w h scale))
    (method show! (self win buf)
      (do (%set-first! sc-shown (+ (first sc-shown) 1)) (%set-first! sc-last buf) win))
    (method poll (self)
      ((fn (_ e) (do (%set-first! sc-events ()) e)) (first sc-events)))
    (method close (self win) (%set-first! sc-closed win))))
(do
  (def sc-stage (Scene open ScFront "t" 16 16 50))
  (list (List ref 1 sc-stage) (List ref 2 sc-stage) (List ref 3 sc-stage) (List ref 4 sc-stage) (Scene stopped? sc-stage)))
```
---
    (("t" 16 16 1) 16 16 50 #f)

### play for no time shows one frame, the animations' end, and answers the figures afterwards

```x
(import x/gfx/canvas)
(import x/gfx/figure)
(import x/gfx/scene)
(import x/core/doors mem-cmp str->ptr)
(do
  (def sc-grow (list (Figure morph (Figure fill (Figure square 2) (list 9 8 7)) (Figure fill (Figure square 4) (list 1 2 3)))))
  (%set-first! sc-shown 0)
  (def sc-end (Scene play sc-stage () sc-grow 0))
  (list (first sc-shown)
        (mem-cmp (str->ptr (first sc-last)) (str->ptr (List ref 2 (Scene frame () sc-grow 1 16 16))) (* 4 16 16))
        (Figure bounds (first sc-end))))
```
---
    (1 0 (-2.0 -2.0 2.0 2.0))

### play over a time shows more than one frame and ends on the animations' end

```x
(import x/gfx/canvas)
(import x/gfx/figure)
(import x/gfx/scene)
(import x/core/doors mem-cmp str->ptr)
(do
  (%set-first! sc-shown 0)
  (Scene play sc-stage () sc-grow 0.2)
  (list (< 1 (first sc-shown))
        (mem-cmp (str->ptr (first sc-last)) (str->ptr (List ref 2 (Scene frame () sc-grow 1 16 16))) (* 4 16 16))))
```
---
    (#t 0)

### figures that do not change are behind every frame, drawn once a play

```x
(import x/gfx/canvas)
(import x/gfx/figure)
(import x/gfx/scene)
(import x/core/doors mem-cmp str->ptr)
(do
  (def sc-still (list (Figure fill (Figure square 6) (list 40 50 60))))
  (def sc-both (Scene play sc-stage sc-still sc-grow 0.1))
  (list (mem-cmp (str->ptr (first sc-last)) (str->ptr (List ref 2 (Scene frame sc-still sc-grow 1 16 16))) (* 4 16 16))
        (List length sc-both)))
```
---
    (0 2)

### wait shows the figures once and answers them

```x
(import x/gfx/figure)
(import x/gfx/scene)
(do
  (%set-first! sc-shown 0)
  (def sc-held (Scene wait sc-stage (list (Figure square 2)) 0.05))
  (list (first sc-shown) (Figure bounds (first sc-held))))
```
---
    (1 (-1.0 -1.0 1.0 1.0))

### a window closed on the way stops the stage: the play ends, and later ones show nothing

```x
(import x/gfx/figure)
(import x/gfx/scene)
(do
  (%set-first! sc-shown 0)
  (%set-first! sc-events (list 'quit))
  (def sc-cut (Scene play sc-stage () sc-grow 30))
  (def sc-once (first sc-shown))
  (Scene play sc-stage () sc-grow 30)
  (Scene wait sc-stage () 30)
  (list sc-once (first sc-shown) (Scene stopped? sc-stage) (Figure bounds (first sc-cut))))
```
---
    (1 1 #t (-2.0 -2.0 2.0 2.0))

### close hands the front its window

```x
(import x/gfx/scene)
(do
  (Scene close sc-stage)
  (first sc-closed))
```
---
    ("t" 16 16 1)
