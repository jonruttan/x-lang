# Canvas: an RGBA picture in memory and the operations a frame is drawn with
# @weight 2

A canvas is (WIDTH HEIGHT REGION), the shape Png decode answers. The
cases run the pure-x loops first; the last section builds the compiled
loops and draws one scene with each, byte for byte.

## pictures

### make answers transparent black

```x
(do (import x/gfx/canvas)
  (def c (Canvas make 3 2))
  (list (first c) (first (rest c)) (Canvas pixel c 0 0) (Canvas pixel c 2 1)))
```
---
    (3 2 (0 0 0 0) (0 0 0 0))

### rows maps each character to its colour; an unnamed one is clear

```x
(do (import x/gfx/canvas)
  (def c (Canvas rows (list "ab." ".ba") (list (list "a" 255 0 0) (list "b" 0 0 255 128))))
  (list (Canvas pixel c 0 0) (Canvas pixel c 1 0) (Canvas pixel c 2 0) (Canvas pixel c 2 1)))
```
---
    ((255 0 0 255) (0 0 255 128) (0 0 0 0) (255 0 0 255))

### a pixel off the canvas raises

```x
(do (import x/gfx/canvas)
  (guard (e (Err text e)) (Canvas pixel (Canvas make 2 2) 2 0)))
```
---
    "Canvas: pixel: X Y is off the canvas"

## fill, copy, blend, stamp

### fill sets a rectangle, alpha included, and clips at the edges

```x
(do (import x/gfx/canvas)
  (def c (Canvas make 3 3))
  (Canvas fill! c -1 -1 3 3 (list 9 8 7 6))
  (list (Canvas pixel c 0 0) (Canvas pixel c 1 1) (Canvas pixel c 2 2) (Canvas pixel c 2 0)))
```
---
    ((9 8 7 6) (9 8 7 6) (0 0 0 0) (0 0 0 0))

### copy moves a rectangle as it is, clipped to both canvases

```x
(do (import x/gfx/canvas)
  (def src (Canvas rows (list "ab" "cd") (list (list "a" 1 1 1) (list "b" 2 2 2) (list "c" 3 3 3 0) (list "d" 4 4 4))))
  (def dst (Canvas make 3 3))
  (Canvas copy! dst 2 1 src 0 0 2 2)
  (Canvas copy! dst -1 0 src 0 0 2 1)
  (list (Canvas pixel dst 0 0) (Canvas pixel dst 2 1) (Canvas pixel dst 2 2) (Canvas pixel dst 1 1)))
```
---
    ((2 2 2 255) (1 1 1 255) (3 3 3 0) (0 0 0 0))

### blend: alpha 0 leaves, 255 replaces, between mixes

```x
(do (import x/gfx/canvas)
  (def dst (Canvas fill! (Canvas make 3 1) 0 0 3 1 (list 0 0 255)))
  (def src (Canvas rows (list "zoh") (list (list "z" 9 9 9 0) (list "o" 255 0 0) (list "h" 255 0 0 128))))
  (Canvas blend! dst 0 0 src 0 0 3 1)
  (list (Canvas pixel dst 0 0) (Canvas pixel dst 1 0) (Canvas pixel dst 2 0)))
```
---
    ((0 0 255 255) (255 0 0 255) (128 0 127 255))

### stamp draws a colour in the source's shape, weighted by its alpha

```x
(do (import x/gfx/canvas)
  (def shape (Canvas rows (list "#h.") (list (list "#" 0 0 0) (list "h" 0 0 0 128))))
  (def dst (Canvas fill! (Canvas make 3 1) 0 0 3 1 (list 0 0 0)))
  (Canvas stamp! dst 0 0 shape 0 0 3 1 (list 200 100 50))
  (list (Canvas pixel dst 0 0) (Canvas pixel dst 1 0) (Canvas pixel dst 2 0)))
```
---
    ((200 100 50 255) (100 50 25 255) (0 0 0 255))

## nine pieces and text

### nine keeps the corners and stretches the edges and middle

```x
(do (import x/gfx/canvas)
  (def p (Canvas rows (list "aba" "bcb" "aba") (list (list "a" 1 1 1) (list "b" 2 2 2) (list "c" 3 3 3))))
  (def d (Canvas nine! (Canvas make 6 4) 0 0 6 4 p 1 1 1 1))
  (list (Canvas pixel d 0 0) (Canvas pixel d 3 0) (Canvas pixel d 5 0)
        (Canvas pixel d 0 2) (Canvas pixel d 4 2) (Canvas pixel d 5 3)))
```
---
    ((1 1 1 255) (2 2 2 255) (1 1 1 255) (2 2 2 255) (3 3 3 255) (1 1 1 255))

### text stamps each glyph a glyph apart; a character with none is a gap

```x
(do (import x/gfx/canvas)
  (def f (Canvas font (list (list "A" (list "#." ".#")) (list "B" (list "##" "##")))))
  (def d (Canvas text! (Canvas make 6 2) 0 0 "AxB" (list 5 6 7) f))
  (list (Canvas pixel d 0 0) (Canvas pixel d 1 0) (Canvas pixel d 1 1)
        (Canvas pixel d 2 0) (Canvas pixel d 4 0) (Canvas pixel d 5 1)))
```
---
    ((5 6 7 255) (0 0 0 0) (5 6 7 255) (0 0 0 0) (5 6 7 255) (5 6 7 255))

## light

### one cell lights its pixels evenly; alpha is kept

```x
(do (import x/gfx/canvas)
  (def d (Canvas fill! (Canvas make 4 4) 0 0 4 4 (list 255 200 100 77)))
  (Canvas light! d 0 0 4 4 (Canvas fill! (Canvas make 1 1) 0 0 1 1 (list 128 255 0)) 4)
  (list (Canvas pixel d 0 0) (Canvas pixel d 3 3)))
```
---
    ((128 200 0 77) (128 200 0 77))

### between two cells the light falls off smoothly, flat beyond the centres

```x
(do (import x/gfx/canvas)
  (def d (Canvas fill! (Canvas make 8 1) 0 0 8 1 (list 255 255 255)))
  (def m (Canvas fill! (Canvas fill! (Canvas make 2 1) 0 0 1 1 (list 255 255 255)) 1 0 1 1 (list 0 0 0)))
  (Canvas light! d 0 0 8 1 m 4)
  (List map (fn (_ x) (first (Canvas pixel d x 0))) (list 0 1 2 3 4 5 6 7)))
```
---
    (255 255 223 159 94 30 0 0)

### CELL must be a power of two

```x
(do (import x/gfx/canvas)
  (guard (e (Err text e)) (Canvas light! (Canvas make 2 2) 0 0 2 2 (Canvas make 1 1) 3)))
```
---
    "Canvas: light!: CELL is a power of two from 1 to 256"

## the compiled loops

### built where there is a JIT, they draw a scene byte for byte as the pure loops do

```x
(do (import x/gfx/canvas) (import x/core/doors mem-cmp str->ptr)
  (def tile (Canvas rows (list "abba" "b..b" "bhhb" "abba")
              (list (list "a" 200 10 10) (list "b" 10 200 10 200) (list "h" 9 9 200 77))))
  (def font (Canvas font (list (list "A" (list "#." ".#")))))
  (def m (Canvas fill! (Canvas fill! (Canvas make 3 3) 0 0 3 3 (list 40 40 60)) 1 1 1 1 (list 255 220 160)))
  (def scene
    (fn (_)
      (def c (Canvas fill! (Canvas make 24 16) 0 0 24 16 (list 5 5 5)))
      (Canvas copy! c 0 0 tile 0 0 4 4)
      (Canvas copy! c 22 14 tile 0 0 4 4)
      (Canvas blend! c 5 3 tile 0 0 4 4)
      (Canvas stamp! c 9 3 tile 0 0 4 4 (list 250 240 230 180))
      (Canvas nine! c 2 8 13 7 tile 1 1 1 1)
      (Canvas text! c 15 1 "AAA" (list 1 2 3) font)
      (Canvas light! c 0 0 24 16 m 8)
      c))
  (def pure (scene))
  (if (Canvas jit!)
    (mem-cmp (str->ptr (List ref 2 pure)) (str->ptr (List ref 2 (scene))) (* 4 24 16))
    0))
```
---
    0
