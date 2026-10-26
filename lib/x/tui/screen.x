; tui/screen.x -- a grid of styled cells, and the escapes that show it.
;
; A screen is ROWS x COLS cells, each a character and a style (x/tui/style).
; Text is put at a row and column and clipped at the right edge; a wide
; character takes two cells, and one that would not fit at the edge leaves
; a blank.  (Screen render) answers the escape sequences that bring the
; terminal from what it showed after the last render to what the screen
; holds now: for each row written since, the cells from the first that
; differs to the last.  The first render, and the first after a resize or
; (Screen repaint), clears the terminal and draws every row.
;
; The cells are a buffer of 8-byte slots, the character's code point and
; the style as 32-bit words; code point 0 is the second cell of a wide
; character.  A second buffer holds what the terminal shows, a byte a row
; whether the row has been written since the last render, and a third
; buffer, big enough for the longest render, takes the render's bytes.  A
; character of no width (a combining mark, a control) takes no cell and is
; dropped.  Work per cell walks offsets in the buffers and allocates
; nothing; screen-put! and screen-fill! are (Screen put) and (Screen fill)
; for the tui modules, without the class send.

(module x/tui/screen)
(import x/type/class)
(import x/type/vector)
(import x/codec/utf8 utf8-cp-at utf8-width utf8-encode)
(import x/tui/width char-width)
(import x/tui/style style-sgr)

(def %sc-blen (prim-ref (lit str) (lit byte-len)))
(def %sc-bref (prim-ref (lit str) (lit byte-ref)))
(def %sc-bsub (prim-ref (lit str) (lit byte-sub)))
(def %sc-c->i (prim-ref (lit char) (lit ->int)))
(def %sc-make-str (prim-ref (lit str) (lit make)))
(def %sc-str->ptr (prim-ref (lit str) (lit ->ptr)))
(def %sc-pref (prim-ref (lit ptr) (lit ref)))
(def %sc-pset (prim-ref (lit ptr) (lit set!)))
(def %sc-oref (prim-ref (lit obj) (lit ref)))
(def %sc-oset! (prim-ref (lit obj) (lit set!)))
(def %sc-omake (prim-ref (lit obj) (lit make)))
(def %sc< (prim-ref (lit int) (lit <)))
(def %sc+ (prim-ref (lit int) (lit +)))
(def %sc* (prim-ref (lit int) (lit *)))
(def %sc-quot (prim-ref (lit int) (lit /)))
(def %sc-mod (prim-ref (lit int) (lit %)))
(def %sc-and (prim-ref (lit int) (lit &)))
(def %sc-or (prim-ref (lit int) (lit |)))
(def %sc-shr (prim-ref (lit int) (lit >>)))
(def %sc-vector ((prim-ref (lit type) (lit of)) (Vector make 0 ())))

; A screen is a vector: 0 rows, 1 columns, 2 the cells, 3 what the terminal
; shows, 4 the written rows, 5 whether to draw everything, 6 and 7 the row
; and column the cursor is left at, 8 the render buffer, 9 the SGR of each
; style rendered so far, an alist.
(def %sc-get (fn (_ s k) (%sc-oref s (%sc+ k 1))))
(def %sc-put! (fn (_ s k x) (%sc-oset! s (%sc+ k 1) x)))
(def %sc-cells (fn (_ s) (%sc-str->ptr (%sc-get s 2))))
(def %sc-shown (fn (_ s) (%sc-str->ptr (%sc-get s 3))))
(def %sc-dirty (fn (_ s) (%sc-str->ptr (%sc-get s 4))))

; Cell R C's offset in a buffer of COLS columns.
(def %sc-off (fn (_ cols r c) (%sc* 8 (%sc+ (%sc* r cols) c))))
(def %sc-cp (fn (_ p o) (%sc-pref p o 4)))
(def %sc-style (fn (_ p o) (%sc-pref p (%sc+ o 4) 4)))
(def %sc-set! (fn (_ p o cp style) (%sc-pset p o cp 4) (%sc-pset p (%sc+ o 4) style 4)))

; Every cell from offset O to E blank in STYLE.
(def %sc-paint!
  (fn (self p o e style)
    (match ((%sc< o e) (do (%sc-set! p o 32 style) (self p (%sc+ o 8) e style))) (#t ()))))
(def %sc-zero!
  (fn (self p i n) (match ((%sc< i n) (do (%sc-pset p i 0 1) (self p (%sc+ i 1) n))) (#t ()))))

; The longest SGR (every attribute, two 256-colour colours) and a cell's
; widest character, a cursor move a row, and the ends.
(def %sc-alloc!
  (fn (_ s rows cols)
    (def n (%sc* 8 (%sc* rows cols)))
    (%sc-put! s 0 rows) (%sc-put! s 1 cols)
    (%sc-put! s 2 (%sc-make-str n)) (%sc-put! s 3 (%sc-make-str n))
    (%sc-put! s 4 (%sc-make-str rows))
    (%sc-put! s 8 (%sc-make-str (%sc+ (%sc* (%sc* rows cols) 40) (%sc+ (%sc* rows 16) 48))))
    (%sc-paint! (%sc-cells s) 0 n 0)
    (%sc-paint! (%sc-shown s) 0 n 0)
    (%sc-zero! (%sc-dirty s) 0 rows)
    (%sc-put! s 5 #t)
    s))
(def %sc-new
  (fn (_ rows cols)
    (def s (%sc-omake %sc-vector 11))
    (%sc-oset! s 0 10)
    (%sc-put! s 6 0) (%sc-put! s 7 0) (%sc-put! s 9 ())
    (%sc-alloc! s rows cols)))

; Before the cells of the row at offset BASE from C, up to E (not
; included), are written: half of a wide character outside them blank.
(def %sc-split!
  (fn (_ p base cols c e)
    (match ((match ((%sc< 0 c) (= (%sc-cp p (%sc+ base (%sc* 8 c))) 0)) (#t #f))
             ((fn (_ o) (%sc-set! p o 32 (%sc-style p o))) (%sc+ base (%sc* 8 (%sc+ c -1)))))
           (#t ()))
    (match ((match ((%sc< e cols) (= (%sc-cp p (%sc+ base (%sc* 8 e))) 0)) (#t #f))
             ((fn (_ o) (%sc-set! p o 32 (%sc-style p o))) (%sc+ base (%sc* 8 e))))
           (#t ()))))

; TEXT from byte I put from column C, at offset O: the column after it.
; Within the text a cell written over half of a wide character is followed
; by the next, so only the ends need %sc-split!.
(def %sc-text!
  (fn (self p cols o c text i style)
    (match
      ((match ((%sc< i (%sc-blen text)) (%sc< c cols)) (#t #f))
        ((fn (_ b)
           (match
             ((%sc< b 128)
               (%sc-char! self p cols o c text (%sc+ i 1) style b (match ((%sc< b 32) 0) ((= b 127) 0) (#t 1))))
             (#t ((fn (_ cp) (%sc-char! self p cols o c text (%sc+ i (utf8-width text i)) style cp (char-width cp)))
                  (utf8-cp-at text i)))))
         (%sc-c->i (%sc-bref text i))))
      (#t c))))
; Character CP, W cells wide, put at column C, offset O; then the text from
; byte I.
(def %sc-char!
  (fn (_ go p cols o c text i style cp w)
    (match
      ((= w 0) (go p cols o c text i style))
      ((%sc< cols (%sc+ c w)) (do (%sc-set! p o 32 style) cols))
      (#t (do (%sc-set! p o cp style)
              (match ((= w 2) (%sc-set! p (%sc+ o 8) 0 style)) (#t ()))
              (go p cols (%sc+ o (%sc* 8 w)) (%sc+ c w) text i style))))))
(def %sc-in?
  (fn (_ s r c) (match ((%sc< r 0) #f) ((%sc< r (%sc-get s 0)) (match ((%sc< c 0) #f) (#t #t))) (#t #f))))
(def screen-put!
  (fn (_ s r c text style)
    (match
      ((%sc-in? s r c)
        ((fn (_ p cols base)
           (%sc-pset (%sc-dirty s) r 1 1)
           (%sc-split! p base cols c cols)
           ((fn (_ e) (%sc-split! p base cols 0 e) e)
            (%sc-text! p cols (%sc+ base (%sc* 8 c)) c text 0 style)))
         (%sc-cells s) (%sc-get s 1) (%sc-off (%sc-get s 1) r 0)))
      (#t c))))
(def screen-fill!
  (fn (_ s r c n style)
    (def cols (%sc-get s 1))
    (def e (match ((%sc< cols (%sc+ c n)) cols) (#t (%sc+ c n))))
    (match
      ((match ((%sc-in? s r c) (%sc< c e)) (#t #f))
        ((fn (_ p base)
           (%sc-pset (%sc-dirty s) r 1 1)
           (%sc-split! p base cols c e)
           (%sc-paint! p (%sc+ base (%sc* 8 c)) (%sc+ base (%sc* 8 e)) style))
         (%sc-cells s) (%sc-off cols r 0)))
      (#t ()))))

; --- rendering -------------------------------------------------------------
; Writers into the render buffer B at I: each answers the I after.
(def %sc-w! (fn (_ b i x) (%sc-pset b i x 1) (%sc+ i 1)))
(def %sc-ws!
  (fn (self b i s k) (match ((%sc< k (%sc-blen s)) (self b (%sc-w! b i (%sc-c->i (%sc-bref s k))) s (%sc+ k 1))) (#t i))))
(def %sc-wnum!
  (fn (self b i n)
    (match ((%sc< n 10) (%sc-w! b i (%sc+ n 48)))
           (#t (%sc-w! b (self b i (%sc-quot n 10)) (%sc+ (%sc-mod n 10) 48))))))
(def %sc-cont (fn (_ cp shift) (%sc-or 128 (%sc-and (%sc-shr cp shift) 63))))
(def %sc-wcp!
  (fn (_ b i cp)
    (match
      ((%sc< cp 128) (%sc-w! b i cp))
      ((%sc< cp 2048) (%sc-w! b (%sc-w! b i (%sc-or 192 (%sc-shr cp 6))) (%sc-cont cp 0)))
      ((%sc< cp 65536)
        (%sc-w! b (%sc-w! b (%sc-w! b i (%sc-or 224 (%sc-shr cp 12))) (%sc-cont cp 6)) (%sc-cont cp 0)))
      (#t (%sc-w! b (%sc-w! b (%sc-w! b (%sc-w! b i (%sc-or 240 (%sc-shr cp 18))) (%sc-cont cp 12)) (%sc-cont cp 6))
                  (%sc-cont cp 0))))))
(def %sc-wcup!
  (fn (_ b i r c)
    (%sc-w! b (%sc-wnum! b (%sc-w! b (%sc-wnum! b (%sc-w! b (%sc-w! b i 27) 91) (%sc+ r 1)) 59) (%sc+ c 1)) 72)))
; STYLE's SGR, kept on screen S once made.
(def %sc-sgr
  (fn (_ s style)
    ((fn (go l)
       (match ((eq? l ()) ((fn (_ x) (%sc-put! s 9 (pair (pair style x) (%sc-get s 9))) x) (style-sgr style)))
              ((= (first (first l)) style) (rest (first l)))
              (#t (go (rest l)))))
     (%sc-get s 9))))
; The offset of the first cell, from O to E, where P and Q differ, or -1;
; the last, back from E to O.
(def %sc-first
  (fn (self p q o e)
    (match ((%sc< e o) -1)
           ((= (%sc-pref p o 8) (%sc-pref q o 8)) (self p q (%sc+ o 8) e))
           (#t o))))
(def %sc-last
  (fn (self p q o e)
    (match ((= (%sc-pref p e 8) (%sc-pref q e 8)) (self p q o (%sc+ e -8)))
           (#t e))))
; The cells from offset O to E written into B from I, each copied to what
; is shown, Q.  STYLE is the style the terminal has: -1 when it is not
; known.  (I . STYLE) after.
(def %sc-emit
  (fn (self s p q b o e i style)
    (match
      ((%sc< e o) (pair i style))
      (#t (do (def cp (%sc-cp p o))
              (def st (%sc-style p o))
              (%sc-pset q o (%sc-pref p o 8) 8)
              (match
                ((= cp 0) (self s p q b (%sc+ o 8) e i style))
                ((= st style) (self s p q b (%sc+ o 8) e (%sc-wcp! b i cp) style))
                (#t (self s p q b (%sc+ o 8) e (%sc-wcp! b (%sc-ws! b i (%sc-sgr s st) 0) cp) st))))))))
(def %sc-render
  (fn (_ s)
    (def rows (%sc-get s 0)) (def cols (%sc-get s 1))
    (def p (%sc-cells s)) (def q (%sc-shown s)) (def d (%sc-dirty s))
    (def b (%sc-str->ptr (%sc-get s 8)))
    (def whole (%sc-get s 5))
    (def width (%sc* 8 cols))
    ((fn (go r i style)
       (match
         ((= r rows)
           (do (%sc-put! s 5 #f)
               (match ((= i 0) "")
                      (#t (%sc-bsub (%sc-get s 8) 0
                            (%sc-wcup! b (%sc-ws! b i "\x1b[0m" 0) (%sc-get s 6) (%sc-get s 7)))))))
         ((match (whole #t) (#t (= (%sc-pref d r 1) 1)))
           (do (%sc-pset d r 0 1)
               ((fn (_ base)
                  ((fn (_ a)
                     (match
                       ((%sc< a 0) (go (%sc+ r 1) i style))
                       (#t ((fn (_ a e)
                              ((fn (_ done) (go (%sc+ r 1) (first done) (rest done)))
                               (%sc-emit s p q b a e (%sc-wcup! b i r (%sc-quot (%sc+ a (- 0 base)) 8)) style)))
                            (match ((match ((%sc< base a) (= (%sc-cp p a) 0)) (#t #f)) (%sc+ a -8)) (#t a))
                            ((fn (_ e) (match ((match ((%sc< (%sc+ e 8) (%sc+ base width)) (= (%sc-cp p (%sc+ e 8)) 0)) (#t #f))
                                                (%sc+ e 8))
                                               (#t e)))
                             (match (whole (%sc+ base (%sc+ width -8))) (#t (%sc-last p q base (%sc+ base (%sc+ width -8))))))))))
                   (match (whole base) (#t (%sc-first p q base (%sc+ base (%sc+ width -8)))))))
                (%sc* r width))))
         (#t (go (%sc+ r 1) i style))))
     0 (match (whole (%sc-ws! b 0 "\x1b[0m\x1b[H\x1b[2J" 0)) (#t 0)) (match (whole 0) (#t -1)))))
; Row R's characters, as text.
(def %sc-onto (fn (self l acc) (match ((eq? l ()) acc) (#t (self (rest l) (pair (first l) acc))))))
(def %sc-row-text
  (fn (_ s r)
    (def cols (%sc-get s 1)) (def p (%sc-cells s))
    ((fn (go c bytes)
       (match ((= c cols) (bytes->str (%reverse bytes)))
              (#t ((fn (_ cp)
                     (go (%sc+ c 1)
                         (match ((= cp 0) bytes) ((%sc< cp 128) (pair cp bytes)) (#t (%sc-onto (utf8-encode cp) bytes)))))
                   (%sc-cp p (%sc-off cols r c))))))
     0 ())))

(def-class Screen ()
  (doc "A grid of styled terminal cells: put text and fill cells, then (Screen render) answers the escapes that show what changed since the last render."
    (example "(Screen row-text (do (def s (Screen make 2 6)) (Screen put s 0 1 \"hi\" 0) s) 0)" "\" hi   \"")
    (see make) (see put) (see render))
  (static
    (method make (self (param rows INTEGER "Rows") (param cols INTEGER "Columns"))
      (doc "A screen of ROWS by COLS blank, plain cells; its first render clears the terminal and draws it all."
        (returns VECTOR "The screen")
        (example "(Screen cols (Screen make 24 80))" "80"))
      (%sc-new rows cols))
    (method rows (self (param screen VECTOR "A screen"))
      (doc "SCREEN's rows." (returns INTEGER "Rows") (example "(Screen rows (Screen make 3 4))" "3"))
      (%sc-get screen 0))
    (method cols (self (param screen VECTOR "A screen"))
      (doc "SCREEN's columns." (returns INTEGER "Columns") (example "(Screen cols (Screen make 3 4))" "4"))
      (%sc-get screen 1))
    (method put (self (param screen VECTOR "A screen") (param row INTEGER "Row, from 0")
                      (param col INTEGER "Column, from 0") (param text STRING "UTF-8 text")
                      (param style INTEGER "Style (x/tui/style)"))
      (doc "Put TEXT at ROW and COL in STYLE, clipped at the right edge: the column after it. A wide character takes two cells; one with no room at the edge leaves a blank. A row or column off the screen puts nothing."
        (returns INTEGER "The column after the text")
        (example "(Screen put (Screen make 1 10) 0 2 \"abc\" 0)" "5"))
      (screen-put! screen row col text style))
    (method fill (self (param screen VECTOR "A screen") (param row INTEGER "Row, from 0")
                       (param col INTEGER "Column, from 0") (param n INTEGER "Cells")
                       (param style INTEGER "Style (x/tui/style)"))
      (doc "Blank N cells of ROW from COL in STYLE, clipped at the right edge."
        (returns ANY "nil")
        (example "(Screen fill (Screen make 1 4) 0 0 4 16)" ""))
      (screen-fill! screen row col n style))
    (method clear (self (param screen VECTOR "A screen"))
      (doc "Blank every cell of SCREEN, plain."
        (returns ANY "nil")
        (example "(Screen clear (Screen make 2 2))" ""))
      ((fn (go r) (match ((%sc< r (%sc-get screen 0)) (do (screen-fill! screen r 0 (%sc-get screen 1) 0) (go (%sc+ r 1))))
                         (#t ())))
       0))
    (method cursor (self (param screen VECTOR "A screen") (param row INTEGER "Row, from 0")
                         (param col INTEGER "Column, from 0"))
      (doc "Leave the terminal's cursor at ROW and COL after each render."
        (returns ANY "nil")
        (example "(Screen cursor (Screen make 2 2) 1 0)" ""))
      (%sc-put! screen 6 row) (%sc-put! screen 7 col) ())
    (method render (self (param screen VECTOR "A screen"))
      (doc "The escapes that bring the terminal from what the last render showed to SCREEN's cells: per row written since, the span from the first cell that changed to the last, with SGR where the style changes, then the cursor put back. Empty when nothing changed. The first render, and the first after a resize or repaint, clears the terminal and draws every row."
        (returns STRING "Escape sequences and text")
        (example "(do (def s (Screen make 1 3)) (Screen render s) (Screen put s 0 1 \"x\" 0) (Screen render s))" "\"\\x1b[1;2H\\x1b[0mx\\x1b[0m\\x1b[1;1H\""))
      (%sc-render screen))
    (method repaint (self (param screen VECTOR "A screen"))
      (doc "Make the next render clear the terminal and draw every row: for when the terminal's contents are not known."
        (returns ANY "nil")
        (example "(Screen repaint (Screen make 1 1))" ""))
      (%sc-put! screen 5 #t) ())
    (method resize (self (param screen VECTOR "A screen") (param rows INTEGER "Rows")
                         (param cols INTEGER "Columns"))
      (doc "Make SCREEN ROWS by COLS, every cell blank; the next render draws it all."
        (returns VECTOR "The screen")
        (example "(Screen rows (Screen resize (Screen make 2 2) 5 9))" "5"))
      (%sc-alloc! screen rows cols))
    (method row-text (self (param screen VECTOR "A screen") (param row INTEGER "Row, from 0"))
      (doc "ROW's characters as text, a wide character once."
        (returns STRING "The row's text")
        (example "(Screen row-text (Screen make 1 3) 0)" "\"   \""))
      (%sc-row-text screen row))
    (method style-at (self (param screen VECTOR "A screen") (param row INTEGER "Row, from 0")
                           (param col INTEGER "Column, from 0"))
      (doc "The style of the cell at ROW and COL."
        (returns INTEGER "A style")
        (example "(Screen style-at (Screen make 1 1) 0 0)" "0"))
      (%sc-style (%sc-cells screen) (%sc-off (%sc-get screen 1) row col)))))

(provide x/tui/screen Screen screen-put! screen-fill!)
