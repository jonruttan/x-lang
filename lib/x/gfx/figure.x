; figure.x -- Figure: an outline of curves with a fill and a stroke, placed
; in a scene and changed over time.
;
; A figure is (POINTS FILL STROKE WIDTH DRAWN).  POINTS is a Matrix, a row
; a point: a closed chain of cubic Bezier curves, an end point, two control
; points and the next end point, the last end point the first again, so K
; curves are 3K + 1 rows.  A straight side is a curve with its control
; points on it.  FILL and STROKE are (R G B A), an alpha of 0 none.  WIDTH
; is the stroke's.  DRAWN is the share of the outline drawn, 0 to 1.
;
; Lengths are floats in scene units: the frame is 8 units high whatever the
; canvas, its centre is 0 0, x runs right and y up.
;
; Nothing changes a figure: each operation answers another.  An animation
; is a function of progress, 0 to 1, answering the figure to draw then.
;
; The arithmetic on points is Matrix's, a few runs a figure however many
; its points.  A figure is drawn by Shape, its points turned to 1/256 of a
; pixel first.
(module x/gfx/figure)

(import x/gfx/canvas)
(import x/gfx/shape)
(import x/num/float Float float-of f-add f-sub f-mul f-div f-lt fsin fcos)
(import x/num/tensor)
(import x/num/matrix)

(import x/core/doors int* int+ int- int/ int< int=)

(def %fail (fn (_ what) (Err raise (lit value) (Str8 append "Figure: " what) ())))

(def %zero (float-of 0))
(def %one (float-of 1))
(def %two (float-of 2))
(def %three (float-of 3))

; A circle's control points lie this share of its radius along the tangent.
(def %kappa (f-div (float-of 5522847) (float-of 10000000)))

(def %neg (fn (_ a) (f-sub %zero a)))

; --- A figure's parts ------------------------------------------------------

(def %points (fn (_ f) (first f)))
(def %fill (fn (_ f) (first (rest f))))
(def %stroke (fn (_ f) (first (rest (rest f)))))
(def %width (fn (_ f) (first (rest (rest (rest f))))))
(def %drawn (fn (_ f) (first (rest (rest (rest (rest f)))))))

(def %with-points (fn (_ f m) (pair m (rest f))))

(def %matrix (fn (_ rows) (Matrix from rows (lit f64))))

; X Y as a row that broadcasts over a figure's points.
(def %row (fn (_ x y) (Tensor from (list x y) (lit f64))))

(def %white (list 255 255 255 255))
(def %none (list 0 0 0 0))

; A new figure's style: no fill, a white stroke 1/25 of a unit wide, all of
; it drawn.
(def %new (fn (_ rows) (list (%matrix rows) %none %white (f-div %one (float-of 25)) %one)))

(def %colour
  (fn (_ c)
    (if (null? (rest (rest (rest c))))
      (list (first c) (first (rest c)) (first (rest (rest c))) 255)
      c)))

; --- Makers ----------------------------------------------------------------

; The rows of a closed chain of straight sides through CORNERS, each (X Y):
; a side's control points at its thirds.
(def %chain
  (fn (_ corners)
    (def third
      (fn (_ a b n)
        (list (f-add (first a) (f-div (f-mul (f-sub (first b) (first a)) n) %three))
              (f-add (first (rest a)) (f-div (f-mul (f-sub (first (rest b)) (first (rest a))) n) %three)))))
    ((fn (self a more)
       ((fn (_ b)
          (pair a
            (pair (third a b %one)
              (pair (third a b %two)
                (if (null? more) (list b) (self b (rest more)))))))
        (if (null? more) (first corners) (first more))))
     (first corners) (rest corners))))

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

; --- Placement -------------------------------------------------------------

(def %column (fn (_ m k) (m slice 1 k (int+ k 1))))

; (MINX MINY MAXX MAXY) of the points, control points among them.
(def %bounds
  (fn (_ m)
    (list ((%column m 0) least) ((%column m 1) least)
          ((%column m 0) greatest) ((%column m 1) greatest))))

; The middle of the bounds, as a row.
(def %centre
  (fn (_ b)
    (%row (f-div (f-add (first b) (first (rest (rest b)))) %two)
          (f-div (f-add (first (rest b)) (first (rest (rest (rest b))))) %two))))

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
    (def mid (fn (_ b k) (f-div (f-add (List ref k b) (List ref (int+ k 2) b)) %two)))
    (def level (f-sub (mid o 1) (mid f 1)))
    (def plumb (f-sub (mid o 0) (mid f 0)))
    (match
      ((eq? side (lit right)) (%shift fig (f-sub (f-add (List ref 2 o) gap) (List ref 0 f)) level))
      ((eq? side (lit left)) (%shift fig (f-sub (f-sub (List ref 0 o) gap) (List ref 2 f)) level))
      ((eq? side (lit up)) (%shift fig plumb (f-sub (f-add (List ref 3 o) gap) (List ref 1 f))))
      ((eq? side (lit down)) (%shift fig plumb (f-sub (f-sub (List ref 1 o) gap) (List ref 3 f))))
      (#t (%fail "next-to: SIDE is right, left, up or down")))))

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
    (pair (first rows)
      ((fn (self i p more)
         (if (int< i k)
           ((fn (_ c1 c2 p3)
              (List append
                (%cut p c1 c2 p3 (int- (int/ (int* n (int+ i 1)) k) (int/ (int* n i) k)))
                (self (int+ i 1) p3 (rest (rest (rest more))))))
            (first more) (first (rest more)) (first (rest (rest more))))
           ()))
       0 (first rows) (rest rows)))))

(def %curves (fn (_ m) (int/ (int- (first (m extent)) 1) 3)))

; M with N curves.
(def %of-curves
  (fn (_ m n)
    (if (int= (%curves m) n) m (%matrix (%recut (m ->list) (%curves m) n)))))

(def %morph
  (fn (_ a b)
    (def n (if (int< (%curves (%points a)) (%curves (%points b))) (%curves (%points b)) (%curves (%points a))))
    (def from (%of-curves (%points a) n))
    (def step ((%of-curves (%points b) n) sub from))
    (fn (_ t)
      ((fn (_ u)
         (list (from add (step mul u))
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
    (def all (int* 256 (%curves (%points fig))))
    (def share (Float ->int (f-mul (%drawn fig) (float-of all))))
    (def part (if (int< share all) share all))
    (def wide (Float ->int (f-mul (%width fig) unit)))
    (when (int< 0 part)
      ((fn (_ line)
         (do (when (int< 0 (first (rest (rest (rest (%fill fig))))))
               (Shape fill! c (list line) (%fill fig)))
             (when (if (int< 1 wide) (int< 0 (first (rest (rest (rest (%stroke fig)))))) #f)
               (Shape stroke! c line wide (%stroke fig) (int= part all)))))
       (pair (first pts) (%trace (first pts) (rest pts) (int/ part 256) (int- part (int* 256 (int/ part 256)))))))
    c))

(def-class Figure ()
  (doc "An outline of curves with a fill and a stroke, placed in a scene and changed over time. A figure is (POINTS FILL STROKE WIDTH DRAWN), POINTS a Matrix of the curves' points; lengths are floats in scene units, the frame 8 units high, 0 0 its centre, y up. Each operation answers another figure, and an animation is a function of progress, 0 to 1, answering the figure to draw then."
    (example "(Figure bounds (Figure circle 1))" "(-1.0 -1.0 1.0 1.0)")
    (see morph) (see draw!))
  (static
    (method circle (self (param radius NUMBER "The radius"))
      (doc "A circle about 0 0, four curves from its rightmost point round anticlockwise. Not filled; its stroke white, 1/25 of a unit wide."
        (returns LIST "A figure")
        (example "(Figure bounds (Figure circle 1))" "(-1.0 -1.0 1.0 1.0)"))
      (%new (%circle (float-of radius))))

    (method square (self (param side NUMBER "A side's length"))
      (doc "A square about 0 0, from its upper right corner round anticlockwise. Not filled; its stroke white, 1/25 of a unit wide."
        (returns LIST "A figure")
        (example "(Figure bounds (Figure square 2))" "(-1.0 -1.0 1.0 1.0)"))
      ((fn (_ h) (%new (%chain (list (list h h) (list (%neg h) h) (list (%neg h) (%neg h)) (list h (%neg h))))))
       (f-div (float-of side) %two)))

    (method triangle (self (param radius NUMBER "From the centre to a corner"))
      (doc "A triangle of equal sides about 0 0, one corner straight up. Not filled; its stroke white, 1/25 of a unit wide."
        (returns LIST "A figure")
        (example "(List ref 3 (Figure bounds (Figure triangle 2)))" "2.0"))
      (%new (%chain (%regular 3 (float-of radius)))))

    (method polygon (self (param corners LIST "Each (X Y), in order round the figure"))
      (doc "The closed figure of straight sides through CORNERS. Not filled; its stroke white, 1/25 of a unit wide."
        (returns LIST "A figure")
        (example "(Figure bounds (Figure polygon (list (list 0 0) (list 4 0) (list 0 3))))" "(0.0 0.0 4.0 3.0)"))
      (when (null? corners) (%fail "polygon: no corners"))
      (%new (%chain (List map (fn (_ p) (list (float-of (first p)) (float-of (first (rest p))))) corners))))

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

    (method fill (self (param fig LIST "A figure")
                       (param colour LIST "(R G B) or (R G B A); an alpha of 0 is no fill"))
      (doc "The figure filled with COLOUR."
        (returns LIST "A figure")
        (example "(do (import x/gfx/canvas) (Canvas pixel (Figure draw! (Canvas make 8 8) (Figure fill (Figure square 4) (list 9 8 7))) 4 4))" "(9 8 7 255)"))
      (list (%points fig) (%colour colour) (%stroke fig) (%width fig) (%drawn fig)))

    (method stroke (self (param fig LIST "A figure")
                         (param colour LIST "(R G B) or (R G B A); an alpha of 0 is no stroke")
                         (param width NUMBER "The line's width in units"))
      (doc "The figure with its outline drawn in COLOUR, WIDTH wide. A line under 2/256 of a pixel on the canvas is not drawn."
        (returns LIST "A figure")
        (example "(do (import x/gfx/canvas) (Canvas pixel (Figure draw! (Canvas make 8 8) (Figure stroke (Figure square 4) (list 9 8 7) 2)) 2 4))" "(9 8 7 255)"))
      (list (%points fig) (%fill fig) (%colour colour) (float-of width) (%drawn fig)))

    (method morph (self (param from LIST "The figure at progress 0")
                        (param to LIST "The figure at progress 1"))
      (doc "The animation from one figure to another: points, colours, width and the share drawn each go evenly from FROM's to TO's. The figure of fewer curves is first cut into as many as the other, its shape unchanged."
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
      (doc "The animation that draws the figure's outline from its first point round, the share drawn the progress. The part drawn is filled as it stands, closed by a straight line."
        (returns CALLABLE "(fn (_ progress) -> figure)")
        (example "(do (import x/gfx/canvas) (Canvas pixel (Figure draw! (Canvas make 8 8) ((Figure create (Figure fill (Figure square 4) (list 9 8 7))) 0)) 4 4))" "(0 0 0 0)"))
      (fn (_ t) (list (%points fig) (%fill fig) (%stroke fig) (%width fig) (float-of t))))

    (method fade-out (self (param fig LIST "A figure"))
      (doc "The animation that fades the figure: the alpha of its fill and of its stroke go evenly to 0."
        (returns CALLABLE "(fn (_ progress) -> figure)")
        (example "(List ref 3 (List ref 2 ((Figure fade-out (Figure circle 1)) 0.5)))" "128"))
      (fn (_ t)
        ((fn (_ u) (list (%points fig) (%fade (%fill fig) u) (%fade (%stroke fig) u) (%width fig) (%drawn fig)))
         (float-of t))))

    (method draw! (self (param c LIST "The canvas drawn on")
                        (param fig LIST "A figure"))
      (doc "Draw the figure on the canvas, the canvas's height 8 units and its middle 0 0: the fill, then the stroke over it. Only the share drawn is traced; a figure all drawn is closed."
        (returns LIST "The canvas")
        (example "(do (import x/gfx/canvas) (Canvas pixel (Figure draw! (Canvas make 8 8) (Figure fill (Figure square 4) (list 9 8 7))) 4 4))" "(9 8 7 255)"))
      (%draw! c fig))))

(doc (provide x/gfx/figure Figure)
  "Figures for a scene: outlines of curves with a fill and a stroke, made (circle, square, triangle, polygon), placed (shift, scale, rotate, next-to), animated (morph, turn, create, fade-out) and drawn on a canvas (draw!)."
  (example "(Figure bounds (Figure circle 1))" "(-1.0 -1.0 1.0 1.0)"))
