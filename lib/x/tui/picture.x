; tui/picture.x -- an RGBA image as terminal text: two pixels a cell.
;
; A cell shows the upper half block, its foreground the upper pixel and its
; background the lower, so a cell is two pixels, one above the other, and a
; terminal's cells, about twice as tall as wide, make the pixels square.  A
; pixel mostly transparent shows the terminal's own background: the lower
; half block in the lower pixel's colour, the upper alone, or a space.
;
; An image larger than the cells it is given is shrunk to fit, keeping its
; shape; each pixel drawn is the average of up to three by three samples of
; the area of the image it covers, weighted by alpha.  An image smaller is
; drawn a pixel a pixel.  Colours are 24-bit (SGR 38;2 and 48;2), or the
; nearest of the 256-colour palette's cube and greys for a terminal without.
; Out come lines of text and SGR escapes, each ending in the plain style.

(module x/tui/picture)
(import x/type/class)
(import x/type/vector)

(import x/core/doors int& int* int+ int- int/ int< int= int>> ptr-ref str->ptr)
(def %pc-cvt (prim-ref (lit convert) (lit to)))
(def %pc-string (Type named STRING))
; The decimal of each byte, made once.
(def %pc-num (Vector make 256 ""))
((fn (self i) (when (int< i 256) (Vector set! i (%pc-cvt i %pc-string 10) %pc-num) (self (int+ i 1)))) 0)
(def %pc-dec (fn (_ n) (Vector ref n %pc-num)))

(def %pc-min (fn (_ a b) (match ((int< a b) a) (#t b))))
(def %pc-max (fn (_ a b) (match ((int< a b) b) (#t a))))

; The pixels the image is drawn at: W x H fitted to COLS x 2*ROWS, its shape
; kept, never grown, at least one each way.
(def %pc-fit
  (fn (_ w h cols rows)
    (def tall (int* rows 2))
    (match ((match ((int< cols w) #f) ((int< tall h) #f) (#t #t)) (list w h))
           ((int< (int* tall w) (int* cols h))
             (list (%pc-max 1 (int/ (int* w tall) h)) tall))
           (#t (list cols (%pc-max 1 (int/ (int* h cols) w)))))))

; The average of up to three by three samples of the image's columns X0
; below X1 and rows Y0 below Y1, weighted by alpha: (R G B A).
(def %pc-sample
  (fn (_ p w x0 x1 y0 y1)
    (def kx (%pc-min (int- x1 x0) 3))
    (def ky (%pc-min (int- y1 y0) 3))
    (def at (fn (_ lo hi k j) (int+ lo (int/ (int* (int+ (int* j 2) 1) (int- hi lo)) (int* k 2)))))
    ((fn (self j i sr sg sb sa)
       (match ((int= j ky)
                (match ((int= sa 0) (list 0 0 0 0))
                       (#t (list (int/ sr sa) (int/ sg sa) (int/ sb sa) (int/ sa (int* kx ky))))))
              ((int= i kx) (self (int+ j 1) 0 sr sg sb sa))
              (#t (do (def o (int* (int+ (int* (at y0 y1 ky j) w) (at x0 x1 kx i)) 4))
                      (def a (int& (ptr-ref p (int+ o 3) 1) 255))
                      (self j (int+ i 1)
                            (int+ sr (int* (int& (ptr-ref p o 1) 255) a))
                            (int+ sg (int* (int& (ptr-ref p (int+ o 1) 1) 255) a))
                            (int+ sb (int* (int& (ptr-ref p (int+ o 2) 1) 255) a))
                            (int+ sa a))))))
     0 0 0 0 0 0)))

; The pixel at column TX of row TY of the TW x TH drawing, or nil for a
; transparent one or one past the bottom.
(def %pc-pixel
  (fn (_ p w h tw th tx ty)
    (match ((int< ty th)
             ((fn (_ c) (match ((int< (List ref 3 c) 128) ()) (#t c)))
              (%pc-sample p w (int/ (int* tx w) tw) (%pc-max (int/ (int* (int+ tx 1) w) tw) (int+ (int/ (int* tx w) tw) 1))
                              (int/ (int* ty h) th) (%pc-max (int/ (int* (int+ ty 1) h) th) (int+ (int/ (int* ty h) th) 1)))))
           (#t ()))))

; --- Colours ---------------------------------------------------------------

; The 256-colour palette's cube levels, and the nearest level of a value.
(def %pc-levels (list 0 95 135 175 215 255))
(def %pc-level (fn (_ v) (match ((int< v 48) 0) ((int< v 115) 1) (#t (int/ (int- v 35) 40)))))
(def %pc-sq (fn (_ x) (int* x x)))
(def %pc-dist
  (fn (_ r g b r2 g2 b2) (int+ (%pc-sq (int- r r2)) (int+ (%pc-sq (int- g g2)) (%pc-sq (int- b b2))))))
; The nearest of the cube's colours and the 24 greys (8, 18, ... 238).
(def %pc-index
  (fn (_ c)
    (def r (first c)) (def g (List ref 1 c)) (def b (List ref 2 c))
    (def ri (%pc-level r)) (def gi (%pc-level g)) (def bi (%pc-level b))
    (def cube (int+ 16 (int+ (int* ri 36) (int+ (int* gi 6) bi))))
    (def gk (%pc-min 23 (%pc-max 0 (int/ (int- (int/ (int+ r (int+ g b)) 3) 3) 10))))
    (def gv (int+ 8 (int* gk 10)))
    (match ((int< (%pc-dist r g b gv gv gv)
                  (%pc-dist r g b (List ref ri %pc-levels) (List ref gi %pc-levels) (List ref bi %pc-levels)))
             (int+ 232 gk))
           (#t cube))))

; The SGR parameters setting colour C as BASE (38 foreground, 48 background).
(def %pc-colour
  (fn (_ base c colours)
    (match ((eq? colours (lit rgb))
             (list base ";2;" (%pc-dec (first c)) ";" (%pc-dec (List ref 1 c)) ";" (%pc-dec (List ref 2 c))))
           (#t (list base ";5;" (%pc-dec (%pc-index c)))))))

; A cell as (TEXT FG BG): the half block and its colours, nil for the
; terminal's own.
(def %pc-cell
  (fn (_ top bottom)
    (match ((eq? top ()) (match ((eq? bottom ()) (list " " () ())) (#t (list "\xe2\x96\x84" bottom ()))))
           (#t (list "\xe2\x96\x80" top bottom)))))

; The escape setting a cell's colours from the plain style.
(def %pc-sgr
  (fn (_ cell colours)
    (Str8 join ""
      (List append (list "\x1b[0")
        (match ((eq? (List ref 1 cell) ()) ()) (#t (pair ";" (%pc-colour "38" (List ref 1 cell) colours))))
        (match ((eq? (List ref 2 cell) ()) ()) (#t (pair ";" (%pc-colour "48" (List ref 2 cell) colours))))
        (list "m")))))

; Line Y of the drawing: its cells, an escape where the colours change.
(def %pc-line
  (fn (_ p w h tw th y colours)
    ((fn (self x prev out)
       (match ((int= x tw) (Str8 join "" (List reverse (pair "\x1b[0m" out))))
              (#t (do (def cell (%pc-cell (%pc-pixel p w h tw th x (int* y 2))
                                          (%pc-pixel p w h tw th x (int+ (int* y 2) 1))))
                      (def look (rest cell))
                      (self (int+ x 1) look
                            (pair (first cell)
                                  (match ((equal? look prev) out) (#t (pair (%pc-sgr cell colours) out)))))))))
     0 #f ())))

(def-class Picture ()
  (doc "An RGBA image -- (WIDTH HEIGHT RGBA) as (Png decode) answers one -- drawn as terminal text, two pixels a cell in upper half blocks, shrunk to fit the cells it is given."
    (example "(Picture fit 640 480 80 24)" "(64 48)")
    (see lines) (see fit))
  (static
    (method fit (self (param width INTEGER "The image's width in pixels")
                      (param height INTEGER "Its height")
                      (param cols INTEGER "Cells across to draw it in")
                      (param rows INTEGER "Cells down"))
      (doc "The size the image is drawn at, in pixels: fitted to COLS across and twice ROWS down, its shape kept and never grown. A drawing H pixels tall takes (H + 1) / 2 rows."
        (returns LIST "(WIDTH HEIGHT)")
        (example "(Picture fit 640 480 80 24)" "(64 48)")
        (example "(Picture fit 16 16 80 24)" "(16 16)"))
      (%pc-fit width height cols rows))
    (method lines (self (param image LIST "(WIDTH HEIGHT RGBA): RGBA a buffer of 4 bytes a pixel, rows top to bottom")
                        (param cols INTEGER "Cells across to draw it in")
                        (param rows INTEGER "Cells down")
                        (param colours SYMBOL "rgb for 24-bit colour, indexed for the 256-colour palette"))
      (doc "The image as lines of text: each cell an upper half block, its foreground the pixel above and its background the pixel below, with SGR where the colours change and the plain style at each line's end. A pixel mostly transparent shows the terminal's background."
        (returns LIST "The lines, (H + 1) / 2 of them for a drawing H pixels tall")
        (example "(Picture lines (list 1 2 (first (Bytes of-list (list 255 0 0 255 0 0 255 255)))) 4 4 'rgb)" "(\"\\x1b[0;38;2;255;0;0;48;2;0;0;255m▀\\x1b[0m\")")
        (example "(Picture lines (list 1 2 (first (Bytes of-list (list 255 0 0 255 0 0 0 0)))) 4 4 'indexed)" "(\"\\x1b[0;38;5;196m▀\\x1b[0m\")"))
      (def w (first image))
      (def h (List ref 1 image))
      (def p (str->ptr (List ref 2 image)))
      (def size (%pc-fit w h cols rows))
      (def tw (first size))
      (def th (List ref 1 size))
      (List map (fn (_ y) (%pc-line p w h tw th y colours)) (List range 0 (int/ (int+ th 1) 2))))))

(doc (provide x/tui/picture Picture)
  "An RGBA image drawn as terminal text, two pixels a cell: (Picture lines image cols rows colours) answers the lines, (Picture fit w h cols rows) the size they draw it at.")
