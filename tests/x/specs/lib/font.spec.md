# Font: the printable ASCII characters as strokes
# @weight 1

A glyph is strokes on a grid 4 wide: the baseline 0, a capital's top 6, a
small letter's 4, a descender to -2. A stroke of one point is a dot.

## glyphs

### a letter of one stroke, of several, and one with a dot

```x
(import x/gfx/font)
(list (Font glyph 76) (Font glyph 84) (Font glyph 105))
```
---
    ((((0 . 6) (0 . 0) (4 . 0))) (((0 . 6) (4 . 6)) ((2 . 6) (2 . 0))) (((2 . 4) (2 . 0)) ((2 . 6))))

### a descender goes below the baseline

The tail of p runs from the top of a small letter to 2 below.

```x
(import x/gfx/font)
(first (Font glyph 112))
```
---
    ((0 . 4) (0 . -2))

### the space and codes outside 32 to 126 have no strokes

```x
(import x/gfx/font)
(list (Font glyph 32) (Font glyph 31) (Font glyph 127) (Font glyph 200))
```
---
    (() () () ())

### every other printable character has a stroke, and every point is on the grid

94 characters from ! to ~, each point's X from 0 to 4 and Y from -2 to 6.

```x
(import x/gfx/font)
(do
  (def fn-on-grid?
    (fn (_ p) (if (< -1 (first p)) (if (< (first p) 5) (if (< -3 (rest p)) (< (rest p) 7) #f) #f) #f)))
  (def fn-count
    (fn (self code drawn sound)
      (if (< code 127)
        ((fn (_ g)
           (self (+ code 1)
                 (if (null? g) drawn (+ drawn 1))
                 (if (List all? (fn (_ s) (List all? fn-on-grid? s)) g) sound #f)))
         (Font glyph code))
        (list drawn sound))))
  (fn-count 33 0 #t))
```
---
    (94 #t)

## metrics

### a character is 6 across and a capital 6 high

```x
(import x/gfx/font)
(list (Font advance) (Font cap))
```
---
    (6 6)
