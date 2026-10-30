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

(import x/core/doors char->int int% int& int* int+ int/ int< int>> int| obj-make obj-ref obj-set! ptr-ref ptr-set! str->ptr str-byte-len str-byte-ref str-byte-sub str-make)
(def %sc-vector ((prim-ref (lit type) (lit of)) (Vector make 0 ())))

; A screen is a vector: 0 rows, 1 columns, 2 the cells, 3 what the terminal
; shows, 4 the written rows, 5 whether to draw everything, 6 and 7 the row
; and column the cursor is left at, 8 the render buffer, 9 the SGR of each
; style rendered so far, an alist.
(def %sc-get (fn (_ s k) (obj-ref s (int+ k 1))))
(def %sc-put! (fn (_ s k x) (obj-set! s (int+ k 1) x)))
(def %sc-cells (fn (_ s) (str->ptr (%sc-get s 2))))
(def %sc-shown (fn (_ s) (str->ptr (%sc-get s 3))))
(def %sc-dirty (fn (_ s) (str->ptr (%sc-get s 4))))

; Cell R C's offset in a buffer of COLS columns.
(def %sc-off (fn (_ cols r c) (int* 8 (int+ (int* r cols) c))))
(def %sc-cp (fn (_ p o) (ptr-ref p o 4)))
(def %sc-style (fn (_ p o) (ptr-ref p (int+ o 4) 4)))
(def %sc-set! (fn (_ p o cp style) (ptr-set! p o cp 4) (ptr-set! p (int+ o 4) style 4)))

; Every cell from offset O to E blank in STYLE.
(def %sc-paint!
  (fn (self p o e style)
    (match ((int< o e) (do (%sc-set! p o 32 style) (self p (int+ o 8) e style))) (#t ()))))
(def %sc-zero!
  (fn (self p i n) (match ((int< i n) (do (ptr-set! p i 0 1) (self p (int+ i 1) n))) (#t ()))))

; The longest SGR (every attribute, two 256-colour colours) and a cell's
; widest character, a cursor move a row, and the ends.
(def %sc-alloc!
  (fn (_ s rows cols)
    (def n (int* 8 (int* rows cols)))
    (%sc-put! s 0 rows) (%sc-put! s 1 cols)
    (%sc-put! s 2 (str-make n)) (%sc-put! s 3 (str-make n))
    (%sc-put! s 4 (str-make rows))
    (%sc-put! s 8 (str-make (int+ (int* (int* rows cols) 40) (int+ (int* rows 16) 48))))
    (%sc-paint! (%sc-cells s) 0 n 0)
    (%sc-paint! (%sc-shown s) 0 n 0)
    (%sc-zero! (%sc-dirty s) 0 rows)
    (%sc-put! s 5 #t)
    s))
(def %sc-new
  (fn (_ rows cols)
    (def s (obj-make %sc-vector 11))
    (obj-set! s 0 10)
    (%sc-put! s 6 0) (%sc-put! s 7 0) (%sc-put! s 9 ())
    (%sc-alloc! s rows cols)))

; Before the cells of the row at offset BASE from C, up to E (not
; included), are written: half of a wide character outside them blank.
(def %sc-split!
  (fn (_ p base cols c e)
    (match ((match ((int< 0 c) (= (%sc-cp p (int+ base (int* 8 c))) 0)) (#t #f))
             ((fn (_ o) (%sc-set! p o 32 (%sc-style p o))) (int+ base (int* 8 (int+ c -1)))))
           (#t ()))
    (match ((match ((int< e cols) (= (%sc-cp p (int+ base (int* 8 e))) 0)) (#t #f))
             ((fn (_ o) (%sc-set! p o 32 (%sc-style p o))) (int+ base (int* 8 e))))
           (#t ()))))

; TEXT from byte I put from column C, at offset O: the column after it.
; Within the text a cell written over half of a wide character is followed
; by the next, so only the ends need %sc-split!.
(def %sc-text!
  (fn (self p cols o c text i style)
    (match
      ((match ((int< i (str-byte-len text)) (int< c cols)) (#t #f))
        ((fn (_ b)
           (match
             ((int< b 128)
               (%sc-char! self p cols o c text (int+ i 1) style b (match ((int< b 32) 0) ((= b 127) 0) (#t 1))))
             (#t ((fn (_ cp) (%sc-char! self p cols o c text (int+ i (utf8-width text i)) style cp (char-width cp)))
                  (utf8-cp-at text i)))))
         (char->int (str-byte-ref text i))))
      (#t c))))
; Character CP, W cells wide, put at column C, offset O; then the text from
; byte I.
(def %sc-char!
  (fn (_ go p cols o c text i style cp w)
    (match
      ((= w 0) (go p cols o c text i style))
      ((int< cols (int+ c w)) (do (%sc-set! p o 32 style) cols))
      (#t (do (%sc-set! p o cp style)
              (match ((= w 2) (%sc-set! p (int+ o 8) 0 style)) (#t ()))
              (go p cols (int+ o (int* 8 w)) (int+ c w) text i style))))))
(def %sc-in?
  (fn (_ s r c) (match ((int< r 0) #f) ((int< r (%sc-get s 0)) (match ((int< c 0) #f) (#t #t))) (#t #f))))
(def screen-put!
  (fn (_ s r c text style)
    (match
      ((%sc-in? s r c)
        ((fn (_ p cols base)
           (ptr-set! (%sc-dirty s) r 1 1)
           (%sc-split! p base cols c cols)
           ((fn (_ e) (%sc-split! p base cols 0 e) e)
            (%sc-text! p cols (int+ base (int* 8 c)) c text 0 style)))
         (%sc-cells s) (%sc-get s 1) (%sc-off (%sc-get s 1) r 0)))
      (#t c))))
(def screen-fill!
  (fn (_ s r c n style)
    (def cols (%sc-get s 1))
    (def e (match ((int< cols (int+ c n)) cols) (#t (int+ c n))))
    (match
      ((match ((%sc-in? s r c) (int< c e)) (#t #f))
        ((fn (_ p base)
           (ptr-set! (%sc-dirty s) r 1 1)
           (%sc-split! p base cols c e)
           (%sc-paint! p (int+ base (int* 8 c)) (int+ base (int* 8 e)) style))
         (%sc-cells s) (%sc-off cols r 0)))
      (#t ()))))

; --- rendering -------------------------------------------------------------
; Writers into the render buffer B at I: each answers the I after.
(def %sc-w! (fn (_ b i x) (ptr-set! b i x 1) (int+ i 1)))
(def %sc-ws!
  (fn (self b i s k) (match ((int< k (str-byte-len s)) (self b (%sc-w! b i (char->int (str-byte-ref s k))) s (int+ k 1))) (#t i))))
(def %sc-wnum!
  (fn (self b i n)
    (match ((int< n 10) (%sc-w! b i (int+ n 48)))
           (#t (%sc-w! b (self b i (int/ n 10)) (int+ (int% n 10) 48))))))
(def %sc-cont (fn (_ cp shift) (int| 128 (int& (int>> cp shift) 63))))
(def %sc-wcp!
  (fn (_ b i cp)
    (match
      ((int< cp 128) (%sc-w! b i cp))
      ((int< cp 2048) (%sc-w! b (%sc-w! b i (int| 192 (int>> cp 6))) (%sc-cont cp 0)))
      ((int< cp 65536)
        (%sc-w! b (%sc-w! b (%sc-w! b i (int| 224 (int>> cp 12))) (%sc-cont cp 6)) (%sc-cont cp 0)))
      (#t (%sc-w! b (%sc-w! b (%sc-w! b (%sc-w! b i (int| 240 (int>> cp 18))) (%sc-cont cp 12)) (%sc-cont cp 6))
                  (%sc-cont cp 0))))))
(def %sc-wcup!
  (fn (_ b i r c)
    (%sc-w! b (%sc-wnum! b (%sc-w! b (%sc-wnum! b (%sc-w! b (%sc-w! b i 27) 91) (int+ r 1)) 59) (int+ c 1)) 72)))
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
    (match ((int< e o) -1)
           ((= (ptr-ref p o 8) (ptr-ref q o 8)) (self p q (int+ o 8) e))
           (#t o))))
(def %sc-last
  (fn (self p q o e)
    (match ((= (ptr-ref p e 8) (ptr-ref q e 8)) (self p q o (int+ e -8)))
           (#t e))))
; The cells from offset O to E written into B from I, each copied to what
; is shown, Q.  STYLE is the style the terminal has: -1 when it is not
; known.  (I . STYLE) after.
(def %sc-emit
  (fn (self s p q b o e i style)
    (match
      ((int< e o) (pair i style))
      (#t (do (def cp (%sc-cp p o))
              (def st (%sc-style p o))
              (ptr-set! q o (ptr-ref p o 8) 8)
              (match
                ((= cp 0) (self s p q b (int+ o 8) e i style))
                ((= st style) (self s p q b (int+ o 8) e (%sc-wcp! b i cp) style))
                (#t (self s p q b (int+ o 8) e (%sc-wcp! b (%sc-ws! b i (%sc-sgr s st) 0) cp) st))))))))
(def %sc-render
  (fn (_ s)
    (def rows (%sc-get s 0)) (def cols (%sc-get s 1))
    (def p (%sc-cells s)) (def q (%sc-shown s)) (def d (%sc-dirty s))
    (def b (str->ptr (%sc-get s 8)))
    (def whole (%sc-get s 5))
    (def width (int* 8 cols))
    ((fn (go r i style)
       (match
         ((= r rows)
           (do (%sc-put! s 5 #f)
               (match ((= i 0) "")
                      (#t (str-byte-sub (%sc-get s 8) 0
                            (%sc-wcup! b (%sc-ws! b i "\x1b[0m" 0) (%sc-get s 6) (%sc-get s 7)))))))
         ((match (whole #t) (#t (= (ptr-ref d r 1) 1)))
           (do (ptr-set! d r 0 1)
               ((fn (_ base)
                  ((fn (_ a)
                     (match
                       ((int< a 0) (go (int+ r 1) i style))
                       (#t ((fn (_ a e)
                              ((fn (_ done) (go (int+ r 1) (first done) (rest done)))
                               (%sc-emit s p q b a e (%sc-wcup! b i r (int/ (int+ a (- 0 base)) 8)) style)))
                            (match ((match ((int< base a) (= (%sc-cp p a) 0)) (#t #f)) (int+ a -8)) (#t a))
                            ((fn (_ e) (match ((match ((int< (int+ e 8) (int+ base width)) (= (%sc-cp p (int+ e 8)) 0)) (#t #f))
                                                (int+ e 8))
                                               (#t e)))
                             (match (whole (int+ base (int+ width -8))) (#t (%sc-last p q base (int+ base (int+ width -8))))))))))
                   (match (whole base) (#t (%sc-first p q base (int+ base (int+ width -8)))))))
                (int* r width))))
         (#t (go (int+ r 1) i style))))
     0 (match (whole (%sc-ws! b 0 "\x1b[0m\x1b[H\x1b[2J" 0)) (#t 0)) (match (whole 0) (#t -1)))))
; Row R's characters, as text.
(def %sc-onto (fn (self l acc) (match ((eq? l ()) acc) (#t (self (rest l) (pair (first l) acc))))))
(def %sc-row-text
  (fn (_ s r)
    (def cols (%sc-get s 1)) (def p (%sc-cells s))
    ((fn (go c bytes)
       (match ((= c cols) (bytes->str (%reverse bytes)))
              (#t ((fn (_ cp)
                     (go (int+ c 1)
                         (match ((= cp 0) bytes) ((int< cp 128) (pair cp bytes)) (#t (%sc-onto (utf8-encode cp) bytes)))))
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
      ((fn (go r) (match ((int< r (%sc-get screen 0)) (do (screen-fill! screen r 0 (%sc-get screen 1) 0) (go (int+ r 1))))
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
