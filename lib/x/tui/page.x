; tui/page.x -- a document laid out for a terminal: wrapped, styled lines.
;
; (Page markdown BLOCKS WIDTH) lays out a document as (Markdown parse)
; answers it, (Page text TEXT WIDTH) plain text, as lines no wider than
; WIDTH.  A line is a list of runs, each (TEXT STYLE LINK): its text, its
; style (x/tui/style) and the number of the link it belongs to, or nil.
; Paragraphs and headings are wrapped at spaces, a word wider than the page
; broken where it runs out; code blocks keep their lines and are clipped
; when drawn.  Emphasis is italic, strong bold, code and links coloured,
; headings bold; block quotes have a bar, list items their markers, and
; blocks a blank line between them, none in a tight list.  An image is its
; alternative text in brackets, linked to the image; raw HTML in a
; paragraph is dropped, an HTML block shown as it is, dim.
;
; A form's field, (field TYPE NAME VALUE ON OPTIONS FORM) as (Html parse)
; answers one, is drawn as lynx draws it, in one piece that never breaks
; across lines: a text field as its value padded with underscores to
; twenty columns (a password's as asterisks), a checkbox as [ ] or [X], a
; radio button as ( ) or (*), a select as its chosen option's label in
; brackets, a submit button as its label (its text, or its value, or
; Submit with neither) in brackets; a hidden field is not drawn.
;
; Links and fields are numbered together from 0 in the order they appear,
; and each is kept as (DESTINATION TITLE SPANS): a link's destination and
; title, or a field's (field ...) inline and nil; SPANS the (LINE COLUMN
; WIDTH) places its text takes, found from the laid-out lines.  (Page
; draw) puts lines on a screen (x/tui/screen), one link shown selected.

(module x/tui/page)
(import x/type/class)
(import x/type/vector)
(import x/codec/utf8 utf8-cp-at utf8-width)
(import x/tui/width char-width text-width)
(import x/tui/style)
(import x/tui/screen Screen screen-put! screen-fill!)

(import x/core/doors char->int int& int+ int< int| obj-make obj-ref obj-set! str-byte-len str-byte-ref str-byte-sub)
(def %pg-cvt (prim-ref (lit convert) (lit to)))
(def %pg-string (Type named STRING))
(def %pg-num (fn (_ n) (%pg-cvt n %pg-string 10)))
(def %pg-vector ((prim-ref (lit type) (lit of)) (Vector make 0 ())))

(def %pg-h1 (Style make (lit (bold underline)) () ()))
(def %pg-h2 (Style make (lit (bold)) () ()))
(def %pg-emph (Style make (lit (italic)) () ()))
(def %pg-strong (Style make (lit (bold)) () ()))
(def %pg-code (Style make () 6 ()))
(def %pg-link (Style make (lit (underline)) 12 ()))
(def %pg-field (Style make (lit (bold)) 12 ()))
(def %pg-dim (Style make (lit (dim)) () ()))
(def %pg-reverse (Style make (lit (reverse)) () ()))
(def %pg-attr-bits 63)

; A vector of the elements of L, read by %pg-at from 0.
(def %pg-vec
  (fn (_ l)
    (def v (obj-make %pg-vector (int+ (%pg-len l) 1)))
    (obj-set! v 0 (%pg-len l))
    ((fn (go l k) (match ((eq? l ()) v) (#t (do (obj-set! v k (first l)) (go (rest l) (int+ k 1)))))) l 1)))
(def %pg-at (fn (_ v k) (obj-ref v (int+ k 1))))
(def %pg-count (fn (_ v) (obj-ref v 0)))
(def %pg-nth (fn (self k l) (match ((= k 0) (first l)) (#t (self (int+ k -1) (rest l))))))
(def %pg-2nd (fn (_ l) (first (rest l))))
(def %pg-3rd (fn (_ l) (first (rest (rest l)))))
(def %pg-4th (fn (_ l) (first (rest (rest (rest l))))))
(def %pg-5th (fn (_ l) (first (rest (rest (rest (rest l)))))))
(def %pg-6th (fn (_ l) (first (rest (rest (rest (rest (rest l))))))))
(def %pg-map (fn (self f l) (match ((eq? l ()) ()) (#t (pair (f (first l)) (self f (rest l)))))))
(def %pg-each (fn (self f l) (match ((eq? l ()) ()) (#t (do (f (first l)) (self f (rest l)))))))
(def %pg-len (fn (self l) (match ((eq? l ()) 0) (#t (int+ 1 (self (rest l)))))))
(def %pg-rev (fn (_ l) (%pg-onto l ())))
(def %pg-onto (fn (self l acc) (match ((eq? l ()) acc) (#t (self (rest l) (pair (first l) acc))))))
(def %pg-append (fn (_ a b) (%pg-onto (%pg-rev a) b)))
(def %pg-repeat (fn (self s n) (match ((int< n 1) "") (#t (%str-concat (list s (self s (int+ n -1))))))))

; INNER's attributes added to OUTER's; INNER's colours where it has them.
(def %pg-merge
  (fn (_ outer inner)
    (def fg (fn (_ s) (int& s 130816)))
    (def bg (fn (_ s) (int& s 66977792)))
    (int| (int| (int& (int| outer inner) %pg-attr-bits)
                    (match ((= (fg inner) 0) (fg outer)) (#t (fg inner))))
            (match ((= (bg inner) 0) (bg outer)) (#t (bg inner))))))

; --- inlines to pieces -----------------------------------------------------
; Inlines become pieces, (TEXT STYLE LINK), and (lit br) for a hard break,
; onto OUT, last first; a link or image is filed in LINKS (a cell holding
; its (DESTINATION TITLE) entries, last first) and numbered.
(def %pg-plain
  (fn (self inl)
    (%str-concat
      (%pg-map (fn (_ x)
                  (match ((str? x) x)
                         ((eq? (first x) (lit code)) (%pg-2nd x))
                         ((match ((eq? (first x) (lit link)) #t) ((eq? (first x) (lit image)) #t) (#t #f))
                           (self (%pg-4th x)))
                         ((match ((eq? (first x) (lit emph)) #t) ((eq? (first x) (lit strong)) #t) (#t #f))
                           (self (%pg-2nd x)))
                         ((match ((eq? (first x) (lit softbreak)) #t) ((eq? (first x) (lit hardbreak)) #t) (#t #f)) " ")
                         (#t "")))
                inl))))
(def %pg-file-link!
  (fn (_ links dest title)
    (%set-first! links (pair (list dest title) (first links)))
    (int+ (%pg-len (first links)) -1)))
; The field F drawn: its text, or nil for a hidden field.
(def %pg-field-width 20)
(def %pg-field-text
  (fn (_ f)
    (def type (%pg-2nd f))
    (def value (%pg-4th f))
    (def padded (fn (_ s) (%str-concat (list s (%pg-repeat "_" (int+ %pg-field-width (- 0 (text-width s))))))))
    ; The label of the option that is the value: a select's chosen one, a
    ; button's text; the value itself with none.
    (def label
      (fn (go opts)
        (match ((eq? opts ()) value)
               ((str=? (first (first opts)) value) (rest (first opts)))
               (#t (go (rest opts))))))
    (match
      ((eq? type (lit hidden)) ())
      ((eq? type (lit checkbox)) (match ((%pg-5th f) "[X]") (#t "[ ]")))
      ((eq? type (lit radio)) (match ((%pg-5th f) "(*)") (#t "( )")))
      ((eq? type (lit select)) (%str-concat (list "[" (label (%pg-6th f)) "]")))
      ((eq? type (lit submit))
        ((fn (_ l) (%str-concat (list "[" (match ((str=? l "") "Submit") (#t l)) "]"))) (label (%pg-6th f))))
      ((eq? type (lit password)) (padded (%pg-repeat "*" (text-width value))))
      (#t (padded (Str8 replace "\n" " " value))))))
(def %pg-pieces
  (fn (self inl style link links out)
    (match
      ((eq? inl ()) out)
      (#t ((fn (_ x)
             (self (rest inl) style link links
               (match
                 ((str? x) (pair (list x style link) out))
                 (#t ((fn (_ t)
                        (match
                          ((eq? t (lit emph)) (self (%pg-2nd x) (%pg-merge style %pg-emph) link links out))
                          ((eq? t (lit strong)) (self (%pg-2nd x) (%pg-merge style %pg-strong) link links out))
                          ((eq? t (lit code)) (pair (list (%pg-2nd x) (%pg-merge style %pg-code) link) out))
                          ((eq? t (lit link))
                            (self (%pg-4th x) (%pg-merge style %pg-link)
                                  (%pg-file-link! links (%pg-2nd x) (%pg-3rd x)) links out))
                          ((eq? t (lit image))
                            ((fn (_ alt)
                               (pair (list (%str-concat (list "[" (match ((str=? alt "") "image") (#t alt)) "]"))
                                           (%pg-merge style %pg-link)
                                           (%pg-file-link! links (%pg-2nd x) (%pg-3rd x)))
                                     out))
                             (%pg-plain (%pg-4th x))))
                          ((eq? t (lit softbreak)) (pair (list " " style link) out))
                          ((eq? t (lit hardbreak)) (pair (lit br) out))
                          ((eq? t (lit field))
                            ((fn (_ shown)
                               (match ((eq? shown ()) out)
                                      (#t (pair (list shown (%pg-merge style %pg-field) (%pg-file-link! links x ()) (lit whole))
                                                out))))
                             (%pg-field-text x)))
                          (#t out)))
                      (first x))))))
           (first inl))))))

; --- pieces to tokens ------------------------------------------------------
; Tokens: (w FRAGMENTS) a word, its pieces in order; (s STYLE LINK) the
; space between two words; (lit br).  OUT last first.  A piece ending in
; (lit whole), a field's, is one fragment whatever it holds.
(def %pg-space
  (fn (_ style link out)
    (match ((match ((eq? out ()) #t) ((eq? (first out) (lit br)) #f) (#t (eq? (first (first out)) (lit s)))) out)
           (#t (pair (list (lit s) style link) out)))))
(def %pg-word (fn (_ frags out) (match ((eq? frags ()) out) (#t (pair (list (lit w) (%pg-rev frags)) out)))))
; Piece TEXT's bytes from I split at spaces: (FRAGS . OUT) after.
(def %pg-split
  (fn (self text style link i from frags out)
    (match
      ((= i (str-byte-len text))
        (pair (match ((= from i) frags) (#t (pair (list (str-byte-sub text from (int+ i (- 0 from))) style link) frags))) out))
      ((= (char->int (str-byte-ref text i)) 32)
        (self text style link (int+ i 1) (int+ i 1) ()
          (%pg-space style link
            (%pg-word (match ((= from i) frags) (#t (pair (list (str-byte-sub text from (int+ i (- 0 from))) style link) frags)))
                      out))))
      (#t (self text style link (int+ i 1) from frags out)))))
(def %pg-tokens
  (fn (self pieces frags out)
    (match
      ((eq? pieces ()) (%pg-rev (%pg-word frags out)))
      ((eq? (first pieces) (lit br)) (self (rest pieces) () (pair (lit br) (%pg-word frags out))))
      ((eq? (rest (rest (rest (first pieces)))) ())
        ((fn (_ p)
           ((fn (_ done) (self (rest pieces) (first done) (rest done)))
            (%pg-split (first p) (%pg-2nd p) (%pg-3rd p) 0 0 frags out)))
         (first pieces)))
      (#t ((fn (_ p) (self (rest pieces) (pair (list (first p) (%pg-2nd p) (%pg-3rd p)) frags) out))
           (first pieces))))))

; --- tokens to lines -------------------------------------------------------
; The first bytes of S, from I, that fit in W columns: their end.
(def %pg-fit
  (fn (self s i w)
    (match ((= i (str-byte-len s)) i)
           ((int< w (char-width (utf8-cp-at s i))) i)
           (#t (self s (int+ i (utf8-width s i)) (int+ w (- 0 (char-width (utf8-cp-at s i)))))))))
(def %pg-frags-width
  (fn (self frags) (match ((eq? frags ()) 0) (#t (int+ (text-width (first (first frags))) (self (rest frags)))))))
; Tokens laid out WIDTH wide: lines, in order.
(def %pg-wrap
  (fn (_ tokens width)
    (def lines ()) (def runs ()) (def col 0) (def gap ())
    (def finish! (fn (_) (set! lines (pair (%pg-rev runs) lines)) (set! runs ()) (set! col 0) (set! gap ())))
    (def run! (fn (_ text style link w) (set! runs (pair (list text style link) runs)) (set! col (int+ col w))))
    ; A fragment wider than what is left of the line, broken where it runs out.
    (def broken! (fn (go f)
      (def s (first f))
      (def e (%pg-fit s 0 (int+ width (- 0 col))))
      (match
        ((= e (str-byte-len s)) (run! s (%pg-2nd f) (%pg-3rd f) (text-width s)))
        ((match ((= e 0) (= col 0)) (#t #f))
          (do (run! (str-byte-sub s 0 (utf8-width s 0)) (%pg-2nd f) (%pg-3rd f) 1)
              (finish!)
              (go (list (str-byte-sub s (utf8-width s 0) (int+ (str-byte-len s) (- 0 (utf8-width s 0)))) (%pg-2nd f) (%pg-3rd f)))))
        (#t (do (match ((int< 0 e) (run! (str-byte-sub s 0 e) (%pg-2nd f) (%pg-3rd f) (text-width (str-byte-sub s 0 e))))
                       (#t ()))
                (finish!)
                (go (list (str-byte-sub s e (int+ (str-byte-len s) (- 0 e))) (%pg-2nd f) (%pg-3rd f))))))))
    (%pg-each
      (fn (_ t)
        (match
          ((eq? t (lit br)) (finish!))
          ((eq? (first t) (lit s)) (match ((int< 0 col) (set! gap t)) (#t ())))
          (#t ((fn (_ frags w)
                 (def spaced (match ((eq? gap ()) 0) (#t 1)))
                 (match ((match ((int< 0 col) (int< width (int+ col (int+ spaced w)))) (#t #f)) (finish!)) (#t ()))
                 (match ((match ((eq? gap ()) #f) (#t (int< 0 col)))
                          (run! " " (%pg-2nd gap) (%pg-3rd gap) 1))
                        (#t ()))
                 (set! gap ())
                 (match ((int< width (int+ col w)) (%pg-each broken! frags))
                        (#t (%pg-each (fn (_ f) (run! (first f) (%pg-2nd f) (%pg-3rd f) (text-width (first f)))) frags))))
               (%pg-2nd t) (%pg-frags-width (%pg-2nd t))))))
      tokens)
    (match ((match ((eq? runs ()) (eq? lines ())) (#t #f)) ()) (#t (finish!)))
    (%pg-rev lines)))
(def %pg-inline-lines
  (fn (_ inl style width links)
    (%pg-wrap (%pg-tokens (%pg-rev (%pg-pieces inl style () links ())) () ()) width)))

; --- text lines ------------------------------------------------------------
; TEXT's lines, tabs to the next stop of four, the last end adding none.
(def %pg-expand
  (fn (self s i col out)
    (match
      ((= i (str-byte-len s)) (bytes->str (%pg-rev out)))
      ((= (char->int (str-byte-ref s i)) 9)
        ((fn (_ n) (self s (int+ i 1) (int+ col n) (%pg-onto (%pg-repeat-list 32 n) out)))
         (- 4 (int& col 3))))
      (#t (self s (int+ i 1)
                (match ((= (int& (char->int (str-byte-ref s i)) 192) 128) col) (#t (int+ col 1)))
                (pair (char->int (str-byte-ref s i)) out))))))
(def %pg-repeat-list (fn (self x n) (match ((int< n 1) ()) (#t (pair x (self x (int+ n -1)))))))
(def %pg-text-lines
  (fn (_ text)
    ((fn (_ ls) (match ((match ((eq? ls ()) #f) (#t (str=? (first (%pg-rev ls)) "")))
                         (%pg-rev (rest (%pg-rev ls))))
                        (#t ls)))
     (%pg-map (fn (_ l) (%pg-expand l 0 0 ())) (Str8 split "\n" text)))))

; Text lines as page lines, each broken where it runs past WIDTH; OUT last
; first.
(def %pg-hard-lines
  (fn (self ls width out)
    (match
      ((eq? ls ()) (%pg-rev out))
      (#t ((fn (_ s)
             ((fn (_ e)
                (match
                  ((= e (str-byte-len s)) (self (rest ls) width (pair (list (list s 0 ())) out)))
                  (#t (self (pair (str-byte-sub s e (int+ (str-byte-len s) (- 0 e))) (rest ls)) width
                            (pair (list (list (str-byte-sub s 0 e) 0 ())) out)))))
              ((fn (_ e) (match ((match ((= e 0) (int< 0 (str-byte-len s))) (#t #f)) (utf8-width s 0)) (#t e)))
               (%pg-fit s 0 width))))
           (first ls))))))

; --- blocks to lines -------------------------------------------------------
; LINES with FIRST's runs before the first and REST's before the others.
(def %pg-prefix
  (fn (_ lines first-runs rest-runs)
    (match ((eq? lines ()) (list first-runs))
           (#t (pair (%pg-append first-runs (first lines))
                     (%pg-map (fn (_ l) (%pg-append rest-runs l)) (rest lines)))))))
(def %pg-bullets (list "•" "◦"))
(def %pg-block
  (fn (self b width depth links)
    (def t (first b))
    (match
      ((eq? t (lit paragraph)) (%pg-inline-lines (%pg-2nd b) 0 width links))
      ((eq? t (lit heading))
        (%pg-inline-lines (%pg-3rd b) (match ((= (%pg-2nd b) 1) %pg-h1) (#t %pg-h2)) width links))
      ((eq? t (lit code-block))
        (%pg-map (fn (_ l) (list (list l %pg-code ()))) (%pg-text-lines (%pg-3rd b))))
      ((eq? t (lit html-block))
        (%pg-map (fn (_ l) (list (list l %pg-dim ()))) (%pg-text-lines (%pg-2nd b))))
      ((eq? t (lit thematic-break)) (list (list (list (%pg-repeat "─" width) %pg-dim ()))))
      ((eq? t (lit block-quote))
        ((fn (_ bar) (%pg-prefix (%pg-blocks (%pg-2nd b) (int+ width -2) depth #f links) bar bar))
         (list (list "│ " %pg-dim ()))))
      ((eq? t (lit list))
        ((fn (go items k out)
           (match
             ((eq? items ()) (%pg-rev out))
             (#t ((fn (_ marker)
                    ((fn (_ mw)
                       ((fn (_ lines)
                          (go (rest items) (int+ k 1)
                              (%pg-onto (%pg-prefix lines (list (list marker 0 ())) (list (list (%pg-repeat " " mw) 0 ())))
                                        (match ((match ((eq? out ()) #t) (#t (%pg-4th b))) out) (#t (pair () out))))))
                        (%pg-blocks (first items) (int+ width (- 0 mw)) (int+ depth 1) (%pg-4th b) links)))
                     (text-width marker)))
                  (match ((%pg-2nd b) (%str-concat (list (%pg-num (int+ (%pg-3rd b) k)) ". ")))
                         (#t (%str-concat (list (%pg-nth (int& depth 1) %pg-bullets) " "))))))))
         (%pg-5th b) 0 ()))
      (#t ()))))
; BLOCKS' lines, a blank line between two blocks unless TIGHT.
(def %pg-blocks
  (fn (self blocks width depth tight links)
    ((fn (go bs out)
       (match ((eq? bs ()) (%pg-rev out))
              (#t (go (rest bs)
                      (%pg-onto (%pg-block (first bs) width depth links)
                                (match ((match ((eq? out ()) #t) (#t tight)) out) (#t (pair () out))))))))
     blocks ())))

; --- pages -----------------------------------------------------------------
; Whether a run of RUNS is in a link.
(def %pg-linked?
  (fn (self runs) (match ((eq? runs ()) #f) ((eq? (%pg-3rd (first runs)) ()) (self (rest runs))) (#t #t))))
; A page is a vector: 0 its lines, 1 its links, 2 its width; lines and
; links vectors.  A link is (DESTINATION TITLE SPANS).
(def %pg-make
  (fn (_ lines links width)
    (def lv (%pg-vec lines))
    (def spans (%pg-vec (%pg-map (fn (_ _) ()) links)))
    ((fn (go i)
       (match
         ((int< i (%pg-count lv))
           (do ((fn (walk runs col)
                  (match ((eq? runs ()) ())
                         (#t ((fn (_ r w)
                                (match ((eq? (%pg-3rd r) ()) ())
                                       (#t ((fn (_ k cur)
                                              (obj-set! spans (int+ k 1)
                                                (match ((match ((eq? cur ()) #f)
                                                               ((= (first (first cur)) i)
                                                                 (= (int+ (%pg-2nd (first cur)) (%pg-3rd (first cur))) col))
                                                               (#t #f))
                                                         (pair (list i (%pg-2nd (first cur)) (int+ (%pg-3rd (first cur)) w))
                                                               (rest cur)))
                                                       (#t (pair (list i col w) cur)))))
                                            (%pg-3rd r) (%pg-at spans (%pg-3rd r)))))
                                (walk (rest runs) (int+ col w)))
                              (first runs) (text-width (first (first runs)))))))
                (match ((%pg-linked? (%pg-at lv i)) (%pg-at lv i)) (#t ())) 0)
               (go (int+ i 1))))
         (#t ())))
     0)
    (def lk ((fn (go ls k out)
               (match ((eq? ls ()) (%pg-rev out))
                      (#t (go (rest ls) (int+ k 1)
                              (pair (list (first (first ls)) (%pg-2nd (first ls)) (%pg-rev (%pg-at spans k))) out)))))
             links 0 ()))
    (def page (obj-make %pg-vector 4))
    (obj-set! page 0 3)
    (obj-set! page 1 lv) (obj-set! page 2 (%pg-vec lk)) (obj-set! page 3 width)
    page))
(def %pg-lines (fn (_ p) (obj-ref p 1)))
(def %pg-links (fn (_ p) (obj-ref p 2)))
(def %pg-line-text (fn (_ p i) (%str-concat (%pg-map first (%pg-at (%pg-lines p) i)))))
; Lines from TOP on SCREEN's rows from ROW0, ROWS of them, link SELECTED
; reversed; rows past the last line blank.
(def %pg-draw
  (fn (_ p screen row0 rows top selected)
    (def lv (%pg-lines p))
    (def cols (Screen cols screen))
    ((fn (go r)
       (match
         ((int< r rows)
           (do (screen-fill! screen (int+ row0 r) 0 cols 0)
               (match
                 ((int< (int+ top r) (%pg-count lv))
                   ((fn (put runs col)
                      (match ((eq? runs ()) ())
                             (#t ((fn (_ run)
                                    (put (rest runs)
                                         (screen-put! screen (int+ row0 r) col (first run)
                                                 (match ((match ((eq? (%pg-3rd run) ()) #f) (#t (= (%pg-3rd run) selected)))
                                                          (int| (%pg-2nd run) %pg-reverse))
                                                        (#t (%pg-2nd run))))))
                                  (first runs)))))
                    (%pg-at lv (int+ top r)) 0))
                 (#t ()))
               (go (int+ r 1))))
         (#t ())))
     0)))

(def-class Page ()
  (doc "A document laid out for a terminal: lines of styled runs no wider than the page, its links and form fields numbered together with the places they take, drawn onto a screen."
    (example "(Page line-text (Page markdown (Markdown parse \"# Hi\\n\\nthere\") 20) 2)" "\"there\"")
    (see markdown) (see text) (see draw))
  (static
    (method markdown (self (param blocks LIST "Blocks, as (Markdown parse) answers them")
                           (param width INTEGER "Columns"))
      (doc "Lay BLOCKS out WIDTH wide: paragraphs and headings wrapped, code kept as it is, quotes barred, list items marked, a blank line between blocks (none in a tight list).  A form's field, as (Html parse) answers one, is drawn as lynx draws it: a text field as its value padded with underscores, a checkbox as [ ] or [X], a radio button as ( ) or (*), a select as its chosen option in brackets, a submit button as its label in brackets."
        (returns VECTOR "The page")
        (example "(Page count (Page markdown (Markdown parse \"a\\n\\n- b\\n- c\") 20))" "4")
        (example "(Page line-text (Page markdown (list (list 'paragraph (list \"Q: \" (list 'field 'text \"q\" \"hi\" #f () ()) \" \" (list 'field 'checkbox \"c\" \"on\" #t () ())))) 40) 0)" "\"Q: hi__________________ [X]\""))
      (def links (pair () ()))
      (def lines (%pg-blocks blocks width 0 #f links))
      (%pg-make lines (%pg-rev (first links)) width))
    (method text (self (param text STRING "Plain text") (param width INTEGER "Columns"))
      (doc "Lay plain TEXT out WIDTH wide: its lines as they are, tabs to stops of four, a line wider than the page broken where it runs out."
        (returns VECTOR "The page")
        (example "(Page line-text (Page text \"abcdef\" 4) 1)" "\"ef\""))
      (%pg-make (%pg-hard-lines (%pg-text-lines text) width ()) () width))
    (method count (self (param page VECTOR "A page"))
      (doc "PAGE's lines." (returns INTEGER "Lines")
        (example "(Page count (Page text \"a\\nb\" 9))" "2"))
      (%pg-count (%pg-lines page)))
    (method width (self (param page VECTOR "A page"))
      (doc "The width PAGE was laid out to." (returns INTEGER "Columns")
        (example "(Page width (Page text \"a\" 9))" "9"))
      (obj-ref page 3))
    (method line (self (param page VECTOR "A page") (param i INTEGER "Line, from 0"))
      (doc "Line I's runs: (TEXT STYLE LINK) each, LINK the link's number or nil."
        (returns LIST "Runs")
        (example "(Page line (Page text \"a\" 9) 0)" "((\"a\" 0 ()))"))
      (%pg-at (%pg-lines page) i))
    (method line-text (self (param page VECTOR "A page") (param i INTEGER "Line, from 0"))
      (doc "Line I's text." (returns STRING "Text")
        (example "(Page line-text (Page text \"a b\" 9) 0)" "\"a b\""))
      (%pg-line-text page i))
    (method links (self (param page VECTOR "A page"))
      (doc "PAGE's links and form fields in order: (DESTINATION TITLE SPANS) each, a field's DESTINATION its (field ...) inline and its TITLE nil, SPANS the (LINE COLUMN WIDTH) places its text takes."
        (returns LIST "Links and fields")
        (example "(Page links (Page markdown (Markdown parse \"see [x](/u)\") 20))" "((\"/u\" () ((0 4 1))))"))
      ((fn (go k out) (match ((int< k 0) out) (#t (go (int+ k -1) (pair (%pg-at (%pg-links page) k) out)))))
       (int+ (%pg-count (%pg-links page)) -1) ()))
    (method draw (self (param page VECTOR "A page") (param screen VECTOR "A screen (x/tui/screen)")
                       (param row INTEGER "The first row to draw on") (param rows INTEGER "Rows to draw")
                       (param top INTEGER "The line on the first row") (param selected ANY "The link shown selected, or nil"))
      (doc "Draw PAGE's lines from TOP on ROWS rows of SCREEN from ROW, link SELECTED reversed; rows past the last line blank."
        (returns ANY "nil")
        (example "(Page draw (Page text \"a\" 9) (Screen make 2 9) 0 2 0 ())" ""))
      (%pg-draw page screen row rows top selected))))

(provide x/tui/page Page)
