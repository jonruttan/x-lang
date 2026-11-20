# Figure: outlines placed in a scene and changed over time
# @weight 2

A figure is (POINTS FILL STROKE WIDTH DRAWN), POINTS a Matrix of its
curves' points in scene units: the frame 8 units high, 0 0 its centre, y
up. An animation is a function of progress answering a figure.

## makers

### a circle, a square and a triangle: their bounds and their rows

Four curves are 13 rows and three are 10.

```x
(import x/gfx/figure)
(do
  (list (Figure bounds (Figure circle 1)) ((first (Figure circle 1)) extent)
        (Figure bounds (Figure square 2)) ((first (Figure square 2)) extent)
        (List ref 3 (Figure bounds (Figure triangle 2))) ((first (Figure triangle 2)) extent)))
```
---
    ((-1.0 -1.0 1.0 1.0) (13 2) (-1.0 -1.0 1.0 1.0) (13 2) 2.0 (10 2))

### a polygon runs through its corners; none raises

```x
(import x/gfx/figure)
(do
  (list (Figure bounds (Figure polygon (list (list 0 0) (list 4 0) (list 0 3))))
        (guard (e (Err text e)) (Figure polygon ()))))
```
---
    ((0.0 0.0 4.0 3.0) "Figure: polygon: no corners")

## placement

### shift moves and scale grows about the middle

```x
(import x/gfx/figure)
(do
  (list (Figure bounds (Figure shift (Figure square 2) 3 -1))
        (Figure bounds (Figure scale (Figure shift (Figure square 2) 3 0) 2))))
```
---
    ((2.0 -2.0 4.0 0.0) (1.0 -2.0 5.0 2.0))

### rotate turns about the middle of the bounds

A 4 by 2 triangle a quarter turn round is 2 by 4 about the same middle.

```x
(import x/gfx/figure)
(import x/num/float)
(do
  (def fig-turned (Figure rotate (Figure polygon (list (list 0 0) (list 4 0) (list 0 2))) (Float / (Float pi) 2)))
  (List map (fn (_ v) (Float round v)) (Figure bounds fig-turned)))
```
---
    (1.0 -1.0 3.0 3.0)

### next-to leaves the gap on each side, the middles in line

```x
(import x/gfx/figure)
(do
  (def fig-ring (Figure circle 1))
  (List map (fn (_ side) (Figure bounds (Figure next-to (Figure square 2) fig-ring side 0.5)))
    (list 'right 'left 'up 'down)))
```
---
    ((1.5 -1.0 3.5 1.0) (-3.5 -1.0 -1.5 1.0) (-1.0 1.5 1.0 3.5) (-1.0 -3.5 1.0 -1.5))

### next-to refuses another side

```x
(import x/gfx/figure)
(do
  (guard (e (Err text e)) (Figure next-to (Figure square 2) (Figure circle 1) 'over 0.5)))
```
---
    "Figure: next-to: SIDE is right, left, up or down"

## morph

### at 0 and at 1 it is the two figures; between, points and colours are between

The circle's first point is 1 0 and the square's 2 2.

```x
(import x/gfx/figure)
(do
  (def fig-morph
    (Figure morph (Figure fill (Figure circle 1) (list 200 0 0))
                  (Figure fill (Figure square 4) (list 0 100 0))))
  (def fig-half (fig-morph 0.5))
  (list (Figure bounds (fig-morph 0)) (List ref 1 (fig-morph 0))
        (Figure bounds (fig-morph 1)) (List ref 1 (fig-morph 1))
        ((first fig-half) ref 0 0) ((first fig-half) ref 0 1) (List ref 1 fig-half)))
```
---
    ((-1.0 -1.0 1.0 1.0) (200 0 0 255) (-2.0 -2.0 2.0 2.0) (0 100 0 255) 1.5 1.0 (100 50 0 255))

### the figure of fewer curves is cut into as many, its shape kept

```x
(import x/gfx/figure)
(do
  (def fig-start ((Figure morph (Figure triangle 1) (Figure circle 1)) 0))
  (list ((first fig-start) extent) (List ref 3 (Figure bounds fig-start))))
```
---
    ((13 2) 1.0)

## turn

### a half turn keeps the square's width on the way; a morph to the turned square does not

```x
(import x/gfx/figure)
(import x/num/float)
(do
  (def fig-width
    (fn (_ f) ((fn (_ b) (Float round (Float - (List ref 2 b) (List ref 0 b)))) (Figure bounds f))))
  (def fig-sq (Figure square 2))
  (def fig-spin (Figure turn fig-sq (Float pi)))
  (def fig-flip (Figure morph fig-sq (Figure rotate fig-sq (Float pi))))
  (list (fig-width (fig-spin 0.5)) (fig-width (fig-flip 0.5))
        (fig-width (fig-spin 1)) (fig-width (fig-flip 1))))
```
---
    (2.0 0.0 2.0 2.0)

## create and fade-out

### create draws none of the outline at 0, half at a half, all at 1

Half a square from its upper right corner is its top and left sides; filled,
that is the half above the diagonal. Four pixels a unit, the square from 8
to 24.

```x
(import x/gfx/canvas)
(import x/gfx/figure)
(do
  (def fig-grow (Figure create (Figure fill (Figure square 4) (list 9 8 7))))
  (def fig-at (fn (_ t x y) (Canvas pixel (Figure draw! (Canvas make 32 32) (fig-grow t)) x y)))
  (list (fig-at 0 12 12) (fig-at 0.5 12 12) (fig-at 0.5 20 20) (fig-at 1 20 20)))
```
---
    ((0 0 0 0) (9 8 7 255) (0 0 0 0) (9 8 7 255))

### fade-out takes the alphas evenly to 0

```x
(import x/gfx/figure)
(do
  (def fig-fade (Figure fade-out (Figure fill (Figure circle 1) (list 200 100 50))))
  (list (List ref 1 (fig-fade 0.5)) (List ref 2 (fig-fade 0.5)) (List ref 1 (fig-fade 1))))
```
---
    ((200 100 50 128) (255 255 255 128) (200 100 50 0))

## drawing

### a filled circle with a wide stroke: inside, on the line and outside

Ten pixels a unit: radius 20 about 40 40, the line from 18 to 22.

```x
(import x/gfx/canvas)
(import x/gfx/figure)
(do
  (def fig-disc (Figure stroke (Figure fill (Figure circle 2) (list 9 8 7)) (list 1 2 3) 0.4))
  (def fig-pic (Figure draw! (Canvas make 80 80) fig-disc))
  (list (Canvas pixel fig-pic 40 40) (Canvas pixel fig-pic 60 40) (Canvas pixel fig-pic 21 21)))
```
---
    ((9 8 7 255) (1 2 3 255) (0 0 0 0))
