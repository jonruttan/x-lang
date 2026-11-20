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
