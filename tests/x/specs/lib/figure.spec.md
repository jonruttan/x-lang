# Figure: outlines placed in a scene and changed over time
# @weight 2

A figure is (POINTS PATHS FILL STROKE WIDTH DRAWN): POINTS a Matrix of its
paths' points in scene units, the frame 8 units high, 0 0 its centre, y
up, and PATHS each path's (ROWS . CLOSED). An animation is a function of
progress answering a figure.

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
(import x/num/float/literal)
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
(import x/num/float/literal)
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
(import x/num/float/literal)
(import x/gfx/figure)
(do
  (def fig-morph
    (Figure morph (Figure fill (Figure circle 1) (list 200 0 0))
                  (Figure fill (Figure square 4) (list 0 100 0))))
  (def fig-half (fig-morph 0.5))
  (list (Figure bounds (fig-morph 0)) (List ref 2 (fig-morph 0))
        (Figure bounds (fig-morph 1)) (List ref 2 (fig-morph 1))
        ((first fig-half) ref 0 0) ((first fig-half) ref 0 1) (List ref 2 fig-half)))
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
(import x/num/float/literal)
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
(import x/num/float/literal)
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
(import x/num/float/literal)
(import x/gfx/figure)
(do
  (def fig-fade (Figure fade-out (Figure fill (Figure circle 1) (list 200 100 50))))
  (list (List ref 2 (fig-fade 0.5)) (List ref 3 (fig-fade 0.5)) (List ref 2 (fig-fade 1))))
```
---
    ((200 100 50 128) (255 255 255 128) (200 100 50 0))

## drawing

### a filled circle with a wide stroke: inside, on the line and outside

Ten pixels a unit: radius 20 about 40 40, the line from 18 to 22.

```x
(import x/num/float/literal)
(import x/gfx/canvas)
(import x/gfx/figure)
(do
  (def fig-disc (Figure stroke (Figure fill (Figure circle 2) (list 9 8 7)) (list 1 2 3) 0.4))
  (def fig-pic (Figure draw! (Canvas make 80 80) fig-disc))
  (list (Canvas pixel fig-pic 40 40) (Canvas pixel fig-pic 60 40) (Canvas pixel fig-pic 21 21)))
```
---
    ((9 8 7 255) (1 2 3 255) (0 0 0 0))

## lines and arrows

### a line is one path, not closed; an arrow is a shaft and two barbs

A line is one curve, 4 rows; an arrow's head is two more, 7 rows. The
barbs start 3/10 back from the tip and 3/20 out.

```x
(import x/gfx/figure)
(do
  (def fig-line (Figure line -1 0 2 3))
  (def fig-arrow (Figure arrow 0 0 2 0))
  (list (Figure bounds fig-line) (List ref 1 fig-line)
        (Figure bounds fig-arrow) (List ref 1 fig-arrow)
        ((first fig-arrow) ref 4 0) ((first fig-arrow) ref 4 1)))
```
---
    ((-1.0 0.0 2.0 3.0) ((4 . #f)) (0.0 -0.15 2.0 0.15) ((4 . #f) (7 . #f)) 1.7 0.15)

### an arrow whose tail is its tip raises

```x
(import x/gfx/figure)
(guard (e (Err text e)) (Figure arrow 1 1 1 1))
```
---
    "Figure: arrow: its ends are one point"

### a line is stroked and never filled

Eight pixels a unit on 64 by 64: a line 4 pixels wide along y = 32 from 16
to 48, given a fill it has no use for.

```x
(import x/num/float/literal)
(import x/gfx/canvas)
(import x/gfx/figure)
(do
  (def fig-bar (Figure fill (Figure stroke (Figure line -2 0 2 0) (list 9 8 7) 0.5) (list 200 0 0)))
  (def fig-bar-pic (Figure draw! (Canvas make 64 64) fig-bar))
  (list (Canvas pixel fig-bar-pic 32 31) (Canvas pixel fig-bar-pic 32 36) (Canvas pixel fig-bar-pic 32 20)))
```
---
    ((9 8 7 255) (0 0 0 0) (0 0 0 0))

### an arrow's shaft and barbs are drawn

Forty pixels a unit on 320 by 320, the stroke 10 wide: the shaft along
y = 160 from 80 to 240, and the upper barb from 228 154 to the tip, its
round end covering 226 150 above the shaft.

```x
(import x/num/float/literal)
(import x/gfx/canvas)
(import x/gfx/figure)
(do
  (def fig-tip-pic (Figure draw! (Canvas make 320 320) (Figure stroke (Figure arrow -2 0 2 0) (list 1 2 3) 0.25)))
  (list (Canvas pixel fig-tip-pic 100 158) (Canvas pixel fig-tip-pic 226 150) (Canvas pixel fig-tip-pic 200 140)))
```
---
    ((1 2 3 255) (1 2 3 255) (0 0 0 0))

### create draws a figure's paths in order: the shaft, then the head

The shaft is one curve of the arrow's three, so at 3/10 only part of it is
drawn.

```x
(import x/num/float/literal)
(import x/gfx/canvas)
(import x/gfx/figure)
(do
  (def fig-grow-arrow (Figure create (Figure stroke (Figure arrow -2 0 2 0) (list 1 2 3) 0.25)))
  (def fig-arrow-at (fn (_ t x y) (Canvas pixel (Figure draw! (Canvas make 320 320) (fig-grow-arrow t)) x y)))
  (list (fig-arrow-at 0.3 100 158) (fig-arrow-at 0.3 226 150) (fig-arrow-at 1 226 150)))
```
---
    ((1 2 3 255) (0 0 0 0) (1 2 3 255))

## onto

### the middles are made one

```x
(import x/gfx/figure)
(Figure bounds (Figure onto (Figure square 2) (Figure shift (Figure circle 3) 5 1)))
```
---
    (4.0 0.0 6.0 2.0)

## morph between unlike paths

### a path with no partner grows from the middle of the other figure

A line to an arrow: the line pairs with the shaft, and the head grows from
the line's middle, 0 0, to its place.

```x
(import x/num/float/literal)
(import x/gfx/figure)
(do
  (def fig-point (Figure morph (Figure line -2 0 2 0) (Figure arrow -2 0 2 0)))
  (list (List ref 1 (fig-point 0)) ((first (fig-point 0)) ref 4 0) ((first (fig-point 0)) ref 4 1)
        ((first (fig-point 0.5)) ref 4 0) ((first (fig-point 0.5)) ref 4 1)
        (Figure bounds (fig-point 1))))
```
---
    (((4 . #f) (7 . #f)) 0.0 0.0 0.85 0.075 (-2.0 -0.15 2.0 0.15))

### a path is closed on the way while either is, and as the second at the end

```x
(import x/num/float/literal)
(import x/gfx/figure)
(do
  (def fig-open (Figure morph (Figure square 2) (Figure line -1 0 1 0)))
  (list (List ref 1 (fig-open 0)) (List ref 1 (fig-open 0.5)) (List ref 1 (fig-open 1))))
```
---
    (((13 . #t)) ((13 . #t)) ((13 . #f)))

### a path whose points are one point draws nothing

A square to an arrow: at the start the head is a point at the square's
middle, 32 32 on 64 by 64, where the square's own stroke, 4 wide at 8
pixels out, does not reach.

```x
(import x/num/float/literal)
(import x/gfx/canvas)
(import x/gfx/figure)
(do
  (def fig-dot (Figure morph (Figure square 2) (Figure arrow -2 0 2 0)))
  (def fig-dot-pic (Figure draw! (Canvas make 64 64) (Figure stroke (fig-dot 0) (list 1 2 3) 0.5)))
  (list (List ref 1 (fig-dot 0)) (Canvas pixel fig-dot-pic 32 32) (Canvas pixel fig-dot-pic 40 32)))
```
---
    (((13 . #t) (7 . #f)) (0 0 0 0) (1 2 3 255))

## labels

### a label is its glyphs' strokes as lines, its box about 0 0

A capital 6 high makes a grid unit one unit: L is 4 wide and 6 high, three
points and so 7 rows, and its line a tenth of the height. H is three
strokes and i a stem and a dot.

```x
(import x/gfx/figure)
(do
  (def fig-ell (Figure label "L" 6))
  (list (Figure bounds fig-ell) (List ref 1 fig-ell) (List ref 4 fig-ell)
        (List ref 1 (Figure label "Hi" 1))))
```
---
    ((-2.0 -3.0 2.0 3.0) ((7 . #f)) 0.6 ((4 . #f) (4 . #f) (4 . #f) (4 . #f) (4 . #f)))

### a character is 6 across with its space; a space draws nothing and keeps its place

```x
(import x/gfx/figure)
(list (Figure bounds (Figure label "LL" 6)) (Figure bounds (Figure label "L L" 6))
      (List length (List ref 1 (Figure label "L L" 6))))
```
---
    ((-5.0 -3.0 5.0 3.0) (-8.0 -3.0 8.0 3.0) 2)

### text with no stroke raises

```x
(import x/gfx/figure)
(guard (e (Err text e)) (Figure label "  " 1))
```
---
    "Figure: label: nothing to draw"

### a label is drawn: on its strokes and off them

Eight pixels a unit on 64 by 64, a capital 4 units high: L's upright is at
x = 21.3 and its foot at y = 48, the line 3.2 wide.

```x
(import x/gfx/canvas)
(import x/gfx/figure)
(do
  (def fig-ell-pic (Figure draw! (Canvas make 64 64) (Figure label "L" 4)))
  (list (Canvas pixel fig-ell-pic 21 30) (Canvas pixel fig-ell-pic 30 47) (Canvas pixel fig-ell-pic 30 30)))
```
---
    ((255 255 255 255) (255 255 255 255) (0 0 0 0))
