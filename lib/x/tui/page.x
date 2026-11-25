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
; blocks a blank line between them, none in a tight list.  A table is a
; grid: its columns parted by a bar, a rule under a header row, its
; columns as wide as their widest cells when they fit and sharing the
; width when they do not, a cell wrapped to its column.  An image is its
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
(import x/tui/screen Screen screen-put! screen-fill! screen-row-cells screen-row!)
(import x/protocol/str/str8 str-find-byte)

(import x/core/doors char->int int& int* int+ int- int/ int< int= int| obj-make obj-ref obj-set! str-byte-len str-byte-ref str-byte-sub)
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
(def %pg-nth (fn (self k l) (match ((int= k 0) (first l)) (#t (self (int+ k -1) (rest l))))))
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
                    (match ((int= (fg inner) 0) (fg outer)) (#t (fg inner))))
            (match ((int= (bg inner) 0) (bg outer)) (#t (bg inner))))))

; --- inlines to pieces -----------------------------------------------------
; Inlines become pieces, (TEXT STYLE LINK), and (lit br) for a hard break,
; onto OUT, last first; a link or image is filed in LINKS (a cell holding
; its (DESTINATION TITLE) entries, last first, and how many) and numbered.
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
    (%set-rest! links (int+ (rest links) 1))
    (int+ (rest links) -1)))
; The field F drawn: its text, or nil for a hidden field.
(def %pg-field-width 20)
(def %pg-field-text
  (fn (_ f)
    (def type (%pg-2nd f))
    (def value (%pg-4th f))
    (def padded (fn (_ s) (%str-concat (list s (%pg-repeat "_" (int+ %pg-field-width (int- 0 (text-width s))))))))
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
; Tokens: (w FRAGMENTS) a word, its pieces in order, each (TEXT STYLE LINK
; WIDTH); (s STYLE LINK) the space between two words; (lit br).  OUT last
; first.  A piece ending in (lit whole), a field's, is one fragment
; whatever it holds.
(def %pg-space
  (fn (_ style link out)
    (match ((match ((eq? out ()) #t) ((eq? (first out) (lit br)) #f) (#t (eq? (first (first out)) (lit s)))) out)
           (#t (pair (list (lit s) style link) out)))))
(def %pg-word (fn (_ frags out) (match ((eq? frags ()) out) (#t (pair (list (lit w) (%pg-rev frags)) out)))))
(def %pg-frag (fn (_ text style link) (list text style link (text-width text))))
; Piece TEXT's bytes from I to N split at spaces: (FRAGS . OUT) after.
(def %pg-split
  (fn (self text style link i n frags out)
    (def at (str-find-byte text 32 i))
    (def e (match ((eq? at ()) n) (#t at)))
    (def word (match ((int= e i) frags) (#t (pair (%pg-frag (str-byte-sub text i (int- e i)) style link) frags))))
    (match ((eq? at ()) (pair word out))
           (#t (self text style link (int+ at 1) n () (%pg-space style link (%pg-word word out)))))))
(def %pg-tokens
  (fn (self pieces frags out)
    (match
      ((eq? pieces ()) (%pg-rev (%pg-word frags out)))
      ((eq? (first pieces) (lit br)) (self (rest pieces) () (pair (lit br) (%pg-word frags out))))
      ((eq? (rest (rest (rest (first pieces)))) ())
        ((fn (_ p)
           ((fn (_ done) (self (rest pieces) (first done) (rest done)))
            (%pg-split (first p) (%pg-2nd p) (%pg-3rd p) 0 (str-byte-len (first p)) frags out)))
         (first pieces)))
      (#t ((fn (_ p) (self (rest pieces) (pair (%pg-frag (first p) (%pg-2nd p) (%pg-3rd p)) frags) out))
           (first pieces))))))

; --- tokens to lines -------------------------------------------------------
; The first bytes of S, from I, that fit in W columns: their end.
(def %pg-fit
  (fn (self s i w)
    (match ((int= i (str-byte-len s)) i)
           ((int< w (char-width (utf8-cp-at s i))) i)
           (#t (self s (int+ i (utf8-width s i)) (int+ w (int- 0 (char-width (utf8-cp-at s i)))))))))
(def %pg-frags-width
  (fn (self frags) (match ((eq? frags ()) 0) (#t (int+ (%pg-4th (first frags)) (self (rest frags)))))))
; Tokens laid out WIDTH wide: lines, in order.
(def %pg-wrap
  (fn (_ tokens width)
    (def lines ()) (def runs ()) (def col 0) (def gap ())
    (def finish! (fn (_) (set! lines (pair (%pg-rev runs) lines)) (set! runs ()) (set! col 0) (set! gap ())))
    (def run! (fn (_ text style link w) (set! runs (pair (list text style link) runs)) (set! col (int+ col w))))
    ; A fragment wider than what is left of the line, broken where it runs out.
    (def broken! (fn (go f)
      (def s (first f))
      (def e (%pg-fit s 0 (int+ width (int- 0 col))))
      (match
        ((int= e (str-byte-len s)) (run! s (%pg-2nd f) (%pg-3rd f) (text-width s)))
        ((match ((int= e 0) (int= col 0)) (#t #f))
          (do (run! (str-byte-sub s 0 (utf8-width s 0)) (%pg-2nd f) (%pg-3rd f) 1)
              (finish!)
              (go (list (str-byte-sub s (utf8-width s 0) (int+ (str-byte-len s) (int- 0 (utf8-width s 0)))) (%pg-2nd f) (%pg-3rd f)))))
        (#t (do (match ((int< 0 e) (run! (str-byte-sub s 0 e) (%pg-2nd f) (%pg-3rd f) (text-width (str-byte-sub s 0 e))))
                       (#t ()))
                (finish!)
                (go (list (str-byte-sub s e (int+ (str-byte-len s) (int- 0 e))) (%pg-2nd f) (%pg-3rd f))))))))
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
                        (#t (%pg-each (fn (_ f) (run! (first f) (%pg-2nd f) (%pg-3rd f) (%pg-4th f))) frags))))
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
      ((int= i (str-byte-len s)) (bytes->str (%pg-rev out)))
      ((int= (char->int (str-byte-ref s i)) 9)
        ((fn (_ n) (self s (int+ i 1) (int+ col n) (%pg-onto (%pg-repeat-list 32 n) out)))
         (int- 4 (int& col 3))))
      (#t (self s (int+ i 1)
                (match ((int= (int& (char->int (str-byte-ref s i)) 192) 128) col) (#t (int+ col 1)))
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
                  ((int= e (str-byte-len s)) (self (rest ls) width (pair (list (list s 0 ())) out)))
                  (#t (self (pair (str-byte-sub s e (int+ (str-byte-len s) (int- 0 e))) (rest ls)) width
                            (pair (list (list (str-byte-sub s 0 e) 0 ())) out)))))
              ((fn (_ e) (match ((match ((int= e 0) (int< 0 (str-byte-len s))) (#t #f)) (utf8-width s 0)) (#t e)))
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

; --- tables ----------------------------------------------------------------
(def %pg-max (fn (_ a b) (match ((int< a b) b) (#t a))))
(def %pg-runs-width
  (fn (self runs) (match ((eq? runs ()) 0) (#t (int+ (text-width (first (first runs))) (self (rest runs)))))))
(def %pg-pad (fn (_ n) (match ((int< n 1) ()) (#t (list (list (%pg-repeat " " n) 0 ()))))))
; The widest line TOKENS make laid out with no limit.
(def %pg-natural
  (fn (_ tokens)
    ((fn (go ls w) (match ((eq? ls ()) w) (#t (go (rest ls) (%pg-max w (%pg-runs-width (first ls)))))))
     (%pg-wrap tokens 1000000) 0)))
; COLS, ((K . NATURAL) ...), given widths that fill AVAIL: a column no wider
; than an even share keeps its natural width, and the rest share what is
; left, the first of them a column more where it does not divide.  OUT
; ((K . WIDTH) ...).
(def %pg-share
  (fn (self cols avail out)
    (match
      ((eq? cols ()) out)
      (#t ((fn (_ share)
             ((fn (_ small)
                (match
                  ((eq? small ())
                    ((fn (go cs extra out)
                       (match ((eq? cs ()) out)
                              (#t (go (rest cs) (int+ extra -1)
                                      (pair (pair (first (first cs)) (match ((int< 0 extra) (int+ share 1)) (#t share))) out)))))
                     cols (int+ avail (int- 0 (int* share (%pg-len cols)))) out))
                  (#t (self ((fn (go cs) (match ((eq? cs ()) ()) ((int< share (rest (first cs))) (pair (first cs) (go (rest cs)))) (#t (go (rest cs)))))
                             cols)
                            (int+ avail (int- 0 ((fn (go cs) (match ((eq? cs ()) 0) (#t (int+ (rest (first cs)) (go (rest cs)))))) small)))
                            (%pg-onto small out)))))
              ((fn (go cs) (match ((eq? cs ()) ()) ((int< share (rest (first cs))) (go (rest cs))) (#t (pair (first cs) (go (rest cs))))))
               cols)))
           (%pg-max 1 (int/ avail (%pg-len cols))))))))
; A cell's line RUNS set W wide by ALIGN; LAST, the row's last cell, adds
; no blanks after.
(def %pg-aligned
  (fn (_ runs w align last)
    (def gap (int+ w (int- 0 (%pg-runs-width runs))))
    (def before (match ((eq? align (lit right)) gap) ((eq? align (lit center)) (int/ gap 2)) (#t 0)))
    (match ((match (last (eq? runs ())) (#t #f)) ())
           (#t (%pg-append (%pg-pad before) (%pg-append runs (match (last ()) (#t (%pg-pad (int+ gap (int- 0 before)))))))))))
(def %pg-sep (list (list " │ " %pg-dim ())))
; A table as a grid: its columns parted by a bar, a rule under a header
; row, a cell's text wrapped to its column.  The columns take their natural
; widths when they fit WIDTH, and share it when they do not.
(def %pg-table
  (fn (_ b width links)
    (def header (%pg-2nd b))
    (def ncols ((fn (go rs n) (match ((eq? rs ()) n) (#t (go (rest rs) (%pg-max n (%pg-len (first rs)))))))
                (%pg-4th b) (%pg-len (%pg-3rd b))))
    (def padded (fn (self l n) (match ((int< n 1) ()) ((eq? l ()) (pair () (self l (int+ n -1)))) (#t (pair (first l) (self (rest l) (int+ n -1)))))))
    (def aligns (padded (%pg-3rd b) ncols))
    ; Each cell's tokens, the links filed in reading order.
    (def rows ())
    ((fn (go rs head)
       (match ((eq? rs ()) ())
              (#t (do ((fn (go2 cs out)
                         (match ((eq? cs ()) (set! rows (pair (%pg-rev out) rows)))
                                (#t (go2 (rest cs)
                                         (pair (%pg-tokens (%pg-rev (%pg-pieces (first cs) (match (head %pg-strong) (#t 0)) () links ())) () ())
                                               out)))))
                       (padded (first rs) ncols) ())
                      (go (rest rs) #f)))))
     (%pg-4th b) header)
    (set! rows (%pg-rev rows))
    (def naturals ((fn (go k) (match ((int= k ncols) ())
                                     (#t (pair ((fn (walk rs w) (match ((eq? rs ()) w) (#t (walk (rest rs) (%pg-max w (%pg-natural (%pg-nth k (first rs))))))))
                                                rows 1)
                                               (go (int+ k 1))))))
                   0))
    (def avail (int+ width (int- 0 (int* 3 (int+ ncols -1)))))
    (def total ((fn (go l) (match ((eq? l ()) 0) (#t (int+ (first l) (go (rest l)))))) naturals))
    (def shared
      (fn (_ given) ((fn (go k) (match ((int= k ncols) ()) (#t (pair (rest (%pg-assq k given)) (go (int+ k 1)))))) 0)))
    (def widths
      (match ((int< avail total)
               (shared (%pg-share ((fn (go l k) (match ((eq? l ()) ()) (#t (pair (pair k (first l)) (go (rest l) (int+ k 1)))))) naturals 0)
                                  avail ())))
             (#t naturals)))
    (def row-lines
      (fn (_ cells)
        (def cell-lines ((fn (go cs ws) (match ((eq? cs ()) ()) (#t (pair (%pg-wrap (first cs) (first ws)) (go (rest cs) (rest ws))))))
                         cells widths))
        (def height (%pg-max 1 ((fn (go l n) (match ((eq? l ()) n) (#t (go (rest l) (%pg-max n (%pg-len (first l))))))) cell-lines 0)))
        ((fn (go i)
           (match ((int= i height) ())
                  (#t (pair ((fn (join ls ws as)
                               ((fn (_ runs)
                                  (match ((eq? (rest ls) ()) runs)
                                         (#t (%pg-append runs (%pg-append %pg-sep (join (rest ls) (rest ws) (rest as)))))))
                                (%pg-aligned (match ((int< i (%pg-len (first ls))) (%pg-nth i (first ls))) (#t ()))
                                             (first ws) (first as) (eq? (rest ls) ()))))
                             cell-lines widths aligns)
                            (go (int+ i 1))))))
         0)))
    (def rule
      (list ((fn (join ws) (match ((eq? (rest ws) ()) (list (%pg-repeat "─" (first ws)) %pg-dim ()))
                                  (#t (list (%str-concat (list (%pg-repeat "─" (first ws)) "─┼─" (first (join (rest ws))))) %pg-dim ()))))
             widths)))
    ((fn (go rs head out)
       (match ((eq? rs ()) (%pg-rev out))
              (#t (go (rest rs) #f
                      ((fn (_ lines) (match (head (pair rule lines)) (#t lines)))
                       (%pg-onto (row-lines (first rs)) out))))))
     rows header ())))
(def %pg-assq (fn (self k l) (match ((eq? l ()) ()) ((int= k (first (first l))) (first l)) (#t (self k (rest l))))))
(def %pg-block
  (fn (self b width depth links)
    (def t (first b))
    (match
      ((eq? t (lit paragraph)) (%pg-inline-lines (%pg-2nd b) 0 width links))
      ((eq? t (lit heading))
        (%pg-inline-lines (%pg-3rd b) (match ((int= (%pg-2nd b) 1) %pg-h1) (#t %pg-h2)) width links))
      ((eq? t (lit code-block))
        (%pg-map (fn (_ l) (list (list l %pg-code ()))) (%pg-text-lines (%pg-3rd b))))
      ((eq? t (lit html-block))
        (%pg-map (fn (_ l) (list (list l %pg-dim ()))) (%pg-text-lines (%pg-2nd b))))
      ((eq? t (lit thematic-break)) (list (list (list (%pg-repeat "─" width) %pg-dim ()))))
      ((eq? t (lit table)) (%pg-table b width links))
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
                        (%pg-blocks (first items) (int+ width (int- 0 mw)) (int+ depth 1) (%pg-4th b) links)))
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
; A page is a vector: 0 its lines, 1 its links, 2 its width, 3 the lines
; drawn (see %pg-cells); lines and
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
                                                               ((int= (first (first cur)) i)
                                                                 (int= (int+ (%pg-2nd (first cur)) (%pg-3rd (first cur))) col))
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
    (def page (obj-make %pg-vector 5))
    (obj-set! page 0 4)
    (obj-set! page 1 lv) (obj-set! page 2 (%pg-vec lk)) (obj-set! page 3 width) (obj-set! page 4 ())
    page))
(def %pg-lines (fn (_ p) (obj-ref p 1)))
(def %pg-links (fn (_ p) (obj-ref p 2)))
(def %pg-line-text (fn (_ p i) (%str-concat (%pg-map first (%pg-at (%pg-lines p) i)))))
; Link K, (DESTINATION TITLE SPANS), or nil past the last; how many links:
; what (Page links) lists, read in place, for x/tui/window to step through.
(def page-link
  (fn (_ p k)
    (match ((int< k 0) ()) ((int< k (%pg-count (%pg-links p))) (%pg-at (%pg-links p) k)) (#t ()))))
(def page-link-count (fn (_ p) (%pg-count (%pg-links p))))
; Whether link K has a run in RUNS.
(def %pg-has-link?
  (fn (self runs k) (match ((eq? runs ()) #f) ((eq? (%pg-3rd (first runs)) ()) (self (rest runs) k))
                           ((int= (%pg-3rd (first runs)) k) #t) (#t (self (rest runs) k)))))
; A page keeps each line it draws as the cells of a screen row COLS wide,
; slot 4 (COLS . CELLS), CELLS a vector a line, nil for one not yet drawn:
; a line drawn again is put back in one copy, where its runs are put a
; character at a time.  A line with the selected link is drawn from its
; runs, its link reversed.
(def %pg-cells
  (fn (_ p cols)
    (def c (obj-ref p 4))
    (match ((match ((eq? c ()) #f) (#t (int= (first c) cols))) (rest c))
           (#t ((fn (_ n)
                  ((fn (_ v)
                     (obj-set! v 0 n)
                     ((fn (go k) (match ((int< n k) ()) (#t (do (obj-set! v k ()) (go (int+ k 1)))))) 1)
                     (obj-set! p 4 (pair cols v))
                     v)
                   (obj-make %pg-vector (int+ n 1))))
                (%pg-count (%pg-lines p)))))))
; RUNS on SCREEN's ROW, COLS wide, link SELECTED reversed.
(def %pg-draw-runs!
  (fn (_ screen row cols runs selected)
    (screen-fill! screen row 0 cols 0)
    ((fn (put runs col)
       (match ((eq? runs ()) ())
              (#t ((fn (_ run)
                     (put (rest runs)
                          (screen-put! screen row col (first run)
                            (match ((match ((eq? (%pg-3rd run) ()) #f) (#t (int= (%pg-3rd run) selected)))
                                     (int| (%pg-2nd run) %pg-reverse))
                                   (#t (%pg-2nd run))))))
                   (first runs)))))
     runs 0)))
; Lines from TOP on SCREEN's rows from ROW0, ROWS of them, link SELECTED
; reversed; rows past the last line blank.
(def %pg-draw
  (fn (_ p screen row0 rows top selected)
    (def lv (%pg-lines p))
    (def cols (Screen cols screen))
    (def cells (%pg-cells p cols))
    ((fn (go r)
       (match
         ((int< r rows)
           (do ((fn (_ row i)
                  (match
                    ((int< i (%pg-count lv))
                      ((fn (_ runs kept)
                         (match
                           ((match ((eq? selected ()) #f) (#t (%pg-has-link? runs selected)))
                             (%pg-draw-runs! screen row cols runs selected))
                           ((eq? kept ())
                             (do (%pg-draw-runs! screen row cols runs ())
                                 (obj-set! cells (int+ i 1) (screen-row-cells screen row))))
                           (#t (screen-row! screen row kept))))
                       (%pg-at lv i) (obj-ref cells (int+ i 1))))
                    (#t (screen-fill! screen row 0 cols 0))))
                (int+ row0 r) (int+ top r))
               (go (int+ r 1))))
         (#t ())))
     0)))

(def-class Page ()
  (doc "A document laid out for a terminal: lines of styled runs no wider than the page, its links and form fields numbered together with the places they take, drawn onto a screen."
    (example "(do (import x/codec/markdown) (Page line-text (Page markdown (Markdown parse \"# Hi\\n\\nthere\") 20) 2))" "\"there\"")
    (see markdown) (see text) (see draw))
  (static
    (method markdown (self (param blocks LIST "Blocks, as (Markdown parse) answers them")
                           (param width INTEGER "Columns"))
      (doc "Lay BLOCKS out WIDTH wide: paragraphs and headings wrapped, code kept as it is, quotes barred, list items marked, a table as a grid, a blank line between blocks (none in a tight list).  A form's field, as (Html parse) answers one, is drawn as lynx draws it: a text field as its value padded with underscores, a checkbox as [ ] or [X], a radio button as ( ) or (*), a select as its chosen option in brackets, a submit button as its label in brackets."
        (returns VECTOR "The page")
        (example "(do (import x/codec/markdown) (Page count (Page markdown (Markdown parse \"a\\n\\n- b\\n- c\") 20)))" "4")
        (example "(Page line-text (Page markdown (list (list 'paragraph (list \"Q: \" (list 'field 'text \"q\" \"hi\" #f () ()) \" \" (list 'field 'checkbox \"c\" \"on\" #t () ())))) 40) 0)" "\"Q: hi__________________ [X]\""))
      (def links (pair () 0))
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
        (example "(do (import x/codec/markdown) (Page links (Page markdown (Markdown parse \"see [x](/u)\") 20)))" "((\"/u\" () ((0 4 1))))"))
      ((fn (go k out) (match ((int< k 0) out) (#t (go (int+ k -1) (pair (%pg-at (%pg-links page) k) out)))))
       (int+ (%pg-count (%pg-links page)) -1) ()))
    (method draw (self (param page VECTOR "A page") (param screen VECTOR "A screen (x/tui/screen)")
                       (param row INTEGER "The first row to draw on") (param rows INTEGER "Rows to draw")
                       (param top INTEGER "The line on the first row") (param selected ANY "The link shown selected, or nil"))
      (doc "Draw PAGE's lines from TOP on ROWS rows of SCREEN from ROW, link SELECTED reversed; rows past the last line blank."
        (returns ANY "nil")
        (example "(Page draw (Page text \"a\" 9) (Screen make 2 9) 0 2 0 ())" ""))
      (%pg-draw page screen row rows top selected))))

(provide x/tui/page Page page-link page-link-count)
