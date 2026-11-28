; tui/panes.x -- a main pane with a side pane on its left, its right, or both.
;
; Panes divide a screen's columns: a left side, the main pane, and a right
; side, each side shown or hidden and wanting a width.  A side takes the
; width it wants, but no more than a quarter of the columns past the two
; bars between the panes, so the main pane keeps at least half; a side left
; under 8 columns is not drawn.  A bar a column wide stands between a side
; and the main pane, bold beside a side that has the focus.  One pane has
; the focus: the main one, or a shown side.
;
; Each pane is drawn on a screen of its own, as wide as the pane, and that
; screen is copied onto the shown one at the pane's column (Screen paste),
; so whatever draws a pane draws on a whole screen and never sees the
; others.  A pane's screen is kept from one draw to the next and is new
; only when the pane's size changes.

(module x/tui/panes)
(import x/type/class)
(import x/type/vector)
(import x/tui/style)
(import x/tui/screen Screen screen-put! screen-paste!)

(import x/core/doors int+ int- int/ int< obj-make obj-ref obj-set!)
(def %pn-vector ((prim-ref (lit type) (lit of)) (Vector make 0 ())))
(def %pn-bold (Style make (lit (bold)) () ()))

; Panes are a vector: 0 and 1 whether the left side is shown and the width
; it wants, 2 and 3 the right side's, 4 the pane with the focus (left, main
; or right), 5, 6 and 7 the left, main and right panes' screens, or nil.
(def %pn-get (fn (_ pn k) (obj-ref pn (int+ k 1))))
(def %pn-put! (fn (_ pn k x) (obj-set! pn (int+ k 1) x)))
(def %pn-new
  (fn (_)
    (def pn (obj-make %pn-vector 9))
    (obj-set! pn 0 8)
    (%pn-put! pn 0 #f) (%pn-put! pn 1 28) (%pn-put! pn 2 #f) (%pn-put! pn 3 28)
    (%pn-put! pn 4 (lit main)) (%pn-put! pn 5 ()) (%pn-put! pn 6 ()) (%pn-put! pn 7 ())
    pn))
; A side's first slot: 0 for left, 2 for right.
(def %pn-side
  (fn (_ side)
    (match ((eq? side (lit left)) 0) ((eq? side (lit right)) 2)
           (#t (error "Panes: a side is left or right")))))
(def %pn-show!
  (fn (_ pn side on)
    (%pn-put! pn (%pn-side side) on)
    (match ((match (on #f) (#t (eq? (%pn-get pn 4) side))) (%pn-put! pn 4 (lit main))) (#t ()))
    on))
; The columns the side at slot K takes among COLS: 0 when it is not drawn.
(def %pn-fit
  (fn (_ w) (match ((int< w 8) 0) (#t w))))
(def %pn-width
  (fn (_ pn k cols)
    (match ((%pn-get pn k)
             (%pn-fit ((fn (_ most) (match ((int< most (%pn-get pn (int+ k 1))) most) (#t (%pn-get pn (int+ k 1)))))
                       (int/ (int- cols 2) 4))))
           (#t 0))))
(def %pn-columns
  (fn (_ pn cols)
    (def lw (%pn-width pn 0 cols))
    (def rw (%pn-width pn 2 cols))
    (def mc (match ((= lw 0) 0) (#t (int+ lw 1))))
    (def mw (int- (int- cols mc) (match ((= rw 0) 0) (#t (int+ rw 1)))))
    (%append (match ((= lw 0) ()) (#t (list (list (lit left) 0 lw))))
             (list (list (lit main) mc mw))
             (match ((= rw 0) ()) (#t (list (list (lit right) (int- cols rw) rw)))))))
; Whether PANE can take the focus: the main pane, or a shown side.
(def %pn-takes?
  (fn (_ pn pane) (match ((eq? pane (lit main)) #t) (#t (%pn-get pn (%pn-side pane))))))
; The first pane of ORDER that can take the focus.
(def %pn-first
  (fn (self pn order) (match ((%pn-takes? pn (first order)) (first order)) (#t (self pn (rest order))))))
; The pane C of a column list, drawn and copied, then its bar.
(def %pn-draw-pane!
  (fn (_ pn screen row rows draw c)
    (def pane (first c))
    (def col (first (rest c)))
    (def w (first (rest (rest c))))
    (def sub (%pn-screen pn pane rows w))
    (draw pane sub)
    (screen-paste! screen row col sub)
    (match ((eq? pane (lit left)) (%pn-bar! screen row rows w (eq? (%pn-get pn 4) pane)))
           ((eq? pane (lit right)) (%pn-bar! screen row rows (int+ col -1) (eq? (%pn-get pn 4) pane)))
           (#t ()))))
(def %pn-draw!
  (fn (self pn screen row rows draw cs)
    (match ((eq? cs ()) ())
           (#t (do (%pn-draw-pane! pn screen row rows draw (first cs))
                   (self pn screen row rows draw (rest cs)))))))
; The screen PANE is drawn on, ROWS by W: the one kept when it is that size.
(def %pn-slot (fn (_ pane) (match ((eq? pane (lit left)) 5) ((eq? pane (lit main)) 6) (#t 7))))
(def %pn-screen
  (fn (_ pn pane rows w)
    (def s (%pn-get pn (%pn-slot pane)))
    (match ((match ((eq? s ()) #f) ((= (Screen rows s) rows) (= (Screen cols s) w)) (#t #f)) s)
           (#t (do (%pn-put! pn (%pn-slot pane) (Screen make rows w)) (%pn-get pn (%pn-slot pane)))))))
; The bar at column COL on ROWS rows from ROW, bold when BOLD.
(def %pn-bar!
  (fn (_ screen row rows col bold)
    ((fn (go k)
       (match ((int< k rows) (do (screen-put! screen (int+ row k) col "│" (match (bold %pn-bold) (#t 0))) (go (int+ k 1))))
              (#t ())))
     0)))

(def-class Panes ()
  (doc "A main pane with side panes on its left and right, each shown or hidden: the columns each takes, which has the focus, and a draw that gives each its own screen."
    (example "(Panes columns (Panes make) 80)" "(('main 0 80))")
    (see columns) (see draw))
  (static
    (method make (self)
      (doc "Panes with both sides hidden, each wanting 28 columns when shown, and the focus on the main pane."
        (returns VECTOR "The panes")
        (example "(Panes focus (Panes make))" "'main"))
      (%pn-new))
    (method shown? (self (param panes VECTOR "Panes") (param side SYMBOL "left or right"))
      (doc "Whether SIDE is shown."
        (returns BOOL "Whether it is shown")
        (example "(Panes shown? (Panes make) 'left)" "#f"))
      (%pn-get panes (%pn-side side)))
    (method show! (self (param panes VECTOR "Panes") (param side SYMBOL "left or right")
                        (param on BOOL "Whether to show it"))
      (doc "Show SIDE, or hide it; hiding the side with the focus gives the focus to the main pane."
        (returns BOOL "ON")
        (example "(Panes show! (Panes make) 'right #t)" "#t"))
      (%pn-show! panes side on))
    (method toggle! (self (param panes VECTOR "Panes") (param side SYMBOL "left or right"))
      (doc "Show SIDE when it is hidden and hide it when it is shown."
        (returns BOOL "Whether it is shown now")
        (example "(Panes toggle! (Panes make) 'left)" "#t"))
      (%pn-show! panes side (match ((%pn-get panes (%pn-side side)) #f) (#t #t))))
    (method width! (self (param panes VECTOR "Panes") (param side SYMBOL "left or right")
                         (param cols INTEGER "Columns"))
      (doc "Make SIDE want COLS columns when it is shown."
        (returns INTEGER "COLS")
        (example "(Panes width! (Panes make) 'left 20)" "20"))
      (%pn-put! panes (int+ (%pn-side side) 1) cols)
      cols)
    (method focus (self (param panes VECTOR "Panes"))
      (doc "The pane with the focus."
        (returns SYMBOL "left, main or right")
        (example "(Panes focus (do (def p (Panes make)) (Panes show! p 'left #t) (Panes focus! p 'left) p))" "'left"))
      (%pn-get panes 4))
    (method focus! (self (param panes VECTOR "Panes") (param pane SYMBOL "left, main or right"))
      (doc "Give PANE the focus; a hidden side does not take it."
        (returns SYMBOL "The pane with the focus")
        (example "(Panes focus! (Panes make) 'right)" "'main"))
      (match ((%pn-takes? panes pane) (%pn-put! panes 4 pane)) (#t ()))
      (%pn-get panes 4))
    (method focus-next! (self (param panes VECTOR "Panes"))
      (doc "Give the focus to the next shown pane to the right, after the last the first."
        (returns SYMBOL "The pane with the focus")
        (example "(Panes focus-next! (do (def p (Panes make)) (Panes show! p 'right #t) p))" "'right"))
      (%pn-put! panes 4
        (%pn-first panes
          (match ((eq? (%pn-get panes 4) (lit left)) (lit (main right left)))
                 ((eq? (%pn-get panes 4) (lit main)) (lit (right left main)))
                 (#t (lit (left main right))))))
      (%pn-get panes 4))
    (method columns (self (param panes VECTOR "Panes") (param cols INTEGER "The screen's columns"))
      (doc "The panes drawn across COLS columns, left to right: each its name, its first column and its width. A shown side too narrow to draw is left out."
        (returns LIST "(PANE COL WIDTH) for each pane drawn")
        (example "(Panes columns (do (def p (Panes make)) (Panes show! p 'left #t) p) 80)" "(('left 0 19) ('main 20 60))"))
      (%pn-columns panes cols))
    (method draw (self (param panes VECTOR "Panes") (param screen VECTOR "A screen (x/tui/screen)")
                       (param row INTEGER "The first row to draw on") (param rows INTEGER "Rows to draw")
                       (param draw CALLABLE "Called with a pane's name and its screen, to draw the pane"))
      (doc "Draw the panes on ROWS rows of SCREEN from ROW: DRAW is called with each pane's name and a screen of ROWS rows as wide as the pane, holding what was drawn on it last time, and that screen is copied onto SCREEN at the pane's column; then the bars between the panes."
        (returns ANY "nil")
        (example "(Screen row-text (do (def s (Screen make 1 40)) (def p (Panes make)) (Panes show! p 'left #t) (Panes draw p s 0 1 (fn (_ pane sub) (Screen put sub 0 0 (match ((eq? pane 'left) \"L\") (#t \"M\")) 0))) s) 0)" "\"L        │M                             \""))
      (match ((int< 0 rows) (%pn-draw! panes screen row rows draw (%pn-columns panes (Screen cols screen))))
             (#t ()))
      ())))

(provide x/tui/panes Panes)
