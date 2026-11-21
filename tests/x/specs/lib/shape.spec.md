# Shape: outlines filled and stroked on a canvas, anti-aliased
# @weight 2

A point is (X . Y) in 1/256 of a pixel and a contour a list of points.
The cases run the pure-x coverage loop first; the last section builds the
compiled loop and draws one scene with each, byte for byte.

## fill

### a rectangle on whole pixels is the rectangle fill! draws

```x
(do (import x/gfx/canvas) (import x/gfx/shape) (import x/core/doors mem-cmp str->ptr)
  (def drawn (Shape fill! (Canvas make 5 4) (list (list (pair 256 256) (pair 1024 256) (pair 1024 768) (pair 256 768))) (list 9 8 7)))
  (def filled (Canvas fill! (Canvas make 5 4) 1 1 3 2 (list 9 8 7)))
  (mem-cmp (str->ptr (List ref 2 drawn)) (str->ptr (List ref 2 filled)) (* 4 5 4)))
```
---
    0

### half a pixel is alpha 128, across and down

```x
(do (import x/gfx/canvas) (import x/gfx/shape)
  (def across (List ref 2 (Shape mask (list (list (pair 128 0) (pair 640 0) (pair 640 256) (pair 128 256))))))
  (def down (List ref 2 (Shape mask (list (list (pair 0 128) (pair 256 128) (pair 256 384) (pair 0 384))))))
  (list (Canvas pixel across 0 0) (Canvas pixel across 1 0) (Canvas pixel across 2 0)
        (Canvas pixel down 0 0) (Canvas pixel down 0 1)))
```
---
    ((0 0 0 128) (0 0 0 255) (0 0 0 128) (0 0 0 128) (0 0 0 128))

### a triangle's alpha adds up to its area

Half of an 8 x 8 square: 28 whole pixels and 8 halves.

```x
(do (import x/gfx/canvas) (import x/gfx/shape)
  (def pic (List ref 2 (Shape mask (list (list (pair 0 0) (pair 2048 0) (pair 0 2048))))))
  (def sum-alpha
    (fn (self x y acc)
      (match ((= y 8) acc)
             ((= x 8) (self 0 (+ y 1) acc))
             (#t (self (+ x 1) y (+ acc (List ref 3 (Canvas pixel pic x y))))))))
  (list (first pic) (first (rest pic)) (sum-alpha 0 0 0)))
```
---
    (8 8 8164)

### either winding fills the same pixels

```x
(do (import x/gfx/canvas) (import x/gfx/shape) (import x/core/doors mem-cmp str->ptr)
  (def tri (list (pair 37 19) (pair 1900 333) (pair 700 1777)))
  (def one (List ref 2 (Shape mask (list tri))))
  (def other (List ref 2 (Shape mask (list (List reverse tri)))))
  (list (first one) (first (rest one))
        (mem-cmp (str->ptr (List ref 2 one)) (str->ptr (List ref 2 other)) (* 4 8 7))))
```
---
    (8 7 0)

### a contour wound the other way is a hole; wound the same way it is not

```x
(do (import x/gfx/canvas) (import x/gfx/shape)
  (def outer (list (pair 0 0) (pair 1024 0) (pair 1024 1024) (pair 0 1024)))
  (def inner (list (pair 256 256) (pair 768 256) (pair 768 768) (pair 256 768)))
  (def holed (List ref 2 (Shape mask (list outer (List reverse inner)))))
  (def solid (List ref 2 (Shape mask (list outer inner))))
  (list (Canvas pixel holed 0 0) (Canvas pixel holed 1 1) (Canvas pixel holed 2 2) (Canvas pixel holed 3 3)
        (Canvas pixel solid 1 1)))
```
---
    ((0 0 0 255) (0 0 0 0) (0 0 0 0) (0 0 0 255) (0 0 0 255))

### an edge taller than 128 pixels is halved and keeps its line

A triangle 4 wide and 400 down: its slope leaves 1/200 of a pixel a row.

```x
(do (import x/gfx/canvas) (import x/gfx/shape)
  (def pic (List ref 2 (Shape mask (list (list (pair 0 0) (pair 1024 0) (pair 0 102400))))))
  (list (Canvas pixel pic 3 0) (Canvas pixel pic 0 399) (Canvas pixel pic 1 399)
        (Canvas pixel pic 1 200) (Canvas pixel pic 0 200) (Canvas pixel pic 2 200)))
```
---
    ((0 0 0 254) (0 0 0 1) (0 0 0 0) (0 0 0 254) (0 0 0 255) (0 0 0 0))

## the canvas's edges

### an outline hanging off the canvas draws the part on it

The triangle's slope crosses the left edge between rows 3 and 4.

```x
(do (import x/gfx/canvas) (import x/gfx/shape)
  (def c (Shape fill! (Canvas make 4 8) (list (list (pair -1024 0) (pair 1024 0) (pair -1024 2048))) (list 255 255 255)))
  (list (Canvas pixel c 2 0) (Canvas pixel c 3 0) (Canvas pixel c 0 3) (Canvas pixel c 1 3) (Canvas pixel c 0 4)))
```
---
    ((255 255 255 255) (128 128 128 128) (128 128 128 128) (0 0 0 0) (0 0 0 0))

### what lies left of the canvas still fills to its right; what lies off it draws nothing

```x
(do (import x/gfx/canvas) (import x/gfx/shape)
  (def wide (Shape fill! (Canvas make 3 1) (list (list (pair -256000 0) (pair 384 0) (pair 384 256) (pair -256000 256))) (list 255 255 255)))
  (def off (Shape fill! (Canvas make 3 1) (list (list (pair 1024 0) (pair 2048 0) (pair 2048 256) (pair 1024 256))) (list 255 255 255)))
  (list (Canvas pixel wide 0 0) (Canvas pixel wide 1 0) (Canvas pixel wide 2 0) (Canvas pixel off 2 0)))
```
---
    ((255 255 255 255) (128 128 128 128) (0 0 0 0) (0 0 0 0))

### no contour, an empty one and a single point draw nothing

```x
(do (import x/gfx/canvas) (import x/gfx/shape)
  (list (Shape mask ()) (Shape mask (list ()))
        (Canvas pixel (Shape fill! (Canvas make 2 2) (list (list (pair 300 300))) (list 9 8 7)) 1 1)))
```
---
    (() () (0 0 0 0))

## stroke

### a translucent line is even where its pieces overlap

A corner: the middle of the first segment, then two pixels its first
segment, its disc and its second segment all cover.

```x
(do (import x/gfx/canvas) (import x/gfx/shape)
  (def c (Shape stroke! (Canvas make 12 12) (list (pair 512 512) (pair 2560 512) (pair 2560 2560)) 1024 (list 255 0 0 128) #f))
  (list (Canvas pixel c 5 2) (Canvas pixel c 9 2) (Canvas pixel c 9 3) (Canvas pixel c 5 5)))
```
---
    ((128 0 0 128) (128 0 0 128) (128 0 0 128) (0 0 0 0))

### closed joins the last point to the first

```x
(do (import x/gfx/canvas) (import x/gfx/shape)
  (def pts (list (pair 512 512) (pair 2560 512) (pair 2560 2560) (pair 512 2560)))
  (list (Canvas pixel (Shape stroke! (Canvas make 12 12) pts 512 (list 9 8 7) #f) 1 6)
        (Canvas pixel (Shape stroke! (Canvas make 12 12) pts 512 (list 9 8 7) #t) 1 6)))
```
---
    ((0 0 0 0) (9 8 7 255))

### a width under 2 raises

```x
(do (import x/gfx/canvas) (import x/gfx/shape)
  (guard (e (Err text e)) (Shape stroke! (Canvas make 2 2) (list (pair 0 0) (pair 256 256)) 1 (list 9 8 7) #f)))
```
---
    "Shape: stroke!: WIDTH is at least 2"

## cubic

### a quarter circle keeps its ends and stays within a quarter pixel

Radius 100 pixels: 16 lines, every point within 16/256 of the radius.

```x
(do (import x/gfx/shape)
  (def arc (Shape cubic (pair 25600 0) (pair 25600 14138) (pair 14138 25600) (pair 0 25600)))
  (def near?
    (fn (_ p)
      ((fn (_ rr) (if (< 654541056 rr) (< rr 656179456) #f))
       (+ (* (first p) (first p)) (* (rest p) (rest p))))))
  (list (first arc) (List ref 16 arc) (List length arc) (List all? near? arc)))
```
---
    ((25600 . 0) (0 . 25600) 17 #t)

## the compiled loop

### built where there is a JIT, it draws a scene byte for byte as the pure loop does

```x
(do (import x/gfx/canvas) (import x/gfx/shape) (import x/core/doors mem-cmp str->ptr)
  (def tri (list (pair 300 200) (pair 5800 900) (pair 2000 3900)))
  (def hole (list (pair 2000 1200) (pair 2600 2400) (pair 3400 1300)))
  (def scene
    (fn (_)
      (def c (Canvas fill! (Canvas make 24 16) 0 0 24 16 (list 5 5 5)))
      (Shape fill! c (list tri hole) (list 200 10 10 180))
      (Shape stroke! c (list (pair 700 3000) (pair 5000 3500) (pair 5600 500)) 700 (list 10 200 10 200) #t)
      c))
  (def pure (scene))
  (if (Shape jit!)
    (mem-cmp (str->ptr (List ref 2 pure)) (str->ptr (List ref 2 (scene))) (* 4 24 16))
    0))
```
---
    0

## strokes

### several lines are drawn together: where they cross they are drawn once

Two translucent lines 2 pixels wide, one across and one down, crossing at
2 2.

```x
(do (import x/gfx/canvas) (import x/gfx/shape)
  (def c (Shape strokes! (Canvas make 6 6)
           (list (pair #f (list (pair 256 768) (pair 1280 768)))
                 (pair #f (list (pair 768 256) (pair 768 1280))))
           512 (list 200 0 0 128)))
  (list (Canvas pixel c 1 2) (Canvas pixel c 2 2) (Canvas pixel c 2 4) (Canvas pixel c 4 4)))
```
---
    ((100 0 0 128) (100 0 0 128) (100 0 0 128) (0 0 0 0))

### one line is what stroke! draws; no line and a line of no points draw nothing

```x
(do (import x/gfx/canvas) (import x/gfx/shape) (import x/core/doors mem-cmp str->ptr)
  (def pts (list (pair 512 512) (pair 2560 512) (pair 2560 2560)))
  (def one (Shape stroke! (Canvas make 12 12) pts 700 (list 9 8 7 200) #t))
  (def all (Shape strokes! (Canvas make 12 12) (list (pair #t pts) (pair #f ())) 700 (list 9 8 7 200)))
  (list (mem-cmp (str->ptr (List ref 2 one)) (str->ptr (List ref 2 all)) (* 4 12 12))
        (Canvas pixel (Shape strokes! (Canvas make 2 2) () 700 (list 9 8 7)) 1 1)))
```
---
    (0 (0 0 0 0))
