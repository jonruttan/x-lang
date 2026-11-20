; codec/pdf-write.x -- PdfWrite: a document as a PDF file.
;
; (PdfWrite bytes BLOCKS) answers the bytes of a PDF that sets a document
; tree (x/codec/document) on US Letter pages: headings in bold at six sizes,
; paragraphs broken at spaces to the page's width and set ragged right,
; code in Courier, quotes and list items indented, a rule for a thematic
; break, a table's rows a line each, its cells parted by bars, and a new
; page when one is full.
;
; The fonts are five of the standard fourteen, which a reader of PDF has
; and a file need not carry: Helvetica, its bold, its oblique and its bold
; oblique for text, emphasis and strong emphasis, and Courier for code.
; Their widths are Adobe's, from the fonts' metric files, here as tables a
; line is measured against; each font's dictionary carries the same widths.
;
; Text is written in WinAnsiEncoding, so a character outside it -- outside
; Latin-1 and the quotes, dashes and few letters Windows adds -- is written
; as a question mark.  A link is its text with an annotation over it that
; goes where the link goes, one rectangle a line; an image is its
; alternative text,
; a form's field its value, and raw HTML is left out.  Lengths are integers
; in thousandths of a point: a width in the tables times a size is one.
;
; The file is plain: its content streams are not compressed, and the only
; bytes past ASCII are text's.  Not yet here: a link's title, images,
; tables as grids, other page sizes and fonts, and justified text.

(module x/codec/pdf-write)
(import x/type/class)
(import x/core/list)
(import x/type/vector)
(import x/codec/pdf-glyphs pdf-encoding)

(import x/core/doors int% int& int* int+ int- int/ int< int<< int= int| obj-make obj-ref obj-set! ptr-ref ptr-set! str->ptr str-byte-len str-make type-of)

; --- the page ---------------------------------------------------------------
(def %pw-width 612000)
(def %pw-height 792000)
(def %pw-margin 72000)
(def %pw-body 11)
; A heading's size by its level.
(def %pw-sizes (list 20 16 14 12 11 11))
; How far a quote or a list item is set in.
(def %pw-indent 18000)

; --- widths -----------------------------------------------------------------
; The widths of the codes 32 to 255 of WinAnsiEncoding, in thousandths of
; the size, 0 for a code the encoding leaves out.  The oblique faces have
; their upright's widths; every glyph of Courier is 600.
(def %pw-regular
  (Vector from-list (list
        278 278 355 556 556 889 667 191 333 333 389 584 278 333 278 278 556 556 556 556 556 556 556 556 556 556 278
        278 584 584 584 556 1015 667 667 722 722 667 611 778 722 278 500 667 556 833 722 778 667 778 722 667 611 722
        667 944 667 667 611 278 278 278 469 556 333 556 556 500 556 556 278 556 556 222 222 500 222 833 556 556 556
        556 333 500 278 556 500 722 500 500 500 334 260 334 584 0 556 0 222 556 333 1000 556 556 333 1000 667 333
        1000 0 611 0 0 222 222 333 333 350 556 1000 333 1000 500 333 944 0 500 667 278 333 556 556 556 556 260 556
        333 737 370 556 584 333 737 333 400 584 333 333 333 556 537 278 333 333 365 556 834 834 834 611 667 667 667
        667 667 667 1000 722 667 667 667 667 278 278 278 278 722 722 778 778 778 778 778 584 778 722 722 722 722 667
        667 611 556 556 556 556 556 556 889 500 556 556 556 556 278 278 278 278 556 556 556 556 556 556 556 584 611
        556 556 556 556 500 556 500)))
(def %pw-bold
  (Vector from-list (list
        278 333 474 556 556 889 722 238 333 333 389 584 278 333 278 278 556 556 556 556 556 556 556 556 556 556 333
        333 584 584 584 611 975 722 722 722 722 667 611 778 722 278 556 722 611 833 722 778 667 778 722 667 611 722
        667 944 667 667 611 333 278 333 584 556 333 556 611 556 611 556 333 611 611 278 278 556 278 889 611 611 611
        611 389 556 333 611 556 778 556 556 500 389 280 389 584 0 556 0 278 556 500 1000 556 556 333 1000 667 333
        1000 0 611 0 0 278 278 500 500 350 556 1000 333 1000 556 333 944 0 500 667 278 333 556 556 556 556 280 556
        333 737 370 556 584 333 737 333 400 584 333 333 333 611 556 278 333 333 365 556 834 834 834 611 722 722 722
        722 722 722 1000 722 667 667 667 667 278 278 278 278 722 722 778 778 778 778 778 584 778 722 722 722 722 667
        667 611 556 556 556 556 556 556 889 556 556 556 556 556 278 278 278 278 611 611 611 611 611 611 611 584 611
        611 611 611 611 556 611 556)))
; A font is its number: 0 Helvetica, 1 bold, 2 oblique, 3 bold oblique, 4
; Courier.  So a style's bold is 1 and its italic 2, and code is 4.
(def %pw-fonts
  (list (list "Helvetica" "32/FontBBox[-166 -225 1000 931]/ItalicAngle 0/Ascent 718/Descent -207/CapHeight 718/StemV 88")
        (list "Helvetica-Bold" "32/FontBBox[-170 -228 1003 962]/ItalicAngle 0/Ascent 718/Descent -207/CapHeight 718/StemV 140")
        (list "Helvetica-Oblique" "96/FontBBox[-170 -225 1116 931]/ItalicAngle -12/Ascent 718/Descent -207/CapHeight 718/StemV 88")
        (list "Helvetica-BoldOblique" "96/FontBBox[-174 -228 1114 962]/ItalicAngle -12/Ascent 718/Descent -207/CapHeight 718/StemV 140")
        (list "Courier" "33/FontBBox[-23 -250 715 805]/ItalicAngle 0/Ascent 629/Descent -157/CapHeight 562/StemV 51")))
; The width of CODE in FONT, in thousandths of the size.
(def %pw-wide
  (fn (_ font code)
    (match ((int= font 4) 600)
           ((int< code 32) 0)
           ((int< 255 code) 0)
           ((int= (int& font 1) 1) (obj-ref %pw-bold (int+ (int- code 32) 1)))
           (#t (obj-ref %pw-regular (int+ (int- code 32) 1))))))

; --- text -------------------------------------------------------------------
(def %pw-u8 (fn (_ p i) (int& (ptr-ref p i 1) 255)))
; The WinAnsi code of a code point, a question mark's for one it lacks.
(def %pw-code
  (fn (_ cp)
    (match ((int< cp 32) 32)
           ((int< cp 127) cp)
           ((int< cp 160)  63)
           ((int< cp 256) cp)
           (#t ((fn (self c) (match ((int< 159 c) 63) ((eq? (pdf-encoding "WinAnsiEncoding" c) cp) c) (#t (self (int+ c 1))))) 128)))))
; The code point of the UTF-8 at I of P, before N: (CODE-POINT . NEXT).  A
; byte that starts no character is itself.
(def %pw-cp
  (fn (_ p i n)
    (def b (%pw-u8 p i))
    (def more (fn (_ k) (match ((int< (int+ i k) n) (int& (%pw-u8 p (int+ i k)) 63)) (#t 0))))
    (match ((int< b 192) (pair b (int+ i 1)))
           ((int< b 224) (pair (int| (int<< (int& b 31) 6) (more 1)) (int+ i 2)))
           ((int< b 240) (pair (int| (int| (int<< (int& b 15) 12) (int<< (more 1) 6)) (more 2)) (int+ i 3)))
           (#t (pair (int| (int| (int| (int<< (int& b 7) 18) (int<< (more 1) 12)) (int<< (more 2) 6)) (more 3)) (int+ i 4))))))
; A string of the codes in the list CS, as a PDF literal string's inside:
; a parenthesis or a reverse solidus after a reverse solidus.
(def %pw-literal
  (fn (_ cs)
    (def s (str-make (int+ (int* 2 (List length cs)) 1)))
    (def p (str->ptr s))
    ((fn (self l i)
       (match ((null? l) (ptr-set! p i 0 1))
              ((match ((int= (first l) 40) #t) ((int= (first l) 41) #t) ((int= (first l) 92) #t) (#t #f))
                (do (ptr-set! p i 92 1) (ptr-set! p (int+ i 1) (first l) 1) (self (rest l) (int+ i 2))))
              (#t (do (ptr-set! p i (first l) 1) (self (rest l) (int+ i 1))))))
     cs 0)
    s))
; A length in thousandths as a PDF number: 72000 is 72, 5400 is 5.4.
(def %pw-number
  (fn (_ m)
    (def a (match ((int< m 0) (int- 0 m)) (#t m)))
    (def whole (Str8 str (int/ a 1000)))
    (def frac (int% a 1000))
    (Str8 append
      (match ((int< m 0) "-") (#t ""))
      whole
      (match ((int= frac 0) "")
             ((int= (int% frac 100) 0) (Str8 append "." (Str8 str (int/ frac 100))))
             ((int= (int% frac 10) 0) (Str8 append "." (match ((int< frac 100) "0") (#t "")) (Str8 str (int/ frac 10))))
             (#t (Str8 append "." (match ((int< frac 10) "00") ((int< frac 100) "0") (#t "")) (Str8 str frac)))))))

; --- chunks -----------------------------------------------------------------
; Inlines become chunks, the runs of text between spaces: a chunk is a list
; of pieces, each (FONT CODES WIDTH LINK), its codes most recent first, its
; width in thousandths of the size, and the destination of the link it is
; in or nil.  A line may end after any chunk; the
; symbol break among the chunks ends one.
(def %pw-chunks
  (fn (_ inlines style)
    (def codes ())
    (def wide 0)
    (def font 0)
    (def link ())
    (def pieces ())
    (def chunks ())
    (def end-piece!
      (fn (_)
        (unless (null? codes)
          (set! pieces (pair (list font codes wide link) pieces))
          (set! codes ())
          (set! wide 0))))
    (def end-chunk!
      (fn (_)
        (end-piece!)
        (unless (null? pieces)
          (set! chunks (pair (List reverse pieces) chunks))
          (set! pieces ()))))
    (def text!
      (fn (_ s f)
        (unless (int= f font) (end-piece!) (set! font f))
        (def p (str->ptr s))
        (def n (str-byte-len s))
        ((fn (self i)
           (when (int< i n)
             ((fn (_ at)
                (match ((match ((int= (first at) 32) #t) ((int= (first at) 10) #t) ((int= (first at) 9) #t) (#t #f)) (end-chunk!))
                       (#t ((fn (_ c) (set! codes (pair c codes)) (set! wide (int+ wide (%pw-wide f c)))) (%pw-code (first at)))))
                (self (rest at)))
              (%pw-cp p i n))))
         0)))
    ((fn (walk l style)
       (unless (null? l)
         ((fn (_ x)
            (match
              ((str? x) (text! x style))
              ((eq? (first x) (lit emph)) (walk (first (rest x)) (match ((int= style 4) 4) (#t (int| style 2)))))
              ((eq? (first x) (lit strong)) (walk (first (rest x)) (match ((int= style 4) 4) (#t (int| style 1)))))
              ((eq? (first x) (lit code)) (text! (first (rest x)) 4))
              ((eq? (first x) (lit softbreak)) (end-chunk!))
              ((eq? (first x) (lit hardbreak)) (do (end-chunk!) (set! chunks (pair (lit break) chunks))))
              ((eq? (first x) (lit link))
                (do (end-piece!) (set! link (List ref 1 x))
                    (walk (List ref 3 x) style)
                    (end-piece!) (set! link ())))
              ((eq? (first x) (lit image)) (walk (List ref 3 x) style))
              ((eq? (first x) (lit field)) (when (str? (List ref 3 x)) (text! (List ref 3 x) style)))
              (#t ())))
          (first l))
         (walk (rest l) style)))
     inlines style)
    (end-chunk!)
    (List reverse chunks)))
; A line of code as one chunk of one Courier piece, its spaces kept.
(def %pw-verbatim
  (fn (_ line)
    (def p (str->ptr line))
    (def n (str-byte-len line))
    ((fn (self i codes)
       (match ((int< i n) ((fn (_ at) (self (rest at) (pair (%pw-code (first at)) codes))) (%pw-cp p i n)))
              ((null? codes) ())
              (#t (list (list (list 4 codes (int* 600 (List length codes)) ()))))))
     0 ())))
(def %pw-chunk-width(fn (_ chunk) (List fold (fn (_ w piece) (int+ w (List ref 2 piece))) 0 chunk)))
; The space after CHUNK: its last piece's font's, so a styled word's space
; is the plain text's when plain text follows the word in its chunk.
(def %pw-space (fn (_ chunk) (%pw-wide (first (List last chunk)) 32)))
; CHUNKS as lines no wider than ROOM, in thousandths of the size: each a
; list of chunks.  A chunk wider than the room has a line to itself.
(def %pw-lines
  (fn (_ chunks room)
    ((fn (self l line used acc)
       (def close (fn (_) (match ((null? line) acc) (#t (pair (List reverse line) acc)))))
       (match
         ((null? l) (List reverse (close)))
         ((eq? (first l) (lit break)) (self (rest l) () 0 (pair (List reverse line) acc)))
         (#t ((fn (_ w)
                (match ((null? line) (self (rest l) (list (first l)) w acc))
                       ((int< room (int+ (int+ used (%pw-space (first line))) w)) (self (rest l) (list (first l)) w (close)))
                       (#t (self (rest l) (pair (first l) line) (int+ (int+ used (%pw-space (first line))) w) acc))))
              (%pw-chunk-width (first l))))))
     chunks () 0 ())))

; --- pages ------------------------------------------------------------------
; The state a document is set in: a vector of where the next line's top is,
; the page being set as content strings most recent first, the pages
; done, each (CONTENT . ANNOTATIONS), and the page being set's link
; annotations most recent first.
(def %pw-vector (type-of (Vector make 0 ())))
(def %pw-state
  (fn (_)
    (def s (obj-make %pw-vector 5))
    (obj-set! s 0 3)
    (obj-set! s 1 (int- %pw-height %pw-margin))
    (obj-set! s 2 ())
    (obj-set! s 3 ())
    (obj-set! s 4 ())
    s))
(def %pw-y (fn (_ s) (obj-ref s 1)))
(def %pw-put! (fn (_ s text) (obj-set! s 2 (pair text (obj-ref s 2)))))
(def %pw-page!
  (fn (_ s)
    (obj-set! s 3 (pair (pair (%str-concat (List reverse (obj-ref s 2))) (%str-concat (List reverse (obj-ref s 4)))) (obj-ref s 3)))
    (obj-set! s 4 ())
    (obj-set! s 2 ())
    (obj-set! s 1 (int- %pw-height %pw-margin))))
; Make room for HIGH below the cursor, on a new page when this one has none.
(def %pw-need! (fn (_ s high) (when (int< (int- (%pw-y s) high) %pw-margin) (%pw-page! s))))
; Move the cursor down HIGH; no further than the page's top when it is there.
(def %pw-down!
  (fn (_ s high)
    (unless (int= (%pw-y s) (int- %pw-height %pw-margin)) (obj-set! s 1 (int- (%pw-y s) high)))))
; The link the space between the chunks A and B is in: theirs when A ends
; and B begins in one link, else none.
(def %pw-between
  (fn (_ a b)
    ((fn (_ x y) (match ((eq? x y) x) (#t ()))) (List ref 3 (List last a)) (List ref 3 (first b)))))
; The bytes of S as a literal string's inside.
(def %pw-bytes
  (fn (_ s)
    (def p (str->ptr s))
    (def n (str-byte-len s))
    (%pw-literal ((fn (self i acc) (match ((int< i n) (self (int+ i 1) (pair (%pw-u8 p i) acc))) (#t (List reverse acc)))) 0 ()))))
; A link annotation over the baseline Y from X1 to X2 at SIZE, to DEST.
(def %pw-annotation
  (fn (_ x1 x2 y size dest)
    (Str8 append "<</Type/Annot/Subtype/Link/Rect[" (%pw-number x1) " " (%pw-number (int- y (int* size 200))) " "
                 (%pw-number x2) " " (%pw-number (int+ y (int* size 800))) "]/Border[0 0 0]/A<</S/URI/URI(" (%pw-bytes dest) ")>>>>")))
; The annotations of a line's chunks set from X on the baseline Y at SIZE:
; one for each run of pieces in one link, the space between two chunks of
; the link inside it.
(def %pw-annotations
  (fn (_ chunks x y size)
    ; The line's pieces in order, each space between chunks a piece too.
    (def pieces
      ((fn (self l prev acc)
         (match ((null? l) (List reverse acc))
                (#t (self (rest l) (first l)
                          (List append (List reverse (first l))
                                       (match ((null? prev) acc)
                                              (#t (pair (list 0 () (%pw-space prev) (%pw-between prev (first l))) acc))))))))
       chunks () ()))
    ((fn (self l at link from acc)
       (def close (fn (_ to) (match ((null? link) acc) (#t (pair (%pw-annotation from to y size link) acc)))))
       (match ((null? l) (List reverse (close at)))
              (#t ((fn (_ piece next)
                     (match ((eq? (List ref 3 piece) link) (self (rest l) next link from acc))
                            (#t (self (rest l) next (List ref 3 piece) at (close at)))))
                   (first l) (int+ at (int* (List ref 2 (first l)) size))))))
     pieces x () x ())))
; The text operators that show a line's chunks from X on the baseline Y at
; SIZE: a font named when it changes, a space between chunks.
(def %pw-show
  (fn (_ chunks x y size)
    (def out (list (Str8 append "BT " (%pw-number x) " " (%pw-number y) " Td")))
    (def font -1)
    (def codes ())
    (def flush!
      (fn (_)
        (unless (null? codes)
          (set! out (pair (Str8 append " (" (%pw-literal (List reverse codes)) ") Tj") out))
          (set! codes ()))))
    (def link ())
    ; A string ends where the font or the link changes, so a link's text is
    ; a string of its own and a reader can tell it from the text beside it.
    (def piece!
      (fn (_ f cs to)
        (unless (eq? to link)
          (flush!)
          (set! link to))
        (unless (int= f font)
          (flush!)
          (set! font f)
          (set! out (pair (Str8 append " /F" (Str8 str f) " " (Str8 str size) " Tf") out)))
        (set! codes (List append cs codes))))
    ((fn (self l prev)
       (unless (null? l)
         (unless (null? prev) (piece! font (list 32) (%pw-between prev (first l))))
         (List for-each (fn (_ piece) (piece! (first piece) (List ref 1 piece) (List ref 3 piece))) (first l))
         (self (rest l) (first l))))
     chunks ())
    (flush!)
    (%str-concat (List reverse (pair " ET\n" out)))))
; Set CHUNKS as lines from the left edge X at SIZE, LEADING apart.
(def %pw-set!
  (fn (_ s chunks x size leading)
    (List for-each
      (fn (_ line)
        (%pw-need! s leading)
        (unless (null? line)
          (%pw-put! s (%pw-show line x (int- (%pw-y s) (int* size 1000)) size))
          (obj-set! s 4 (List append (List reverse (%pw-annotations line x (int- (%pw-y s) (int* size 1000)) size)) (obj-ref s 4))))
        (obj-set! s 1 (int- (%pw-y s) leading)))
      (%pw-lines chunks (int/ (int- (int- %pw-width %pw-margin) x) size)))))
; The lines of TEXT, each cut to WIDE bytes a piece.
(def %pw-code-lines
  (fn (_ text wide)
    (List flat-map
      (fn (_ line)
        ((fn (self l acc)
           (match ((int< wide (Str8 length l)) (self (Str8 sub wide (int- (Str8 length l) wide) l) (pair (Str8 sub 0 wide l) acc)))
                  (#t (List reverse (pair l acc)))))
         line ()))
      ((fn (_ ls) (match ((null? ls) ()) ((str=? (List last ls) "") (List init ls)) (#t ls))) (Str8 split "\n" text)))))
; A table's rows as paragraphs, a row's cells parted by " | ", a header
; row's strong.
(def %pw-table-rows
  (fn (_ b)
    ((fn (self rows head)
       (match ((null? rows) ())
              (#t (pair (list (lit paragraph)
                              ((fn (_ inl) (match (head (list (list (lit strong) inl))) (#t inl)))
                               (List flat-map (fn (_ c) c)
                                 ((fn (join cs) (match ((null? cs) ()) ((null? (rest cs)) (list (first cs)))
                                                       (#t (pair (first cs) (pair (list " | ") (join (rest cs)))))))
                                  (first rows)))))
                        (self (rest rows) #f)))))
     (List ref 3 b) (List ref 1 b))))
; Set BLOCKS from the left edge X.  TIGHT? leaves less after a paragraph.
(def %pw-blocks!
  (fn (blocks! s blocks x tight?)
    (List for-each
      (fn (_ b)
        ((fn (_ kind)
           (match
             ((eq? kind (lit paragraph))
               (do (%pw-set! s (%pw-chunks (List ref 1 b) 0) x %pw-body 14000)
                   (%pw-down! s (match (tight? 2000) (#t 7000)))))
             ((eq? kind (lit heading))
               ((fn (_ size)
                  (%pw-down! s (int* size 500))
                  (%pw-need! s (int* size 3000))
                  (%pw-set! s (%pw-chunks (List ref 2 b) 1) x size (int* size 1250))
                  (%pw-down! s (int* size 300)))
                (List ref (int- (List ref 1 b) 1) %pw-sizes)))
             ((eq? kind (lit code-block))
               (do (List for-each
                     (fn (_ line)
                       (%pw-need! s 11000)
                       (unless (str=? line "") (%pw-put! s (%pw-show (%pw-verbatim line) x (int- (%pw-y s) 9000) 9)))
                       (obj-set! s 1 (int- (%pw-y s) 11000)))
                     (%pw-code-lines (List ref 2 b) (int/ (int- (int- %pw-width %pw-margin) x) 5400)))
                   (%pw-down! s 7000)))
             ((eq? kind (lit block-quote)) (blocks! s (List ref 1 b) (int+ x %pw-indent) tight?))
             ((eq? kind (lit table)) (do (blocks! s (%pw-table-rows b) x #t) (%pw-down! s 5000)))
             ((eq? kind (lit list))
               (do ((fn (self items n)
                      (unless (null? items)
                        (%pw-need! s 14000)
                        (%pw-put! s (%pw-show (%pw-chunks (list (match ((List ref 1 b) (Str8 append (Str8 str n) ".")) (#t "\xe2\x80\xa2"))) 0)
                                              x (int- (%pw-y s) (int* %pw-body 1000)) %pw-body))
                        (blocks! s (first items) (int+ x %pw-indent) (List ref 3 b))
                        (self (rest items) (int+ n 1))))
                    (List ref 4 b) (match ((null? (List ref 2 b)) 1) (#t (List ref 2 b))))
                   (when (List ref 3 b) (%pw-down! s 5000))))
             ((eq? kind (lit thematic-break))
               (do (%pw-need! s 14000)
                   (%pw-put! s (Str8 append "0.5 w " (%pw-number x) " " (%pw-number (int- (%pw-y s) 7000)) " m "
                                            (%pw-number (int- %pw-width %pw-margin)) " " (%pw-number (int- (%pw-y s) 7000)) " l S\n"))
                   (obj-set! s 1 (int- (%pw-y s) 14000))
                   (%pw-down! s 7000)))
             (#t ())))
         (first b)))
      blocks)))

; --- the file ---------------------------------------------------------------
; A font's widths from 32 to 255 as an array's inside.
(def %pw-widths
  (fn (_ font)
    (Str8 join " " (List map (fn (_ c) (Str8 str (%pw-wide font c))) (List range 32 256)))))
; TITLE as a literal string's inside, in WinAnsi.
(def %pw-title
  (fn (_ title)
    (def p (str->ptr title))
    (def n (str-byte-len title))
    (%pw-literal
      ((fn (self i acc)
         (match ((int< i n) ((fn (_ at) (self (rest at) (pair (%pw-code (first at)) acc))) (%pw-cp p i n)))
                (#t (List reverse acc))))
       0 ()))))
; The file of PAGES, each (CONTENT . ANNOTATIONS), in order, with TITLE or
; nil.
(def %pw-file
  (fn (_ pages title)
    (def count (List length pages))
    ; The objects, numbered from 1: the catalogue, the page tree, five fonts
    ; and their descriptors, the information, then a page and its content
    ; for each page.
    (def bodies
      (List append
        (list "<</Type/Catalog/Pages 2 0 R>>"
              (Str8 append "<</Type/Pages/Count " (Str8 str count) "/Kids["
                           (Str8 join " " (List map (fn (_ k) (Str8 append (Str8 str (int+ 14 (int* 2 k))) " 0 R")) (List range 0 count)))
                           "]>>"))
        (List flat-map
          (fn (_ f)
            ((fn (_ font)
               (list (Str8 append "<</Type/Font/Subtype/Type1/BaseFont/" (first font) "/Encoding/WinAnsiEncoding/FirstChar 32/LastChar 255/Widths["
                                  (%pw-widths f) "]/FontDescriptor " (Str8 str (int+ 4 (int* 2 f))) " 0 R>>")
                     (Str8 append "<</Type/FontDescriptor/FontName/" (first font) "/Flags " (List ref 1 font) ">>")))
             (List ref f %pw-fonts)))
          (List range 0 5))
        (list (match ((null? title) "<<>>") (#t (Str8 append "<</Title(" (%pw-title title) ")>>"))))
        (List flat-map
          (fn (_ page)
            (list (Str8 append "<</Type/Page/Parent 2 0 R/MediaBox[0 0 612 792]"
                               (match ((str=? (rest page) "") "") (#t (Str8 append "/Annots[" (rest page) "]")))
                               "/Contents "
                               "0 0 R/Resources<</Font<</F0 3 0 R/F1 5 0 R/F2 7 0 R/F3 9 0 R/F4 11 0 R>>>>>>")
                  (Str8 append "<</Length " (Str8 str (Str8 length (first page))) ">>\nstream\n" (first page) "endstream")))
          pages)))
    ; A page names its content, the object after it; the number is known
    ; only here.
    ((fn (self l n text rows)
       (match
         ((null? l)
           ((fn (_ out) (list out 0 (Str8 length out)))
            (Str8 append text "xref\n0 " (Str8 str n) "\n0000000000 65535 f \n" rows
                         "trailer\n<</Size " (Str8 str n) "/Root 1 0 R/Info 13 0 R>>\nstartxref\n"
                         (Str8 str (Str8 length text)) "\n%%EOF\n")))
         (#t (self (rest l) (int+ n 1)
                   (Str8 append text (Str8 str n) " 0 obj\n"
                                (Str8 replace "/Contents 0 0 R" (Str8 append "/Contents " (Str8 str (int+ n 1)) " 0 R") (first l))
                                "\nendobj\n")
                   (Str8 append rows (Str8 pad-left 10 #\0 (Str8 str (Str8 length text))) " 00000 n \n")))))
     bodies 1 "%PDF-1.4\n" "")))

(def-class PdfWrite ()
  (doc "A document as a PDF file: (PdfWrite bytes blocks) sets the document tree (x/codec/document) on US Letter pages in Helvetica and Courier, standard fonts a file need not carry, and answers the file's bytes."
    (example "(List ref 2 (PdfWrite bytes ()))" "6738")
    (see bytes))
  (static
    (method bytes (self (param blocks LIST "A document's blocks")
                        . (param title STRING "Optionally the document's title, for the file's /Info"))
      (doc "The bytes of a PDF that sets the blocks: headings bold at a size for each level, paragraphs broken at spaces and set ragged right, emph oblique and strong bold, code and code blocks in Courier, quotes and list items indented, a rule for a thematic break, a new page when one is full. Text is WinAnsiEncoding, a character outside it a question mark. A link is its text under a link annotation that goes to its destination; an image is its alternative text, a field its value; raw HTML is left out."
        (returns LIST "(BUF START LENGTH): the file")
        (example "(do (import x/codec/pdf-text) (def r (PdfWrite bytes (list (list 'heading 1 (list \"Hi\")) (list 'paragraph (list \"a \" (list 'strong (list \"b\")) \" c\"))) \"T\")) (list (PdfText title (first r) (List ref 2 r)) (PdfText parse (first r) (List ref 2 r))))" "(\"T\" (('heading 1 (\"Hi\")) ('paragraph (\"a \" ('strong (\"b\")) \" c\"))))"))
      (def s (%pw-state))
      (%pw-blocks! s blocks %pw-margin #f)
      (%pw-page! s)
      (%pw-file (List reverse (obj-ref s 3)) (match ((null? title) ()) (#t (first title)))))))

(doc (provide x/codec/pdf-write PdfWrite)
  (example "(do (import x/codec/pdf) (def r (PdfWrite bytes (list (list 'paragraph (list \"one\"))))) (List length (Pdf pages (Pdf open (first r) (List ref 2 r)))))" "1")
  (note "The file is text but for the bytes of characters past ASCII, and holds no NUL, so its buffer is also a string.")
  (see PdfText)
  "A document tree written as a PDF file in the standard fonts, homed on the PdfWrite class.")
