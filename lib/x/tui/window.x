; tui/window.x -- a page seen through some rows: where it is scrolled to,
; and which link is selected.
;
; A window holds a title, a page (x/tui/page), the line on its first row
; and the selected link's number, or nil.  Moves take the rows the window
; is drawn on, so a scroll stops with the last line on the last row and a
; link selected is scrolled into view.  The next link, with none selected,
; is the first on or below the top row; the previous, the last above the
; bottom row.  A link whose text takes no place on the page (an empty one,
; or one whose only text is an image's) is passed over and never selected.

(module x/tui/window)
(import x/type/class)
(import x/type/vector)
(import x/tui/page)

(import x/core/doors int+ int< obj-make obj-ref obj-set!)
(def %wn-vector ((prim-ref (lit type) (lit of)) (Vector make 0 ())))

; A window is a vector: 0 title, 1 page, 2 top line, 3 selected link.
(def %wn-get (fn (_ w k) (obj-ref w (int+ k 1))))
(def %wn-put! (fn (_ w k x) (obj-set! w (int+ k 1) x)))
(def %wn-new
  (fn (_ title page)
    (def w (obj-make %wn-vector 5))
    (obj-set! w 0 4)
    (%wn-put! w 0 title) (%wn-put! w 1 page) (%wn-put! w 2 0) (%wn-put! w 3 ())
    w))
(def %wn-clamp
  (fn (_ w top rows)
    ((fn (_ most) (match ((int< top 0) 0) ((int< most top) (match ((int< most 0) 0) (#t most))) (#t top)))
     (int+ (Page count (%wn-get w 1)) (- 0 rows)))))
(def %wn-scroll! (fn (_ w n rows) (%wn-put! w 2 (%wn-clamp w (int+ (%wn-get w 2) n) rows))))
(def %wn-nth (fn (self k l) (match ((= k 0) (first l)) (#t (self (int+ k -1) (rest l))))))
(def %wn-drop (fn (self k l) (match ((= k 0) l) (#t (self (int+ k -1) (rest l))))))
; The places a link takes, and its first line: nil for a link with no
; place on the page.
(def %wn-spans (fn (_ link) (%wn-nth 2 link)))
(def %wn-place? (fn (_ link) (not (eq? (%wn-spans link) ()))))
(def %wn-first-line (fn (_ link) (first (first (%wn-spans link)))))
; Link K, or nil when LINKS has none.
(def %wn-link
  (fn (self links k)
    (match ((eq? links ()) ()) ((= k 0) (first links)) (#t (self (rest links) (int+ k -1))))))
; Link K selected, scrolled into view: K.  A link with no place, or no
; link K, selects none: nil.
(def %wn-show!
  (fn (_ w k rows)
    (def link (%wn-link (Page links (%wn-get w 1)) k))
    (match
      ((match ((eq? link ()) #t) (#t (not (%wn-place? link)))) (do (%wn-put! w 3 ()) ()))
      (#t (do (def l (%wn-first-line link))
              (%wn-put! w 3 k)
              (match ((int< l (%wn-get w 2)) (%wn-put! w 2 (%wn-clamp w l rows)))
                     ((int< (int+ (%wn-get w 2) (int+ rows -1)) l)
                       (%wn-put! w 2 (%wn-clamp w (int+ l (- 1 rows)) rows)))
                     (#t ()))
              k)))))
; The first link from K on with a place, its first line at least L, or nil.
(def %wn-from
  (fn (self links k l)
    (match ((eq? links ()) ())
           ((not (%wn-place? (first links))) (self (rest links) (int+ k 1) l))
           ((int< (%wn-first-line (first links)) l) (self (rest links) (int+ k 1) l))
           (#t k))))
; The last link from K before END with a place, its first line at most L,
; or nil.
(def %wn-upto
  (fn (self links k end l found)
    (match ((eq? links ()) found)
           ((= k end) found)
           ((not (%wn-place? (first links))) (self (rest links) (int+ k 1) end l found))
           ((int< l (%wn-first-line (first links))) found)
           (#t (self (rest links) (int+ k 1) end l k)))))

(def-class Window ()
  (doc "A page seen through some rows: its title, the line on the first row, and the selected link."
    (example "(Window top (Window make \"t\" (Page text \"a\\nb\\nc\" 9)))" "0")
    (see make) (see scroll) (see next-link))
  (static
    (method make (self (param title STRING "Title") (param page VECTOR "A page (x/tui/page)"))
      (doc "A window on PAGE, at its top, no link selected."
        (returns VECTOR "The window")
        (example "(Window title (Window make \"t\" (Page text \"a\" 9)))" "\"t\""))
      (%wn-new title page))
    (method title (self (param window VECTOR "A window"))
      (doc "WINDOW's title." (returns STRING "Title")
        (example "(Window title (Window make \"t\" (Page text \"a\" 9)))" "\"t\""))
      (%wn-get window 0))
    (method retitle (self (param window VECTOR "A window") (param title STRING "Title"))
      (doc "Give WINDOW the title TITLE." (returns ANY "nil")
        (example "(Window retitle (Window make \"t\" (Page text \"a\" 9)) \"u\")" ""))
      (%wn-put! window 0 title) ())
    (method page (self (param window VECTOR "A window"))
      (doc "WINDOW's page." (returns VECTOR "A page")
        (example "(Page count (Window page (Window make \"t\" (Page text \"a\" 9))))" "1"))
      (%wn-get window 1))
    (method show (self (param window VECTOR "A window") (param page VECTOR "A page")
                       (param rows INTEGER "Rows the window is drawn on"))
      (doc "Put PAGE in WINDOW, as when the same document is laid out again: the top kept as near as the page allows, the selection kept when PAGE has that link."
        (returns ANY "nil")
        (example "(Window show (Window make \"t\" (Page text \"a\" 9)) (Page text \"b\" 9) 5)" ""))
      (%wn-put! window 1 page)
      (%wn-put! window 2 (%wn-clamp window (%wn-get window 2) rows))
      (match ((match ((eq? (%wn-get window 3) ()) #f) (#t (int< (%wn-get window 3) (%length (Page links page))))) ())
             (#t (%wn-put! window 3 ())))
      ())
    (method top (self (param window VECTOR "A window"))
      (doc "The line on WINDOW's first row." (returns INTEGER "Line, from 0")
        (example "(Window top (Window make \"t\" (Page text \"a\" 9)))" "0"))
      (%wn-get window 2))
    (method scroll (self (param window VECTOR "A window") (param n INTEGER "Lines: down when positive, up when negative")
                         (param rows INTEGER "Rows the window is drawn on"))
      (doc "Scroll WINDOW N lines, stopping at the first line on the first row and the last on the last."
        (returns INTEGER "The new top line")
        (example "(do (def w (Window make \"t\" (Page text \"a\\nb\\nc\\nd\" 9))) (Window scroll w 9 2))" "2"))
      (%wn-scroll! window n rows)
      (%wn-get window 2))
    (method go (self (param window VECTOR "A window") (param line INTEGER "Line, from 0")
                     (param rows INTEGER "Rows the window is drawn on"))
      (doc "Scroll WINDOW to put LINE on its first row, as far as the page allows."
        (returns INTEGER "The new top line")
        (example "(do (def w (Window make \"t\" (Page text \"a\\nb\\nc\\nd\" 9))) (Window go w 3 2))" "2"))
      (%wn-put! window 2 (%wn-clamp window line rows))
      (%wn-get window 2))
    (method selected (self (param window VECTOR "A window"))
      (doc "The selected link's number, or nil." (returns ANY "A link number or nil")
        (example "(Window selected (Window make \"t\" (Page text \"a\" 9)))" ""))
      (%wn-get window 3))
    (method link (self (param window VECTOR "A window"))
      (doc "The selected link, (DESTINATION TITLE SPANS), or nil; a form field's DESTINATION is its (field ...) inline." (returns ANY "A link or nil")
        (example "(Window link (Window make \"t\" (Page text \"a\" 9)))" ""))
      (match ((eq? (%wn-get window 3) ()) ())
             (#t (%wn-nth (%wn-get window 3) (Page links (%wn-get window 1))))))
    (method select (self (param window VECTOR "A window") (param k ANY "A link number, or nil for none")
                         (param rows INTEGER "Rows the window is drawn on"))
      (doc "Select link K, scrolled into view; nil, a link that takes no place on the page, or no link K selects none."
        (returns ANY "K, or nil when none is selected")
        (example "(Window select (Window make \"t\" (Page text \"a\" 9)) () 5)" ""))
      (match ((eq? k ()) (do (%wn-put! window 3 ()) ())) (#t (%wn-show! window k rows))))
    (method next-link (self (param window VECTOR "A window") (param rows INTEGER "Rows the window is drawn on"))
      (doc "Select the link after the selected one, or with none selected the first on or below the top row, scrolled into view: its number, or nil when there is none (the selection kept). A link that takes no place on the page is passed over."
        (returns ANY "A link number or nil")
        (example "(Window next-link (Window make \"t\" (Page text \"a\" 9)) 5)" ""))
      ((fn (_ k) (match ((eq? k ()) ()) (#t (%wn-show! window k rows))))
       ((fn (_ links selected)
          (match ((eq? selected ()) (%wn-from links 0 (%wn-get window 2)))
                 (#t (%wn-from (%wn-drop (int+ selected 1) links) (int+ selected 1) 0))))
        (Page links (%wn-get window 1)) (%wn-get window 3))))
    (method prev-link (self (param window VECTOR "A window") (param rows INTEGER "Rows the window is drawn on"))
      (doc "Select the link before the selected one, or with none selected the last above the bottom row, scrolled into view: its number, or nil when there is none (the selection kept). A link that takes no place on the page is passed over."
        (returns ANY "A link number or nil")
        (example "(Window prev-link (Window make \"t\" (Page text \"a\" 9)) 5)" ""))
      ((fn (_ k) (match ((eq? k ()) ()) (#t (%wn-show! window k rows))))
       ((fn (_ links selected)
          (match ((eq? selected ())
                   (%wn-upto links 0 (%length links) (int+ (%wn-get window 2) (int+ rows -1)) ()))
                 (#t (%wn-upto links 0 selected (Page count (%wn-get window 1)) ()))))
        (Page links (%wn-get window 1)) (%wn-get window 3))))
    (method draw (self (param window VECTOR "A window") (param screen VECTOR "A screen (x/tui/screen)")
                       (param row INTEGER "The first row to draw on") (param rows INTEGER "Rows to draw"))
      (doc "Draw WINDOW's page on ROWS rows of SCREEN from ROW, from its top line, its selected link reversed."
        (returns ANY "nil")
        (example "(Window draw (Window make \"t\" (Page text \"a\" 9)) (Screen make 3 9) 1 2)" ""))
      (Page draw (%wn-get window 1) screen row rows (%wn-get window 2) (%wn-get window 3)))))

(provide x/tui/window Window)
