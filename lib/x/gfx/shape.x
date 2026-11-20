; shape.x -- Shape: outlines filled and stroked on a canvas, their edges
; anti-aliased.
;
; A point is (X . Y), each an integer in 1/256 of a pixel: (256 . 512) is
; one pixel right and two down from the canvas's top left corner.  A
; contour is a list of points, closed from its last to its first; contours
; is a list of them, filled by the non-zero rule, so a contour wound the
; other way inside another is a hole.
;
; An outline is drawn in two steps.  Its coverage is gathered into a mask,
; a canvas whose alpha is the share of each pixel the outline covers, and
; the mask is drawn in a colour by (Canvas stamp!).  A stroke is the union
; of a quadrilateral a segment and a disc a point, gathered into one mask,
; so a translucent stroke is no darker where its pieces overlap.
;
; Coverage is exact area.  Each edge adds, a row at a time, the signed area
; to its right to one word a pixel; a running sum along the row is then the
; pixel's coverage, 131072 a whole pixel.  That sum is the kernel, written
; once as an integer function over addresses (x/tool/word-form) and
; compiled the way Canvas's are: adopted only after the compiled one writes
; what the pure one writes, once the masks made have covered %jit-threshold
; pixels or on (Shape jit!).  The edges are walked in pure x.
;
; Every product fits a 4-byte word: an edge longer than 128 pixels down or
; 8192 across is halved first.
(module x/gfx/shape)

(import x/gfx/canvas)
(import x/tool/compiled)
(import x/tool/word-form word-form-pure)
(import x/codec/bytes)

(import x/core/doors int& int* int+ int- int->ptr int/ int< int= ptr->int ptr-ref ptr-ref-word ptr-set-word! str->ptr)

(def %fail (fn (_ what) (Err raise (lit value) (Str8 append "Shape: " what) ())))

; --- The kernel, as a form -------------------------------------------------
;
; A is the row's words and D its pixels.  The word at I becomes the running
; sum, ACC plus what the edges left there, and the pixel's alpha its
; magnitude: 255 from a whole pixel up, else rounded.  A row has N pixels
; and one word more, where an edge in the last column leaves its remainder.

(def %alpha!
  (fn (_ v)
    (list (lit if) (list (lit <) 131071 v)
      (lit (%mem-byte-set-at! d (+ (<< i 2) 3) 255))
      (list (lit %mem-byte-set-at!) (lit d) (lit (+ (<< i 2) 3))
        (list (lit >>) (list (lit +) (list (lit *) v 255) 65536) 17)))))

(def %cover-form
  (list (lit fn) (lit (self a d i n h acc))
    (list (lit if) (lit (< i n))
      (list (lit do)
        (lit (%mem-set-at! a i (+ acc (%mem-ref-at a i))))
        (list (lit if) (lit (< (%mem-ref-at a i) 0))
          (%alpha! (lit (- 0 (%mem-ref-at a i))))
          (%alpha! (lit (%mem-ref-at a i))))
        (lit (self a d (+ i 1) n h (%mem-ref-at a i))))
      (list (lit if) (lit (< 1 h))
        (list (lit self) (list (lit +) (lit a) (list (lit *) (lit (+ n 1)) %word-size))
          (lit (+ d (<< n 2))) 0 (lit n) (lit (- h 1)) 0)
        0))))

(def %forms (list %cover-form))

(def %pure (List map word-form-pure %forms))

; The kernel in use: the pure one until the compiled one is installed, and
; the pure one again whenever Compiled installs it (before a state image is
; written).
(def %k-cover ())

(def %install! (fn (_ ks) (set! %k-cover (first ks))))

(%install! %pure)

; --- The compiled kernel, adopted only when it agrees ----------------------

(def %check-n 24)
(def %check-h 3)

; Rows of words no kernel could sum right by accident: both signs, and
; running sums past a whole pixel either way.
(def %check-words
  (fn (_)
    (def n (int* (int+ %check-n 1) %check-h))
    (def b (first (Bytes zeros (int* n %word-size))))
    ((fn (self i)
       (when (int< i n)
         (do (ptr-set-word! (str->ptr b) (int* i %word-size)
               (int* (int- (int& (int+ (int* i 37) (int+ (int/ (int* i i) 8) 11)) 255) 128) 700))
             (self (int+ i 1)))))
     0)
    b))

(def %same?
  (fn (self a b i n)
    (match ((int< i n) (match ((int= (ptr-ref a i 1) (ptr-ref b i 1)) (self a b (int+ i 1) n)) (#t #f)))
           (#t #t))))

; The kernel run pure and by the candidate on copies of one buffer, the
; masks and the summed words then compared byte for byte.
(def %agrees?
  (fn (_ engine)
    (def run
      (fn (_ k)
        (def a (%check-words))
        (def d (first (Bytes zeros (int* 4 (int* %check-n %check-h)))))
        (k (ptr->int (str->ptr a)) (ptr->int (str->ptr d)) 0 %check-n %check-h 0)
        (pair a d)))
    (def p (run (first %pure)))
    (def e (run (first engine)))
    (if (%same? (str->ptr (first p)) (str->ptr (first e)) 0 (int* (int* (int+ %check-n 1) %check-h) %word-size))
      (%same? (str->ptr (rest p)) (str->ptr (rest e)) 0 (int* 4 (int* %check-n %check-h)))
      #f)))

; Canvas's bar: a build is tried once this many pixels have been drawn.
(def %jit-threshold 65536)
(def %drawn 0)
(def %entry ())

(def %jit-try!
  (fn (_)
    (when (null? %entry)
      (set! %entry
        (Compiled make-on-demand (lit shape) %pure
          (fn (_)
            (import x/tool/word-form-jit)
            ((prim-ref (lit word-form) (lit jit-make)) %forms %agrees?))
          %install!)))
    ((fn (_ entry)
       (when (eq? (entry state) (lit interpreted)) (entry compile!))
       (eq? (entry state) (lit compiled)))
     %entry)))

(def %drawing
  (fn (_ n)
    (when (null? %entry)
      (do (set! %drawn (int+ %drawn n))
          (unless (int< %drawn %jit-threshold) (%jit-try!))))))

; --- Edges -----------------------------------------------------------------

(def %min (fn (_ a b) (if (int< b a) b a)))
(def %max (fn (_ a b) (if (int< a b) b a)))

; V / 256 rounded down, and rounded up, for either sign.
(def %floor8 (fn (_ v) (if (int< v 0) (int- 0 (int/ (int- 255 v) 256)) (int/ v 256))))
(def %ceil8 (fn (_ v) (int- 0 (%floor8 (int- 0 v)))))

(def %add!
  (fn (_ r i v)
    (ptr-set-word! (int->ptr r) (int* i %word-size)
      (int+ v (ptr-ref-word (int->ptr r) (int* i %word-size))))))

; An edge's piece within one row, from XA to XB, covering D of the row's
; height (signed, in 1/256): the area to its right goes to the row's words
; at R.  Within a column the piece leaves D times the room right of its
; middle to that column and the rest to the next, 512 a column's width.
; What lies left of the mask is left of all of it; what lies right of it
; is right of none.
(def %span!
  (fn (self r xmax xa xb d)
    (match
      ((int< xb xa) (self r xmax xb xa d))
      ((int< xb 1) (%add! r 0 (int* d 512)))
      ((int< xa xmax)
        (match
          ((int= xa xb)
            ((fn (_ col)
               ((fn (_ f)
                  (do (%add! r col (int* d (int- 512 f)))
                      (%add! r (int+ col 1) (int* d f))))
                (int* 2 (int- xa (int* col 256)))))
             (int/ xa 256)))
          (#t
            (do
              (def span (int- xb xa))
              (def end (%min xb xmax))
              (def share (fn (_ x) (int/ (int* d (int- x xa)) span)))
              (def before (if (int< xa 0) (share 0) 0))
              (when (int< xa 0) (%add! r 0 (int* before 512)))
              ((fn (self xl done)
                 (when (int< xl end)
                   ((fn (_ col)
                      ((fn (_ xr)
                         ((fn (_ upto f)
                            (do (%add! r col (int* (int- upto done) (int- 512 f)))
                                (%add! r (int+ col 1) (int* (int- upto done) f))
                                (self xr upto)))
                          (share xr)
                          (int- (int+ xl xr) (int* col 512))))
                       (%min (int* (int+ col 1) 256) xb)))
                    (int/ xl 256))))
               (%max xa 0) before)))))
      (#t 0))))

; The edge from X0 Y0 down to X1 Y1 (Y0 < Y1), DIR 1 when the contour runs
; down it and -1 when up, onto a mask W x H whose words start at A.
(def %edge!
  (fn (self a w h x0 y0 x1 y1 dir)
    (match
      ((int< y1 1) 0)
      ((int< y0 y1)
        (when (int< y0 (int* h 256))
          (if (match ((int< 32768 (int- y1 y0)) #t)
                     ((int< 2097152 (int- x1 x0)) #t)
                     ((int< 2097152 (int- x0 x1)) #t)
                     (#t #f))
            ((fn (_ mx my)
               (do (self a w h x0 y0 mx my dir)
                   (self a w h mx my x1 y1 dir)))
             (int/ (int+ x0 x1) 2) (int/ (int+ y0 y1) 2))
            (do
              (def dy (int- y1 y0))
              (def q (int/ (int- x1 x0) dy))
              (def r (int- (int- x1 x0) (int* q dy)))
              (def at (fn (_ t) (int+ x0 (int+ (int* q t) (int/ (int* r t) dy)))))
              (def end (%min y1 (int* h 256)))
              (def stride (int* (int+ w 1) %word-size))
              (def xmax (int* w 256))
              ((fn (self ya xa)
                 (when (int< ya end)
                   ((fn (_ row)
                      ((fn (_ yb)
                         ((fn (_ xb)
                            (do (%span! (int+ a (int* row stride)) xmax xa xb (int* (int- yb ya) dir))
                                (self yb xb)))
                          (at (int- yb y0))))
                       (%min (int* (int+ row 1) 256) end)))
                    (int/ ya 256))))
               (%max y0 0) (at (int- (%max y0 0) y0)))))))
      (#t 0))))

; Every edge of a contour, its points moved by -OX -OY first.
(def %contour!
  (fn (_ a w h ox oy points)
    (def edge
      (fn (_ p q)
        ((fn (_ x0 y0 x1 y1)
           (if (int< y0 y1)
             (%edge! a w h x0 y0 x1 y1 1)
             (%edge! a w h x1 y1 x0 y0 -1)))
         (int- (first p) ox) (int- (rest p) oy) (int- (first q) ox) (int- (rest q) oy))))
    (unless (null? points)
      ((fn (self p more)
         (if (null? more)
           (edge p (first points))
           (do (edge p (first more))
               (self (first more) (rest more)))))
       (first points) (rest points)))))

; --- Masks -----------------------------------------------------------------

; (MINX MINY MAXX MAXY) over every point, or () when there is none.
(def %bounds
  (fn (_ contours)
    (List fold
      (fn (_ box points)
        (List fold
          (fn (_ b p)
            (if (null? b)
              (list (first p) (rest p) (first p) (rest p))
              (list (%min (first b) (first p))
                    (%min (first (rest b)) (rest p))
                    (%max (first (rest (rest b))) (first p))
                    (%max (first (rest (rest (rest b)))) (rest p)))))
          box points))
      () contours)))

; The mask of CONTOURS within the pixels LEFT TOP to RIGHT BOTTOM, or all
; of it when CLIP is #f: (X Y CANVAS), or () when no pixel is touched.
(def %mask
  (fn (_ contours clip left top right bottom)
    (def b (%bounds contours))
    (if (null? b)
      ()
      ((fn (_ x0 y0 x1 y1)
         ((fn (_ ox oy w h)
            (if (if (int< 0 w) (int< 0 h) #f)
              (do
                (def words (first (Bytes zeros (int* (int* (int+ w 1) h) %word-size))))
                (def m (Canvas make w h))
                (def a (ptr->int (str->ptr words)))
                (List for-each (fn (_ points) (%contour! a w h (int* ox 256) (int* oy 256) points)) contours)
                (%drawing (int* w h))
                (%k-cover a (ptr->int (str->ptr (first (rest (rest m))))) 0 w h 0)
                (list ox oy m))
              ()))
          x0 y0 (int- x1 x0) (int- y1 y0)))
       (if clip (%max left (%floor8 (first b))) (%floor8 (first b)))
       (if clip (%max top (%floor8 (first (rest b)))) (%floor8 (first (rest b))))
       (if clip (%min right (%ceil8 (first (rest (rest b))))) (%ceil8 (first (rest (rest b)))))
       (if clip (%min bottom (%ceil8 (first (rest (rest (rest b)))))) (%ceil8 (first (rest (rest (rest b))))))))))

(def %fill!
  (fn (_ c contours colour)
    ((fn (_ m)
       (unless (null? m)
         ((fn (_ pic)
            (Canvas stamp! c (first m) (first (rest m)) pic 0 0 (first pic) (first (rest pic)) colour))
          (first (rest (rest m))))))
     (%mask contours #t 0 0 (first c) (first (rest c))))
    c))

; --- Curves ----------------------------------------------------------------

(def %abs (fn (_ v) (if (int< v 0) (int- 0 v) v)))
(def %mid (fn (_ p q) (pair (int/ (int+ (first p) (first q)) 2) (int/ (int+ (rest p) (rest q)) 2))))

; A cubic lies within a quarter pixel of its chord when both control
; points are within 181/3 of the chord's thirds, each way.
(def %flat?
  (fn (_ p0 p1 p2 p3)
    (def near
      (fn (_ a b c d)
        (if (int< (%abs (int- (int* 3 b) (int+ (int* 2 a) d))) 182)
          (int< (%abs (int- (int* 3 c) (int+ a (int* 2 d)))) 182)
          #f)))
    (if (near (first p0) (first p1) (first p2) (first p3))
      (near (rest p0) (rest p1) (rest p2) (rest p3))
      #f)))

; The curve's points after P0, ahead of TAIL: halved until each half is
; flat, or 16 times.
(def %cubic
  (fn (self p0 p1 p2 p3 depth tail)
    (if (if (int< 15 depth) #t (%flat? p0 p1 p2 p3))
      (pair p3 tail)
      ((fn (_ a b c)
         ((fn (_ ab bc)
            ((fn (_ m)
               (self p0 a ab m (int+ depth 1)
                 (self m bc c p3 (int+ depth 1) tail)))
             (%mid ab bc)))
          (%mid a b) (%mid b c)))
       (%mid p0 p1) (%mid p1 p2) (%mid p2 p3)))))

; --- Strokes ---------------------------------------------------------------

; The integer square root of N, 0 to 2^30.
(def %isqrt
  (fn (_ n)
    (if (int< n 1)
      0
      ((fn (self x)
         ((fn (_ y) (if (int< y x) (self y) x))
          (int/ (int+ x (int/ n x)) 2)))
       32768))))

; DX DY doubled or halved until the longer is 2048 to 4095, so that its
; length is known to one part in 2048.
(def %scaled
  (fn (self dx dy)
    ((fn (_ m)
       (match ((int< 4095 m) (self (int/ dx 2) (int/ dy 2)))
              ((int< m 2048) (self (int* dx 2) (int* dy 2)))
              (#t (pair dx dy))))
     (%max (%abs dx) (%abs dy)))))

; The segment P Q widened HALF each side, or () when P is Q.
(def %quad
  (fn (_ p q half)
    (if (if (int= (first p) (first q)) (int= (rest p) (rest q)) #f)
      ()
      ((fn (_ d)
         ((fn (_ len)
            ((fn (_ nx ny)
               (list (pair (int+ (first p) nx) (int+ (rest p) ny))
                     (pair (int+ (first q) nx) (int+ (rest q) ny))
                     (pair (int- (first q) nx) (int- (rest q) ny))
                     (pair (int- (first p) nx) (int- (rest p) ny))))
             (int/ (int* (int- 0 (rest d)) half) len)
             (int/ (int* (first d) half) len)))
          (%isqrt (int+ (int* (first d) (first d)) (int* (rest d) (rest d))))))
       (%scaled (int- (first q) (first p)) (int- (rest q) (rest p)))))))

; A disc of radius R about 0 0 as four cubics, wound as %quad winds.
(def %disc
  (fn (_ r)
    (def k (int/ (int* r 2262) 4096))
    (def n (int- 0 r))
    (def j (int- 0 k))
    (pair (pair r 0)
      (%cubic (pair r 0) (pair r j) (pair k n) (pair 0 n) 0
        (%cubic (pair 0 n) (pair j n) (pair n j) (pair n 0) 0
          (%cubic (pair n 0) (pair n k) (pair j r) (pair 0 r) 0
            (%cubic (pair 0 r) (pair k r) (pair r k) (pair r 0) 0 ())))))))

(def %moved
  (fn (_ points p)
    (List map (fn (_ d) (pair (int+ (first d) (first p)) (int+ (rest d) (rest p)))) points)))

; A stroke's contours: a quadrilateral a segment and a disc a point.
(def %stroke
  (fn (_ points width closed)
    (def half (int/ width 2))
    (def disc (%disc half))
    (def quads
      (fn (self p more out)
        (if (null? more)
          (if closed (pair (%quad p (first points) half) out) out)
          (self (first more) (rest more) (pair (%quad p (first more) half) out)))))
    (List fold
      (fn (_ out p) (pair (%moved disc p) out))
      (quads (first points) (rest points) ())
      points)))

(def-class Shape ()
  (doc "Outlines filled and stroked on a canvas, their edges anti-aliased. A point is (X . Y), each in 1/256 of a pixel; a contour is a list of points, closed from its last to its first. An outline's coverage is gathered into a mask and the mask drawn by (Canvas stamp!). The loop that turns the edges' areas into the mask is compiled once a process when the masks made have covered 65,536 pixels, and only after it agrees with the pure-x loop."
    (example "(do (import x/gfx/canvas) (Canvas pixel (Shape fill! (Canvas make 4 4) (list (list (pair 256 256) (pair 768 256) (pair 768 768) (pair 256 768))) (list 9 8 7)) 2 2))" "(9 8 7 255)")
    (see fill!) (see stroke!))
  (static
    (method mask (self (param contours LIST "Contours, each a list of (X . Y) points"))
      (doc "The coverage of CONTOURS, filled by the non-zero rule: a canvas over the pixels they touch whose alpha is the share of each pixel inside, 255 a whole pixel, its colours zero. A contour wound the other way inside another is a hole. The canvas is as large as the outline, wherever it lies."
        (returns LIST "(X Y CANVAS), the canvas and the pixel its top left corner is at; () when the contours have no point or their bounds hold no pixel")
        (example "(do (import x/gfx/canvas) (def m (Shape mask (list (list (pair 128 0) (pair 384 0) (pair 384 256) (pair 128 256))))) (list (first m) (first (rest m)) (Canvas pixel (first (rest (rest m))) 0 0) (Canvas pixel (first (rest (rest m))) 1 0)))" "(0 0 (0 0 0 128) (0 0 0 128))"))
      (%mask contours #f 0 0 0 0))

    (method fill! (self (param c LIST "The canvas drawn on")
                        (param contours LIST "Contours, each a list of (X . Y) points")
                        (param colour LIST "(R G B) or (R G B A)"))
      (doc "Draw COLOUR over the canvas inside CONTOURS, by the non-zero rule, at each pixel by the share of it inside. Only the part on the canvas is gathered and drawn."
        (returns LIST "The canvas")
        (example "(do (import x/gfx/canvas) (Canvas pixel (Shape fill! (Canvas make 2 1) (list (list (pair 0 0) (pair 384 0) (pair 384 256) (pair 0 256))) (list 255 255 255)) 1 0))" "(128 128 128 128)"))
      (%fill! c contours colour))

    (method stroke! (self (param c LIST "The canvas drawn on")
                          (param points LIST "The line's (X . Y) points")
                          (param width INTEGER "The line's width in 1/256 of a pixel, 2 or more")
                          (param colour LIST "(R G B) or (R G B A)")
                          (param closed BOOL "#t to join the last point to the first"))
      (doc "Draw a line WIDTH wide through POINTS in COLOUR, round at its ends and its joins. Where its pieces overlap it is drawn once, so a translucent line is even. Raises a label 'value when WIDTH is under 2."
        (returns LIST "The canvas")
        (example "(do (import x/gfx/canvas) (Canvas pixel (Shape stroke! (Canvas make 4 4) (list (pair 256 512) (pair 768 512)) 512 (list 9 8 7) #f) 1 1))" "(9 8 7 255)"))
      (when (int< width 2) (%fail "stroke!: WIDTH is at least 2"))
      (if (null? points) c (%fill! c (%stroke points width closed) colour)))

    (method cubic (self (param p0 LIST "The start, (X . Y)")
                        (param p1 LIST "The first control point")
                        (param p2 LIST "The second control point")
                        (param p3 LIST "The end"))
      (doc "The points of a cubic Bezier curve, from P0 to P3 as they are, with as many between as keep the lines through them within a quarter pixel of the curve."
        (returns LIST "Points, P0 first and P3 last")
        (example "(Shape cubic (pair 0 0) (pair 100 0) (pair 200 0) (pair 300 0))" "((0 . 0) (300 . 0))"))
      (pair p0 (%cubic p0 p1 p2 p3 0 ())))

    (method jit! (self)
      (doc "Build and adopt the compiled coverage loop (JIT; ARM64 and x86-64 backends) now, if it writes the check rows exactly as the pure-x loop does. Idempotent. Answers #t when it is in use, #f when it is not: the pure-x loop carries on, writing the same masks."
        (returns BOOL "#t when the compiled loop is in use")
        (sample "(Shape jit!)" "#t"))
      (%jit-try!))))

(doc (provide x/gfx/shape Shape)
  "Outlines filled and stroked on a canvas with anti-aliased edges, points in 1/256 of a pixel: (Shape fill! c contours colour), stroke!, mask and cubic."
  (example "(Shape cubic (pair 0 0) (pair 100 0) (pair 200 0) (pair 300 0))" "((0 . 0) (300 . 0))"))
