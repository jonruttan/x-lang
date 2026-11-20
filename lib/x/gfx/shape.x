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
; pixel's coverage, 131072 a whole pixel.
;
; The outline is packed into words first, each contour its count and then
; its points, a count of 0 after the last.  Three kernels work on words:
; one walks the packed edges, one sums the rows into the mask, one copies a
; stroke's disc to a point.  Each is written once as an integer function
; over addresses (x/tool/word-form) and compiled the way Canvas's are:
; adopted only after the compiled ones write what the pure ones write, once
; the masks made have covered %jit-threshold pixels or on (Shape jit!).
;
; Every quotient is of numbers that are not negative.  On a 4-byte word
; every product fits while an edge runs under 16384 pixels across.
(module x/gfx/shape)

(import x/gfx/canvas)
(import x/tool/compiled)
(import x/tool/word-form word-form-pure)
(import x/codec/bytes)

(import x/core/doors int& int* int+ int- int->ptr int/ int< int= ptr->int ptr-ref ptr-ref-word ptr-set-word! str->ptr)

(def %fail (fn (_ what) (Err raise (lit value) (Str8 append "Shape: " what) ())))

; --- The row sum, as a form ------------------------------------------------
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

; --- The edge walk, as a form ----------------------------------------------
;
; The walk keeps what it knows in words at S, named here in order.  The
; first four are the caller's: the mask's words, a row's count of them, and
; the mask's width and height in 1/256.  POS is the word of the contour's
; count among the packed words at P.
;
; The source below names them: (get NAME) reads one, (put! NAME V) stores
; one, (add! I V) adds V to the mask's word I, and (least A B) and
; (most A B) are the lesser and the greater.

(def %fields
  (lit (acc w1 xmax ymax pos n i x0 y0 x1 y1 dir dy adx sx xrel rem ya xa yb xb d rb lo hi span end xl done t u v)))

(def %field
  (fn (_ name)
    ((fn (self k names)
       (match ((null? names) (%fail "no such field"))
              ((eq? (first names) name) k)
              (#t (self (int+ k 1) (rest names)))))
     0 %fields)))

(def %expand
  (fn (self f)
    (match
      ((pair? f)
        (match
          ((eq? (first f) (lit get))
            (list (lit %mem-ref-at) (lit s) (%field (first (rest f)))))
          ((eq? (first f) (lit put!))
            (list (lit %mem-set-at!) (lit s) (%field (first (rest f))) (self (first (rest (rest f))))))
          ((eq? (first f) (lit add!))
            ((fn (_ at i v)
               (list (lit %mem-set-at!) at i (list (lit +) (list (lit %mem-ref-at) at i) v)))
             (list (lit %mem-ref-at) (lit s) (%field (lit acc)))
             (self (first (rest f)))
             (self (first (rest (rest f))))))
          ((eq? (first f) (lit least))
            ((fn (_ a b) (list (lit if) (list (lit <) a b) a b))
             (self (first (rest f))) (self (first (rest (rest f))))))
          ((eq? (first f) (lit most))
            ((fn (_ a b) (list (lit if) (list (lit <) a b) b a))
             (self (first (rest f))) (self (first (rest (rest f))))))
          (#t (List map self f))))
      (#t f))))

; MODE is where the walk is: 0 at a contour, 1 at its next edge, 2 at an
; edge's constants, 3 at the edge's next row, 4 at the row's next column.
;
; An edge runs down from X0 Y0 to X1 Y1, DIR 1 when its contour runs down
; it and -1 when up.  At YA it is XREL across from X0 with REM over DY left
; of the division, so the next row's is one division more and exact.  A
; row's piece from LO to HI covers D of the row's height; within a column
; it leaves D times the room right of its middle to that column and the
; rest to the next, 512 a column's width.  What lies left of the mask is
; left of all of it; what lies right of it is right of none.
(def %walk-form
  (%expand
    (lit
      (fn (self s p mode)
        (match
          ((= mode 0)
            (if (< (%mem-ref-at p (get pos)) 1)
              0
              (do (put! n (%mem-ref-at p (get pos)))
                  (put! i 0)
                  (self s p 1))))
          ((= mode 1)
            (if (< (get i) (get n))
              (do (put! t (+ (get pos) (+ 1 (<< (get i) 1))))
                  (put! u (+ (get pos) (+ 1 (<< (if (= (+ (get i) 1) (get n)) 0 (+ (get i) 1)) 1))))
                  (put! i (+ (get i) 1))
                  (if (< (%mem-ref-at p (+ (get t) 1)) (%mem-ref-at p (+ (get u) 1)))
                    (do (put! x0 (%mem-ref-at p (get t)))
                        (put! y0 (%mem-ref-at p (+ (get t) 1)))
                        (put! x1 (%mem-ref-at p (get u)))
                        (put! y1 (%mem-ref-at p (+ (get u) 1)))
                        (put! dir 1))
                    (do (put! x0 (%mem-ref-at p (get u)))
                        (put! y0 (%mem-ref-at p (+ (get u) 1)))
                        (put! x1 (%mem-ref-at p (get t)))
                        (put! y1 (%mem-ref-at p (+ (get t) 1)))
                        (put! dir -1)))
                  (self s p 2))
              (do (put! pos (+ (get pos) (+ 1 (<< (get n) 1))))
                  (self s p 0))))
          ((= mode 2)
            (match
              ((= (get y0) (get y1)) (self s p 1))
              ((< (get y1) 1) (self s p 1))
              ((< (get y0) (get ymax))
                (do (put! dy (- (get y1) (get y0)))
                    (if (< (get x1) (get x0))
                      (do (put! adx (- (get x0) (get x1))) (put! sx -1))
                      (do (put! adx (- (get x1) (get x0))) (put! sx 1)))
                    (put! xrel 0)
                    (put! rem 0)
                    (put! ya (get y0))
                    (put! xa (get x0))
                    (self s p 3)))
              (#t (self s p 1))))
          ((= mode 3)
            (match
              ((< (get ya) (get y1))
                (match
                  ((< (get ya) (get ymax))
                    (do (put! t (<< (+ (>> (get ya) 8) 1) 8))
                        (if (< (get t) (get y1))
                          (do (put! yb (get t))
                              (put! u (+ (get rem) (* (get adx) (- (get yb) (get ya)))))
                              (put! v (/ (get u) (get dy)))
                              (put! xrel (+ (get xrel) (get v)))
                              (put! rem (- (get u) (* (get v) (get dy))))
                              (put! xb (+ (get x0) (* (get sx) (get xrel)))))
                          (do (put! yb (get y1))
                              (put! xb (get x1))))
                        (put! d (- (get yb) (get ya)))
                        (put! lo (least (get xa) (get xb)))
                        (put! hi (most (get xa) (get xb)))
                        (put! rb (* (>> (get ya) 8) (get w1)))
                        (put! t (get ya))
                        (put! ya (get yb))
                        (put! xa (get xb))
                        (match
                          ((< (get t) 0) (self s p 3))
                          ((< (get hi) 1)
                            (do (add! (get rb) (* (get dir) (* (get d) 512)))
                                (self s p 3)))
                          ((< (get lo) (get xmax))
                            (if (= (get lo) (get hi))
                              (do (put! u (>> (get lo) 8))
                                  (put! v (<< (- (get lo) (<< (get u) 8)) 1))
                                  (add! (+ (get rb) (get u)) (* (get dir) (* (get d) (- 512 (get v)))))
                                  (add! (+ (get rb) (+ (get u) 1)) (* (get dir) (* (get d) (get v))))
                                  (self s p 3))
                              (do (put! span (- (get hi) (get lo)))
                                  (put! end (least (get hi) (get xmax)))
                                  (if (< (get lo) 0)
                                    (do (put! done (/ (* (get d) (- 0 (get lo))) (get span)))
                                        (add! (get rb) (* (get dir) (* (get done) 512)))
                                        (put! xl 0))
                                    (do (put! done 0)
                                        (put! xl (get lo))))
                                  (self s p 4))))
                          (#t (self s p 3)))))
                  (#t (self s p 1))))
              (#t (self s p 1))))
          (#t
            (if (< (get xl) (get end))
              (do (put! u (>> (get xl) 8))
                  (put! t (least (<< (+ (get u) 1) 8) (get hi)))
                  (put! v (/ (* (get d) (- (get t) (get lo))) (get span)))
                  (add! (+ (get rb) (get u))
                    (* (get dir) (* (- (get v) (get done)) (- 512 (- (+ (get xl) (get t)) (<< (get u) 9))))))
                  (add! (+ (get rb) (+ (get u) 1))
                    (* (get dir) (* (- (get v) (get done)) (- (+ (get xl) (get t)) (<< (get u) 9)))))
                  (put! xl (get t))
                  (put! done (get v))
                  (self s p 4))
              (self s p 3))))))))

; --- The disc copy, as a form ----------------------------------------------

; N points at T copied to D, each moved by DX DY.
(def %move-form
  (lit
    (fn (self d t i n dx dy)
      (if (< i n)
        (do (%mem-set-at! d (<< i 1) (+ (%mem-ref-at t (<< i 1)) dx))
            (%mem-set-at! d (+ (<< i 1) 1) (+ (%mem-ref-at t (+ (<< i 1) 1)) dy))
            (self d t (+ i 1) n dx dy))
        0))))

(def %forms (list %cover-form %walk-form %move-form))

(def %pure (List map word-form-pure %forms))

; The kernels in use: the pure ones until the compiled ones are installed,
; and the pure ones again whenever Compiled installs them (before a state
; image is written).
(def %k-cover ())
(def %k-walk ())
(def %k-move ())

(def %install!
  (fn (_ ks)
    (set! %k-cover (first ks))
    (set! %k-walk (first (rest ks)))
    (set! %k-move (first (rest (rest ks))))))

(%install! %pure)

; --- Words -----------------------------------------------------------------

(def %words (fn (_ n) (first (Bytes zeros (int* n %word-size)))))
(def %at (fn (_ buf) (ptr->int (str->ptr buf))))
(def %put! (fn (_ a i v) (ptr-set-word! (int->ptr a) (int* i %word-size) v)))

; --- The compiled kernels, adopted only when they agree --------------------

(def %check-n 16)
(def %check-h 12)

; Rows of words no kernel could sum right by accident: both signs, and
; running sums past a whole pixel either way.
(def %check-words
  (fn (_)
    (def n (int* (int+ %check-n 1) %check-h))
    (def b (%words n))
    ((fn (self i)
       (when (int< i n)
         (do (%put! (%at b) i
               (int* (int- (int& (int+ (int* i 37) (int+ (int/ (int* i i) 8) 11)) 255) 128) 700))
             (self (int+ i 1)))))
     0)
    b))

; An outline for the walk: a triangle off three sides of the mask, one
; inside it wound the other way, a rectangle of upright and level edges, and
; a triangle left of the mask.  Each is X Y X Y ...
(def %check-outline
  (lit ((-300 -200 5000 900 2100 4100)
        (1500 1200 1800 2400 2600 1300)
        (64 64 64 700 1000 700 1000 64)
        (-900 300 -500 2000 -100 600))))

(def %check-packed
  (fn (_)
    (def b (%words 64))
    (List fold
      (fn (_ pos flat)
        (do (%put! (%at b) pos (int/ (List length flat) 2))
            (List fold (fn (_ k v) (do (%put! (%at b) k v) (int+ k 1))) (int+ pos 1) flat)))
      0 %check-outline)
    b))

(def %same?
  (fn (self a b i n)
    (match ((int< i n) (match ((int= (ptr-ref a i 1) (ptr-ref b i 1)) (self a b (int+ i 1) n)) (#t #f)))
           (#t #t))))

(def %same-words? (fn (_ a b n) (%same? (str->ptr a) (str->ptr b) 0 (int* n %word-size))))

; Each kernel run pure and by the candidate on copies of one buffer, what
; the two wrote then compared byte for byte.
(def %agrees?
  (fn (_ engine)
    (def cover
      (fn (_ k)
        (def a (%check-words))
        (def d (first (Bytes zeros (int* 4 (int* %check-n %check-h)))))
        (k (%at a) (%at d) 0 %check-n %check-h 0)
        (pair a d)))
    (def walk
      (fn (_ k)
        (def a (%words (int* (int+ %check-n 1) %check-h)))
        (def s (%words (List length %fields)))
        (def p (%check-packed))
        (%put! (%at s) (%field (lit acc)) (%at a))
        (%put! (%at s) (%field (lit w1)) (int+ %check-n 1))
        (%put! (%at s) (%field (lit xmax)) (int* %check-n 256))
        (%put! (%at s) (%field (lit ymax)) (int* %check-h 256))
        (k (%at s) (%at p) 0)
        a))
    (def move
      (fn (_ k)
        (def t (%check-words))
        (def d (%words 24))
        (k (%at d) (%at t) 0 12 -777 4242)
        d))
    (def pc (cover (first %pure)))
    (def ec (cover (first engine)))
    (match
      ((%same-words? (first pc) (first ec) (int* (int+ %check-n 1) %check-h))
        (match
          ((%same? (str->ptr (rest pc)) (str->ptr (rest ec)) 0 (int* 4 (int* %check-n %check-h)))
            (match
              ((%same-words? (walk (first (rest %pure))) (walk (first (rest engine))) (int* (int+ %check-n 1) %check-h))
                (%same-words? (move (first (rest (rest %pure)))) (move (first (rest (rest engine)))) 24))
              (#t #f)))
          (#t #f)))
      (#t #f))))

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

; --- Masks -----------------------------------------------------------------

(def %min (fn (_ a b) (if (int< b a) b a)))
(def %max (fn (_ a b) (if (int< a b) b a)))

; V / 256 rounded down, and rounded up, for either sign.
(def %floor8 (fn (_ v) (if (int< v 0) (int- 0 (int/ (int- 255 v) 256)) (int/ v 256))))
(def %ceil8 (fn (_ v) (int- 0 (%floor8 (int- 0 v)))))

; (MINX MINY MAXX MAXY) over every point, or () when there is none.
(def %bounds
  (fn (_ contours)
    ((fn (self cs pts any x0 y0 x1 y1)
       (match
         ((null? pts)
           (match ((null? cs) (if any (list x0 y0 x1 y1) ()))
                  (#t (self (rest cs) (first cs) any x0 y0 x1 y1))))
         (any
           (self cs (rest pts) #t
             (%min x0 (first (first pts))) (%min y0 (rest (first pts)))
             (%max x1 (first (first pts))) (%max y1 (rest (first pts)))))
         (#t
           (self cs (rest pts) #t
             (first (first pts)) (rest (first pts)) (first (first pts)) (rest (first pts))))))
     contours () #f 0 0 0 0)))

; The pixels the bounds B hold, within LEFT TOP to RIGHT BOTTOM when CLIP:
; (X Y WIDTH HEIGHT), or () when there is none.
(def %frame
  (fn (_ b clip left top right bottom)
    ((fn (_ x0 y0 x1 y1)
       (if (if (int< x0 x1) (int< y0 y1) #f)
         (list x0 y0 (int- x1 x0) (int- y1 y0))
         ()))
     (if clip (%max left (%floor8 (first b))) (%floor8 (first b)))
     (if clip (%max top (%floor8 (first (rest b)))) (%floor8 (first (rest b))))
     (if clip (%min right (%ceil8 (first (rest (rest b))))) (%ceil8 (first (rest (rest b)))))
     (if clip (%min bottom (%ceil8 (first (rest (rest (rest b)))))) (%ceil8 (first (rest (rest (rest b)))))))))

; The mask of the outline packed at P, its points counted from the frame's
; corner: (X Y CANVAS).
(def %render
  (fn (_ p frame)
    (def w (first (rest (rest frame))))
    (def h (first (rest (rest (rest frame)))))
    (def acc (%words (int* (int+ w 1) h)))
    (def s (%words (List length %fields)))
    (def m (Canvas make w h))
    (%put! (%at s) (%field (lit acc)) (%at acc))
    (%put! (%at s) (%field (lit w1)) (int+ w 1))
    (%put! (%at s) (%field (lit xmax)) (int* w 256))
    (%put! (%at s) (%field (lit ymax)) (int* h 256))
    (%drawing (int* w h))
    (%k-walk (%at s) p 0)
    (%k-cover (%at acc) (%at (first (rest (rest m)))) 0 w h 0)
    (list (first frame) (first (rest frame)) m)))

; A contour's count and points at word POS of A, each point less DX DY.
; Answers the word after them.
(def %pack!
  (fn (_ a pos points dx dy)
    (%put! a pos (List length points))
    ((fn (self k more)
       (if (null? more)
         k
         (do (%put! a k (int- (first (first more)) dx))
             (%put! a (int+ k 1) (int- (rest (first more)) dy))
             (self (int+ k 2) (rest more)))))
     (int+ pos 1) points)))

; The mask of CONTOURS, clipped as %frame clips, or () when no pixel is
; held.
(def %mask
  (fn (_ contours clip left top right bottom)
    (def b (%bounds contours))
    (def frame (if (null? b) () (%frame b clip left top right bottom)))
    (if (null? frame)
      ()
      (do
        (def buf
          (%words (List fold (fn (_ n points) (int+ n (int+ 1 (int* 2 (List length points))))) 1 contours)))
        (List fold
          (fn (_ pos points)
            (if (null? points)
              pos
              (%pack! (%at buf) pos points (int* 256 (first frame)) (int* 256 (first (rest frame))))))
          0 contours)
        (%render (%at buf) frame)))))

; The mask M, from %mask, drawn on C in COLOUR.
(def %stamp!
  (fn (_ c m colour)
    (unless (null? m)
      ((fn (_ pic)
         (Canvas stamp! c (first m) (first (rest m)) pic 0 0 (first pic) (first (rest pic)) colour))
       (first (rest (rest m)))))
    c))

(def %fill!
  (fn (_ c contours colour)
    (%stamp! c (%mask contours #t 0 0 (first c) (first (rest c))) colour)))

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

; The segment P Q widened HALF each side, packed at word POS of A as a
; contour of four points, each less DX DY.  Answers the word after it, or
; POS when P is Q.
(def %quad!
  (fn (_ a pos p q half dx dy)
    (if (if (int= (first p) (first q)) (int= (rest p) (rest q)) #f)
      pos
      ((fn (_ d)
         ((fn (_ len)
            ((fn (_ nx ny px py qx qy)
               (do (%put! a pos 4)
                   (%put! a (int+ pos 1) (int+ px nx))
                   (%put! a (int+ pos 2) (int+ py ny))
                   (%put! a (int+ pos 3) (int+ qx nx))
                   (%put! a (int+ pos 4) (int+ qy ny))
                   (%put! a (int+ pos 5) (int- qx nx))
                   (%put! a (int+ pos 6) (int- qy ny))
                   (%put! a (int+ pos 7) (int- px nx))
                   (%put! a (int+ pos 8) (int- py ny))
                   (int+ pos 9)))
             (int/ (int* (int- 0 (rest d)) half) len)
             (int/ (int* (first d) half) len)
             (int- (first p) dx) (int- (rest p) dy)
             (int- (first q) dx) (int- (rest q) dy)))
          (%isqrt (int+ (int* (first d) (first d)) (int* (rest d) (rest d))))))
       (%scaled (int- (first q) (first p)) (int- (rest q) (rest p)))))))

; A disc of radius R about 0 0 as four cubics, wound as %quad! winds.
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

; The mask of a stroke WIDTH wide through POINTS on a canvas CW x CH: a
; quadrilateral a segment and a disc a point, packed as one outline.  The
; frame is the points' bounds and half the width more, and a pixel past
; that for the disc's rounding.
(def %stroke-mask
  (fn (_ points width closed cw ch)
    (def half (int/ width 2))
    (def disc (%disc half))
    (def dn (List length disc))
    (def b (%bounds (list points)))
    (def pad (int+ half 256))
    (def frame
      (%frame (list (int- (first b) pad) (int- (first (rest b)) pad)
                    (int+ (first (rest (rest b))) pad) (int+ (first (rest (rest (rest b)))) pad))
              #t 0 0 cw ch))
    (if (null? frame)
      ()
      (do
        (def nv (List length points))
        (def tmpl (%words (int* 2 dn)))
        (def buf (%words (int+ 1 (int* nv (int+ 9 (int+ 1 (int* 2 dn)))))))
        (def a (%at buf))
        (def dx (int* 256 (first frame)))
        (def dy (int* 256 (first (rest frame))))
        (List fold
          (fn (_ k p) (do (%put! (%at tmpl) k (first p)) (%put! (%at tmpl) (int+ k 1) (rest p)) (int+ k 2)))
          0 disc)
        (def quads
          (fn (self pos p more)
            (if (null? more)
              (if closed (%quad! a pos p (first points) half dx dy) pos)
              (self (%quad! a pos p (first more) half dx dy) (first more) (rest more)))))
        (List fold
          (fn (_ pos p)
            (do (%put! a pos dn)
                (%k-move (int+ a (int* (int+ pos 1) %word-size)) (%at tmpl) 0 dn
                  (int- (first p) dx) (int- (rest p) dy))
                (int+ pos (int+ 1 (int* 2 dn)))))
          (quads 0 (first points) (rest points))
          points)
        (%render a frame)))))

(def-class Shape ()
  (doc "Outlines filled and stroked on a canvas, their edges anti-aliased. A point is (X . Y), each in 1/256 of a pixel; a contour is a list of points, closed from its last to its first. An outline's coverage is gathered into a mask and the mask drawn by (Canvas stamp!). The loops that walk the edges and sum their areas into the mask are compiled once a process when the masks made have covered 65,536 pixels, and only after they agree with the pure-x loops."
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
      (if (null? points)
        c
        (%stamp! c (%stroke-mask points width closed (first c) (first (rest c))) colour)))

    (method cubic (self (param p0 LIST "The start, (X . Y)")
                        (param p1 LIST "The first control point")
                        (param p2 LIST "The second control point")
                        (param p3 LIST "The end"))
      (doc "The points of a cubic Bezier curve, from P0 to P3 as they are, with as many between as keep the lines through them within a quarter pixel of the curve."
        (returns LIST "Points, P0 first and P3 last")
        (example "(Shape cubic (pair 0 0) (pair 100 0) (pair 200 0) (pair 300 0))" "((0 . 0) (300 . 0))"))
      (pair p0 (%cubic p0 p1 p2 p3 0 ())))

    (method jit! (self)
      (doc "Build and adopt the compiled loops (JIT; ARM64 and x86-64 backends) now, if they write the check outline and rows exactly as the pure-x loops do. Idempotent. Answers #t when they are in use, #f when they are not: the pure-x loops carry on, writing the same masks."
        (returns BOOL "#t when the compiled loops are in use")
        (sample "(Shape jit!)" "#t"))
      (%jit-try!))))

(doc (provide x/gfx/shape Shape)
  "Outlines filled and stroked on a canvas with anti-aliased edges, points in 1/256 of a pixel: (Shape fill! c contours colour), stroke!, mask and cubic."
  (example "(Shape cubic (pair 0 0) (pair 100 0) (pair 200 0) (pair 300 0))" "((0 . 0) (300 . 0))"))
