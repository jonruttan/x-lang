; figure.x -- Figure: paths of curves with a fill and a stroke, placed in a
; scene and changed over time.
;
; A figure is (POINTS PATHS FILL STROKE WIDTH DRAWN).  POINTS is a Matrix,
; a row a point, the paths' points one after another.  A path is a chain
; of cubic Bezier curves, an end point, two control points and the next end
; point, so K curves are 3K + 1 rows; a straight side is a curve with its
; control points on it.  PATHS says how the rows are shared out: each
; (ROWS . CLOSED), CLOSED #t for an outline, whose last point is its first
; again, and #f for a line.  FILL and STROKE are (R G B A), an alpha of 0
; none; only a closed path is filled.  WIDTH is the stroke's.  DRAWN is the
; share of the paths drawn, 0 to 1, the first path first.
;
; Lengths are floats in scene units: the frame is 8 units high whatever the
; canvas, its centre is 0 0, x runs right and y up.
;
; Nothing changes a figure: each operation answers another.  An animation
; is a function of progress, 0 to 1, answering the figure to draw then.
;
; The arithmetic on points is Matrix's, a few runs a figure however many
; its points or its paths.  A figure is drawn by Shape, its points turned
; to 1/256 of a pixel first: its closed paths filled together, then every
; path stroked together.
(module x/gfx/figure)

(import x/gfx/canvas)
(import x/gfx/shape)
(import x/gfx/font)
(import x/num/float Float float-of f-add f-sub f-mul f-div f-lt fsin fcos)
(import x/num/tensor)
(import x/num/matrix)

(import x/core/doors char->int int& int* int+ int- int/ int< int= str-byte-len str-byte-ref)

(def %fail (fn (_ what) (Err raise (lit value) (Str8 append "Figure: " what) ())))

(def %zero (float-of 0))
(def %one (float-of 1))
(def %two (float-of 2))
(def %three (float-of 3))

; A circle's control points lie this share of its radius along the tangent.
(def %kappa (f-div (float-of 5522847) (float-of 10000000)))

; An arrow's head: how far back its barbs start, and how far out.
(def %head-back (f-div (float-of 3) (float-of 10)))
(def %head-out (f-div (float-of 3) (float-of 20)))

(def %neg (fn (_ a) (f-sub %zero a)))

; --- A figure's parts ------------------------------------------------------

(def %points (fn (_ f) (first f)))
(def %paths (fn (_ f) (first (rest f))))
(def %fill (fn (_ f) (first (rest (rest f)))))
(def %stroke (fn (_ f) (first (rest (rest (rest f))))))
(def %width (fn (_ f) (first (rest (rest (rest (rest f)))))))
(def %drawn (fn (_ f) (first (rest (rest (rest (rest (rest f))))))))

(def %with-points (fn (_ f m) (pair m (rest f))))

(def %matrix (fn (_ rows) (Matrix from rows (lit f64))))

; X Y as a row that broadcasts over a figure's points.
(def %row (fn (_ x y) (Tensor from (list x y) (lit f64))))

(def %white (list 255 255 255 255))
(def %none (list 0 0 0 0))

(def %curves-of (fn (_ rows) (int/ (int- rows 1) 3)))

; A new figure's style: no fill, a white stroke 1/25 of a unit wide, all of
; it drawn.  PARTS is each path's (ROWS . CLOSED), ROWS here the rows
; themselves.
(def %new
  (fn (_ parts)
    (list (%matrix (List fold (fn (_ all p) (List append all (first p))) () parts))
          (List map (fn (_ p) (pair (List length (first p)) (rest p))) parts)
          %none %white (f-div %one (float-of 25)) %one)))

(def %colour
  (fn (_ c)
    (if (null? (rest (rest (rest c))))
      (list (first c) (first (rest c)) (first (rest (rest c))) 255)
      c)))

; --- Makers ----------------------------------------------------------------

; The rows of a chain of straight sides through CORNERS, each (X Y): a
; side's control points at its thirds.
(def %chain
  (fn (_ corners)
    (def third
      (fn (_ a b n)
        (list (f-add (first a) (f-div (f-mul (f-sub (first b) (first a)) n) %three))
              (f-add (first (rest a)) (f-div (f-mul (f-sub (first (rest b)) (first (rest a))) n) %three)))))
    (pair (first corners)
      ((fn (self a more)
         (if (null? more)
           ()
           ((fn (_ b) (pair (third a b %one) (pair (third a b %two) (pair b (self b (rest more))))))
            (first more))))
       (first corners) (rest corners)))))

; The same, back to its first corner.
(def %ring (fn (_ corners) (%chain (List append corners (list (first corners))))))

(def %circle
  (fn (_ r)
    (def k (f-mul r %kappa))
    (def n (%neg r))
    (def j (%neg k))
    (list (list r %zero) (list r k) (list k r)
          (list %zero r) (list j r) (list n k)
          (list n %zero) (list n j) (list j n)
          (list %zero n) (list k n) (list r j)
          (list r %zero))))

; N corners R from the centre, the first straight up, the rest
; anticlockwise.
(def %regular
  (fn (_ n r)
    (def step (f-div (f-mul %two (Float pi)) (float-of n)))
    (def start (f-div (Float pi) %two))
    ((fn (self i)
       (if (int< i n)
         ((fn (_ a) (pair (list (f-mul r (fcos a)) (f-mul r (fsin a))) (self (int+ i 1))))
          (f-add start (f-mul step (float-of i))))
         ()))
     0)))

; The shaft from A to B and a head at B: two barbs, each %head-back along
; the shaft and %head-out to a side.
(def %arrow
  (fn (_ a b)
    (def dx (f-sub (first b) (first a)))
    (def dy (f-sub (first (rest b)) (first (rest a))))
    (def len (Float sqrt (f-add (f-mul dx dx) (f-mul dy dy))))
    (when (if (f-lt %zero len) #f #t) (%fail "arrow: its ends are one point"))
    ((fn (_ ux uy)
       ((fn (_ bx by)
          (%new (list (pair (%chain (list a b)) #f)
                      (pair (%chain (list (list (f-sub bx (f-mul uy %head-out)) (f-add by (f-mul ux %head-out)))
                                          b
                                          (list (f-add bx (f-mul uy %head-out)) (f-sub by (f-mul ux %head-out)))))
                            #f))))
        (f-sub (first b) (f-mul ux %head-back))
        (f-sub (first (rest b)) (f-mul uy %head-back))))
     (f-div dx len) (f-div dy len))))

; --- Placement -------------------------------------------------------------

(def %column (fn (_ m k) (m slice 1 k (int+ k 1))))

; (MINX MINY MAXX MAXY) of the points, control points among them.
(def %bounds
  (fn (_ m)
    (list ((%column m 0) least) ((%column m 1) least)
          ((%column m 0) greatest) ((%column m 1) greatest))))

(def %mid (fn (_ b k) (f-div (f-add (List ref k b) (List ref (int+ k 2) b)) %two)))

; The middle of the bounds, as a row.
(def %centre (fn (_ b) (%row (%mid b 0) (%mid b 1))))

; F of the points taken from the figure's centre, put back about it.
(def %about
  (fn (_ fig f)
    ((fn (_ c) (%with-points fig ((f ((%points fig) sub c)) add c)))
     (%centre (%bounds (%points fig))))))

(def %shift
  (fn (_ fig dx dy)
    (%with-points fig ((%points fig) add (%row dx dy)))))

(def %rotate
  (fn (_ fig angle)
    (def c (fcos angle))
    (def s (fsin angle))
    (def turn (%matrix (list (list c s) (list (%neg s) c))))
    (%about fig (fn (_ m) (m product turn)))))

(def %next-to
  (fn (_ fig other side gap)
    (def f (%bounds (%points fig)))
    (def o (%bounds (%points other)))
    (def level (f-sub (%mid o 1) (%mid f 1)))
    (def plumb (f-sub (%mid o 0) (%mid f 0)))
    (match
      ((eq? side (lit right)) (%shift fig (f-sub (f-add (List ref 2 o) gap) (List ref 0 f)) level))
      ((eq? side (lit left)) (%shift fig (f-sub (f-sub (List ref 0 o) gap) (List ref 2 f)) level))
      ((eq? side (lit up)) (%shift fig plumb (f-sub (f-add (List ref 3 o) gap) (List ref 1 f))))
      ((eq? side (lit down)) (%shift fig plumb (f-sub (f-sub (List ref 1 o) gap) (List ref 3 f))))
      (#t (%fail "next-to: SIDE is right, left, up or down")))))

(def %onto
  (fn (_ fig other)
    (def f (%bounds (%points fig)))
    (def o (%bounds (%points other)))
    (%shift fig (f-sub (%mid o 0) (%mid f 0)) (f-sub (%mid o 1) (%mid f 1)))))

; --- Animations ------------------------------------------------------------

; A to B by T.
(def %mix (fn (_ a b t) (f-add a (f-mul (f-sub b a) t))))

(def %mix-int
  (fn (_ a b t) (Float ->int (Float round (%mix (float-of a) (float-of b) t)))))

(def %mix-colour (fn (_ a b t) (List map (fn (_ x y) (%mix-int x y t)) a b)))

(def %mix-row (fn (_ a b t) (List map (fn (_ x y) (%mix x y t)) a b)))

; The curve P0 C1 C2 P3 cut in M pieces of equal share: the rows after P0.
(def %cut
  (fn (self p0 c1 c2 p3 m)
    (if (int< m 2)
      (list c1 c2 p3)
      ((fn (_ t)
         ((fn (_ a b c)
            ((fn (_ ab bc)
               ((fn (_ mid)
                  (pair a (pair ab (pair mid (self mid bc c p3 (int- m 1))))))
                (%mix-row ab bc t)))
             (%mix-row a b t) (%mix-row b c t)))
          (%mix-row p0 c1 t) (%mix-row c1 c2 t) (%mix-row c2 p3 t)))
       (f-div %one (float-of m))))))

; ROWS, a chain of K curves, as one of N: curve I is cut in as many pieces
; as N shares out to it, so the extra cuts fall evenly along the chain.
(def %recut
  (fn (_ rows k n)
    (if (int= k n)
      rows
      (pair (first rows)
        ((fn (self i p more)
           (if (int< i k)
             ((fn (_ c1 c2 p3)
                (List append
                  (%cut p c1 c2 p3 (int- (int/ (int* n (int+ i 1)) k) (int/ (int* n i) k)))
                  (self (int+ i 1) p3 (rest (rest (rest more))))))
              (first more) (first (rest more)) (first (rest (rest more))))
             ()))
         0 (first rows) (rest rows))))))

; The first N of L, and the rest: (FIRST-N . REST).
(def %split
  (fn (self n l)
    (if (int< 0 n)
      ((fn (_ r) (pair (pair (first l) (first r)) (rest r))) (self (int- n 1) (rest l)))
      (pair () l))))

; A figure's paths, each (ROWS . CLOSED), ROWS the path's rows as lists.
(def %parts
  (fn (_ fig)
    ((fn (self paths rows)
       (if (null? paths)
         ()
         ((fn (_ s) (pair (pair (first s) (rest (first paths))) (self (rest paths) (rest s))))
          (%split (first (first paths)) rows))))
     (%paths fig) ((%points fig) ->list))))

; N rows, every one the point AT.
(def %dot (fn (self n at) (if (int< 0 n) (pair at (self (int- n 1) at)) ())))

; Two figures' paths made alike, pair by pair in order: each pair cut to
; the more curves of the two, and a path with no partner given one, its
; rows all at the middle of the other figure's bounds, so that it grows
; from there or shrinks to it.  Answers ((ROWS-A ROWS-B CLOSED-A CLOSED-B)
; ...).
(def %paired
  (fn (_ a b)
    (def at (fn (_ fig) ((fn (_ bd) (list (%mid bd 0) (%mid bd 1))) (%bounds (%points fig)))))
    (def mid-a (at a))
    (def mid-b (at b))
    ((fn (self pa pb)
       (match
         ((if (null? pa) (null? pb) #f) ())
         ((null? pa)
           (pair (list (%dot (List length (first (first pb))) mid-a) (first (first pb)) (rest (first pb)) (rest (first pb)))
                 (self pa (rest pb))))
         ((null? pb)
           (pair (list (first (first pa)) (%dot (List length (first (first pa))) mid-b) (rest (first pa)) (rest (first pa)))
                 (self (rest pa) pb)))
         (#t
           ((fn (_ ka kb)
              ((fn (_ n)
                 (pair (list (%recut (first (first pa)) ka n) (%recut (first (first pb)) kb n)
                             (rest (first pa)) (rest (first pb)))
                       (self (rest pa) (rest pb))))
               (if (int< ka kb) kb ka)))
            (%curves-of (List length (first (first pa)))) (%curves-of (List length (first (first pb))))))))
     (%parts a) (%parts b))))

; A path is closed on the way while either figure's is, and as TO's at the
; end: a fill fades by its alpha, so an outline opening keeps its fill
; until it has gone.
(def %morph
  (fn (_ a b)
    (def pairs (%paired a b))
    (def rows-of (fn (_ pick) (%matrix (List fold (fn (_ all p) (List append all (pick p))) () pairs))))
    (def from (rows-of first))
    (def step ((rows-of (fn (_ p) (first (rest p)))) sub from))
    (def counts (List map (fn (_ p) (List length (first p))) pairs))
    (def either
      (List map (fn (_ p n) (pair n (if (first (rest (rest p))) #t (first (rest (rest (rest p))))))) pairs counts))
    (def at-end (List map (fn (_ p n) (pair n (first (rest (rest (rest p)))))) pairs counts))
    (fn (_ t)
      ((fn (_ u)
         (list (from add (step mul u))
               (if (f-lt u %one) either at-end)
               (%mix-colour (%fill a) (%fill b) u)
               (%mix-colour (%stroke a) (%stroke b) u)
               (%mix (%width a) (%width b) u)
               (%mix (%drawn a) (%drawn b) u)))
       (float-of t)))))

(def %fade
  (fn (_ c t)
    (list (first c) (first (rest c)) (first (rest (rest c)))
          (%mix-int (first (rest (rest (rest c)))) 0 t))))

; --- Drawing ---------------------------------------------------------------

(def %join (fn (self a b) (if (null? a) b (pair (first a) (self (rest a) b)))))

; A to B by F / 256, in whole numbers.
(def %step
  (fn (_ a b f)
    (pair (int+ (first a) (int/ (int* (int- (first b) (first a)) f) 256))
          (int+ (rest a) (int/ (int* (int- (rest b) (rest a)) f) 256)))))

; The points of the chain after P: WHOLE curves entire, then F / 256 of
; the next.  MORE is the rows after P.
(def %trace
  (fn (self p more whole f)
    (if (null? more)
      ()
      ((fn (_ c1 c2 p3)
         (match
           ((int< 0 whole)
             (%join (rest (Shape cubic p c1 c2 p3))
                    (self p3 (rest (rest (rest more))) (int- whole 1) f)))
           ((int< 0 f)
             ((fn (_ a b c)
                ((fn (_ ab bc) (rest (Shape cubic p a ab (%step ab bc f))))
                 (%step a b f) (%step b c f)))
              (%step p c1 f) (%step c1 c2 f) (%step c2 p3 f)))
           (#t ())))
       (first more) (first (rest more)) (first (rest (rest more)))))))

; Whether every point of LINE is its first: such a path draws nothing.
(def %still?
  (fn (_ line)
    ((fn (self p more)
       (match ((null? more) #t)
              ((if (int= (first p) (first (first more))) (int= (rest p) (rest (first more))) #f) (self p (rest more)))
              (#t #f)))
     (first line) (rest line))))

; The paths' lines to draw with LEFT of the drawing left, in 1/256 of a
; curve: each (CLOSED WHOLE . POINTS), CLOSED the path's own, WHOLE #t when
; all of it is drawn.  PTS is the points of every path, in order.
(def %lines
  (fn (self paths pts left)
    (if (if (null? paths) #t (int< left 1))
      ()
      ((fn (_ s all)
         ((fn (_ part)
            ((fn (_ line more)
               (if (%still? line) more (pair (pair (rest (first paths)) (pair (int= part all) line)) more)))
             (pair (first (first s))
                   (%trace (first (first s)) (rest (first s)) (int/ part 256) (int- part (int* 256 (int/ part 256)))))
             (self (rest paths) (rest s) (int- left part))))
          (if (int< left all) left all)))
       (%split (first (first paths)) pts)
       (int* 256 (%curves-of (first (first paths))))))))

(def %draw!
  (fn (_ c fig)
    (def w (first c))
    (def h (first (rest c)))
    (def unit (float-of (int* 32 h)))
    (def placed
      (((%points fig) mul (%row unit (%neg unit)))
        add (%row (float-of (int* 128 w)) (float-of (int* 128 h)))))
    (def pts
      (List map (fn (_ r) (pair (Float ->int (first r)) (Float ->int (first (rest r))))) (placed ->list)))
    (def all
      (List fold (fn (_ n p) (int+ n (int* 256 (%curves-of (first p))))) 0 (%paths fig)))
    (def share (Float ->int (f-mul (%drawn fig) (float-of all))))
    (def lines (%lines (%paths fig) pts (if (int< share all) share all)))
    (def wide (Float ->int (f-mul (%width fig) unit)))
    (def outlines
      (List fold (fn (_ out l) (if (first l) (pair (rest (rest l)) out) out)) () lines))
    (when (if (null? outlines) #f (int< 0 (first (rest (rest (rest (%fill fig)))))))
      (Shape fill! c outlines (%fill fig)))
    (when (if (null? lines) #f (if (int< 1 wide) (int< 0 (first (rest (rest (rest (%stroke fig)))))) #f))
      (Shape strokes! c
        (List map (fn (_ l) (pair (if (first l) (first (rest l)) #f) (rest (rest l)))) lines)
        wide (%stroke fig)))
    c))

; --- Labels ----------------------------------------------------------------

(def %twenty-four (float-of 24))

; TEXT as a figure, a capital HEIGHT high: each stroke of each glyph a
; line, a dot a line half a grid unit long.  The text's box, as wide as
; its glyphs and a capital high, is about 0 0.  Places are worked in
; quarters of a grid unit, whole numbers, 24 a character.
(def %label
  (fn (_ text height)
    (def n (str-byte-len text))
    (def quarter (f-div height %twenty-four))
    (def left (int- 0 (int* 2 (int- (int* 6 n) 2))))
    (def at (fn (_ x y) (list (f-mul quarter (float-of x)) (f-mul quarter (float-of y)))))
    (def line
      (fn (_ base stroke)
        (if (null? (rest stroke))
          ((fn (_ x y) (pair (%chain (list (at (int- x 1) y) (at (int+ x 1) y))) #f))
           (int+ base (int* 4 (first (first stroke))))
           (int* 4 (int- (rest (first stroke)) 3)))
          (pair (%chain (List map (fn (_ p) (at (int+ base (int* 4 (first p))) (int* 4 (int- (rest p) 3)))) stroke))
                #f))))
    (def parts
      ((fn (self i)
         (if (int< i n)
           (List append
             (List map (fn (_ s) (line (int+ left (int* 24 i)) s))
               (Font glyph (int& (char->int (str-byte-ref text i)) 255)))
             (self (int+ i 1)))
           ()))
       0))
    (when (null? parts) (%fail "label: nothing to draw"))
    ((fn (_ f) (list (%points f) (%paths f) (%fill f) (%stroke f) (f-div height (float-of 10)) (%drawn f)))
     (%new parts))))

(def-class Figure ()
  (doc "Paths of curves with a fill and a stroke, placed in a scene and changed over time. A figure is (POINTS PATHS FILL STROKE WIDTH DRAWN): POINTS a Matrix of the paths' points and PATHS each path's (ROWS . CLOSED), #t for an outline and #f for a line. Lengths are floats in scene units, the frame 8 units high, 0 0 its centre, y up. Each operation answers another figure, and an animation is a function of progress, 0 to 1, answering the figure to draw then."
    (example "(Figure bounds (Figure circle 1))" "(-1.0 -1.0 1.0 1.0)")
    (see morph) (see draw!))
  (static
    (method circle (self (param radius NUMBER "The radius"))
      (doc "A circle about 0 0, four curves from its rightmost point round anticlockwise. Not filled; its stroke white, 1/25 of a unit wide."
        (returns LIST "A figure")
        (example "(Figure bounds (Figure circle 1))" "(-1.0 -1.0 1.0 1.0)"))
      (%new (list (pair (%circle (float-of radius)) #t))))

    (method square (self (param side NUMBER "A side's length"))
      (doc "A square about 0 0, from its upper right corner round anticlockwise. Not filled; its stroke white, 1/25 of a unit wide."
        (returns LIST "A figure")
        (example "(Figure bounds (Figure square 2))" "(-1.0 -1.0 1.0 1.0)"))
      ((fn (_ h)
         (%new (list (pair (%ring (list (list h h) (list (%neg h) h) (list (%neg h) (%neg h)) (list h (%neg h)))) #t))))
       (f-div (float-of side) %two)))

    (method triangle (self (param radius NUMBER "From the centre to a corner"))
      (doc "A triangle of equal sides about 0 0, one corner straight up. Not filled; its stroke white, 1/25 of a unit wide."
        (returns LIST "A figure")
        (example "(List ref 3 (Figure bounds (Figure triangle 2)))" "2.0"))
      (%new (list (pair (%ring (%regular 3 (float-of radius))) #t))))

    (method polygon (self (param corners LIST "Each (X Y), in order round the figure"))
      (doc "The closed figure of straight sides through CORNERS. Not filled; its stroke white, 1/25 of a unit wide."
        (returns LIST "A figure")
        (example "(Figure bounds (Figure polygon (list (list 0 0) (list 4 0) (list 0 3))))" "(0.0 0.0 4.0 3.0)"))
      (when (null? corners) (%fail "polygon: no corners"))
      (%new (list (pair (%ring (List map (fn (_ p) (list (float-of (first p)) (float-of (first (rest p))))) corners)) #t))))

    (method line (self (param x0 NUMBER "The start's x") (param y0 NUMBER "The start's y")
                       (param x1 NUMBER "The end's x") (param y1 NUMBER "The end's y"))
      (doc "The straight line from X0 Y0 to X1 Y1: one path, not closed. Its stroke white, 1/25 of a unit wide."
        (returns LIST "A figure")
        (example "(Figure bounds (Figure line -1 0 2 3))" "(-1.0 0.0 2.0 3.0)"))
      (%new (list (pair (%chain (list (list (float-of x0) (float-of y0)) (list (float-of x1) (float-of y1)))) #f))))

    (method arrow (self (param x0 NUMBER "The tail's x") (param y0 NUMBER "The tail's y")
                        (param x1 NUMBER "The tip's x") (param y1 NUMBER "The tip's y"))
      (doc "An arrow from X0 Y0 to X1 Y1: the shaft, and a head of two barbs at the tip, each 3/10 of a unit back along the shaft and 3/20 out. Two paths, neither closed. Raises a label 'value when the tail is the tip."
        (returns LIST "A figure")
        (example "(Figure bounds (Figure arrow 0 0 2 0))" "(0.0 -0.15 2.0 0.15)"))
      (%arrow (list (float-of x0) (float-of y0)) (list (float-of x1) (float-of y1))))

    (method label (self (param text STRING "The text, printable ASCII")
                        (param height NUMBER "A capital's height in units"))
      (doc "TEXT as a figure of lines, a capital HEIGHT high, drawn with x/gfx/font's strokes: one line a stroke, none closed. Its box, as wide as its characters and a capital high, is about 0 0; a character is HEIGHT across with its space. Its stroke is white, a tenth of HEIGHT wide. A character outside printable ASCII is left as a space. Raises a label 'value when no character has a stroke."
        (returns LIST "A figure")
        (example "(Figure bounds (Figure label \"L\" 6))" "(-2.0 -3.0 2.0 3.0)")
        (example "(List ref 1 (Figure label \"Hi\" 1))" "((4 . #f) (4 . #f) (4 . #f) (4 . #f) (4 . #f))"))
      (%label text (float-of height)))

    (method bounds (self (param fig LIST "A figure"))
      (doc "The least and greatest x and y among the figure's points, its curves' control points with them."
        (returns LIST "(MINX MINY MAXX MAXY)")
        (example "(Figure bounds (Figure square 2))" "(-1.0 -1.0 1.0 1.0)"))
      (%bounds (%points fig)))

    (method shift (self (param fig LIST "A figure")
                        (param dx NUMBER "Units right")
                        (param dy NUMBER "Units up"))
      (doc "The figure moved."
        (returns LIST "A figure")
        (example "(Figure bounds (Figure shift (Figure square 2) 3 0))" "(2.0 -1.0 4.0 1.0)"))
      (%shift fig (float-of dx) (float-of dy)))

    (method scale (self (param fig LIST "A figure")
                        (param by NUMBER "The factor"))
      (doc "The figure made BY times as large about the middle of its bounds. Its stroke keeps its width."
        (returns LIST "A figure")
        (example "(Figure bounds (Figure scale (Figure square 2) 2))" "(-2.0 -2.0 2.0 2.0)"))
      ((fn (_ k) (%about fig (fn (_ m) (m mul k)))) (float-of by)))

    (method rotate (self (param fig LIST "A figure")
                         (param angle NUMBER "Radians, anticlockwise"))
      (doc "The figure turned about the middle of its bounds."
        (returns LIST "A figure")
        (sample "(Figure bounds (Figure rotate (Figure square 2) (Float pi)))" "(-1.0 -1.0 1.0 1.0), to rounding"))
      (%rotate fig (float-of angle)))

    (method next-to (self (param fig LIST "The figure placed")
                          (param other LIST "The figure it is placed beside")
                          (param side SYMBOL "right, left, up or down")
                          (param gap NUMBER "Units between their bounds"))
      (doc "The figure moved to SIDE of OTHER, GAP between their bounds and their middles in line. Raises a label 'value for another SIDE."
        (returns LIST "A figure")
        (example "(Figure bounds (Figure next-to (Figure square 2) (Figure circle 1) 'right 0.5))" "(1.5 -1.0 3.5 1.0)"))
      (%next-to fig other side (float-of gap)))

    (method onto (self (param fig LIST "The figure placed")
                       (param other LIST "The figure it is placed on"))
      (doc "The figure moved so that the middle of its bounds is the middle of OTHER's."
        (returns LIST "A figure")
        (example "(Figure bounds (Figure onto (Figure square 2) (Figure shift (Figure circle 3) 5 1)))" "(4.0 0.0 6.0 2.0)"))
      (%onto fig other))

    (method fill (self (param fig LIST "A figure")
                       (param colour LIST "(R G B) or (R G B A); an alpha of 0 is no fill"))
      (doc "The figure with its closed paths filled with COLOUR."
        (returns LIST "A figure")
        (example "(do (import x/gfx/canvas) (Canvas pixel (Figure draw! (Canvas make 8 8) (Figure fill (Figure square 4) (list 9 8 7))) 4 4))" "(9 8 7 255)"))
      (list (%points fig) (%paths fig) (%colour colour) (%stroke fig) (%width fig) (%drawn fig)))

    (method stroke (self (param fig LIST "A figure")
                         (param colour LIST "(R G B) or (R G B A); an alpha of 0 is no stroke")
                         (param width NUMBER "The line's width in units"))
      (doc "The figure with its paths drawn in COLOUR, WIDTH wide. A line under 2/256 of a pixel on the canvas is not drawn."
        (returns LIST "A figure")
        (example "(do (import x/gfx/canvas) (Canvas pixel (Figure draw! (Canvas make 8 8) (Figure stroke (Figure square 4) (list 9 8 7) 2)) 2 4))" "(9 8 7 255)"))
      (list (%points fig) (%paths fig) (%fill fig) (%colour colour) (float-of width) (%drawn fig)))

    (method morph (self (param from LIST "The figure at progress 0")
                        (param to LIST "The figure at progress 1"))
      (doc "The animation from one figure to another: points, colours, width and the share drawn each go evenly from FROM's to TO's. Paths are taken pair by pair in order; of a pair, the one of fewer curves is first cut into as many as the other, its shape unchanged, and a path with no partner grows from, or shrinks to, the middle of the other figure. A path is closed on the way while either of its pair is, and as TO's at the end."
        (returns CALLABLE "(fn (_ progress) -> figure)")
        (example "(Figure bounds ((Figure morph (Figure square 2) (Figure square 4)) 0.5))" "(-1.5 -1.5 1.5 1.5)"))
      (%morph from to))

    (method turn (self (param fig LIST "A figure")
                       (param angle NUMBER "Radians, anticlockwise, turned by progress 1"))
      (doc "The animation that turns the figure about the middle of its bounds, by ANGLE times the progress. Unlike a morph to the turned figure, every point keeps its distance from the middle on the way."
        (returns CALLABLE "(fn (_ progress) -> figure)")
        (sample "((Figure turn (Figure square 2) (Float pi)) 0.5)" "the square a quarter turn round"))
      ((fn (_ a) (fn (_ t) (%rotate fig (f-mul a (float-of t))))) (float-of angle)))

    (method create (self (param fig LIST "A figure"))
      (doc "The animation that draws the figure's paths from the first path's first point on, the share drawn the progress. The part of a closed path drawn is filled as it stands, closed by a straight line."
        (returns CALLABLE "(fn (_ progress) -> figure)")
        (example "(do (import x/gfx/canvas) (Canvas pixel (Figure draw! (Canvas make 8 8) ((Figure create (Figure fill (Figure square 4) (list 9 8 7))) 0)) 4 4))" "(0 0 0 0)"))
      (fn (_ t) (list (%points fig) (%paths fig) (%fill fig) (%stroke fig) (%width fig) (float-of t))))

    (method fade-out (self (param fig LIST "A figure"))
      (doc "The animation that fades the figure: the alpha of its fill and of its stroke go evenly to 0."
        (returns CALLABLE "(fn (_ progress) -> figure)")
        (example "(List ref 3 (List ref 3 ((Figure fade-out (Figure circle 1)) 0.5)))" "128"))
      (fn (_ t)
        ((fn (_ u)
           (list (%points fig) (%paths fig) (%fade (%fill fig) u) (%fade (%stroke fig) u) (%width fig) (%drawn fig)))
         (float-of t))))

    (method draw! (self (param c LIST "The canvas drawn on")
                        (param fig LIST "A figure"))
      (doc "Draw the figure on the canvas, the canvas's height 8 units and its middle 0 0: its closed paths filled together, then every path stroked together over them. Only the share drawn is traced; a closed path all drawn is closed, and a path whose points are one point draws nothing."
        (returns LIST "The canvas")
        (example "(do (import x/gfx/canvas) (Canvas pixel (Figure draw! (Canvas make 8 8) (Figure fill (Figure square 4) (list 9 8 7))) 4 4))" "(9 8 7 255)"))
      (%draw! c fig))))

(doc (provide x/gfx/figure Figure)
  "Figures for a scene: paths of curves with a fill and a stroke, made (circle, square, triangle, polygon, line, arrow, label), placed (shift, scale, rotate, next-to, onto), animated (morph, turn, create, fade-out) and drawn on a canvas (draw!)."
  (example "(Figure bounds (Figure circle 1))" "(-1.0 -1.0 1.0 1.0)"))
