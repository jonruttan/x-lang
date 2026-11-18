; codec/pdf-text.x -- PdfText: a PDF's text as a document.
;
; A PDF page does not hold paragraphs: its content stream places runs of
; glyphs, each a string of codes in a font, at a point.  (PdfText parse)
; answers the document tree (x/codec/document) those runs spell, in three
; steps:
;
;   runs     the content stream's text operators are followed -- the text
;            and graphics matrices, the font and its size, the spacing
;            parameters -- and each string shown becomes a run (X Y SIZE
;            WIDTH TEXT STYLE): where it starts on the page, its font size
;            there, how far it runs, its codes as UTF-8, and its font's
;            style: 1 bold, 2 italic, 4 fixed-width, added together.
;   lines    runs in the order shown that share a baseline are a line, a
;            space put where the gap between two is wider than a kern.
;   blocks   lines are a paragraph until the next starts a new one: it is
;            set lower than the leading, in another size, indented, or its
;            first word would have fitted on the line before.  A line set
;            larger than the body's size is a heading, the largest size
;            level 1.  A word hyphenated at a line's end is joined.
;
; A code is a character through the font's /ToUnicode map; with none, a
; simple font's /Encoding and its /Differences, or the encoding an embedded
; Type 1 font program declares.  Lengths are integers in thousandths of a
; point, multiplied in halves so a product stays inside a 32-bit word.
;
; Not yet here: a composite font with no /ToUnicode, vertical writing, a
; rotated page, text set out of reading order or in columns the producer
; interleaved, tables, lists, links, and inline images' bytes, which are
; passed over as they lex.

(module x/codec/pdf-text)
(import x/type/class)
(import x/core/list)
(import x/type/vector)
(import x/codec/pdf)
(import x/codec/bytes)
(import x/codec/utf8 utf8-encode)
(import x/codec/pdf-glyphs pdf-glyph pdf-encoding)

(import x/core/doors char->int heap-collect int% int& int* int+ int- int/ int< int<< int= int| obj-make obj-ref obj-set! ptr-ref ptr-set! str->ptr str-byte-len str-byte-ref str-byte-sub str-make type-of)

; --- small things -----------------------------------------------------------
(def %pt-vector (type-of (Vector make 0 ())))
(def %pt-node
  (fn (_ n)
    (def v (obj-make %pt-vector (int+ n 1)))
    (obj-set! v 0 n)
    ((fn (go k) (match ((int< 0 k) (do (obj-set! v k ()) (go (int+ k -1)))) (#t ()))) n)
    v))
(def %pt-get (fn (_ v k) (obj-ref v (int+ k 1))))
(def %pt-put! (fn (_ v k x) (obj-set! v (int+ k 1) x)))
(def %pt-size (fn (_ v) (obj-ref v 0)))
(def %pt-u8 (fn (_ p i) (int& (ptr-ref p i 1) 255)))
(def %pt-abs (fn (_ x) (match ((int< x 0) (int- 0 x)) (#t x))))
(def %pt-max (fn (_ a b) (match ((int< a b) b) (#t a))))
(def %pt-tagged? (fn (_ x tag) (match ((pair? x) (eq? (first x) tag)) (#t #f))))
(def %pt-op? (fn (_ x name) (match ((%pt-tagged? x (lit op)) (str=? (first (rest x)) name)) (#t #f))))
(def %pt-name (fn (_ x) (match ((%pt-tagged? x (lit name)) (first (rest x))) (#t ""))))
(def %pt-items (fn (_ x) (match ((%pt-tagged? x (lit array)) (rest x)) (#t ()))))
(def %pt-nth (fn (self l k) (match ((null? l) ()) ((int= k 0) (first l)) (#t (self (rest l) (int- k 1))))))
(def %pt-int (fn (_ x default) (match ((number? x) x) (#t default))))

; A string of the bytes in the list BS.
(def %pt-string
  (fn (_ bs)
    (def n (List length bs))
    (def s (str-make (int+ n 1)))
    (def p (str->ptr s))
    ((fn (self l i) (match ((null? l) (ptr-set! p i 0 1)) (#t (do (ptr-set! p i (first l) 1) (self (rest l) (int+ i 1)))))) bs 0)
    s))
; The character of a code point as UTF-8; a Latin ligature as its letters.
(def %pt-char
  (fn (_ cp)
    (match ((int= cp 64256) "ff") ((int= cp 64257) "fi") ((int= cp 64258) "fl") ((int= cp 64259) "ffi")
           ((int= cp 64260) "ffl") ((int= cp 160) " ") ((int= cp 173) "-")
           (#t (%pt-string (utf8-encode cp))))))

; --- thousandths ------------------------------------------------------------
; A times B, both thousandths, in thousandths: four partial products, none
; wider than the answer.
(def %pt-mul
  (fn (_ a b)
    (def x (%pt-abs a))
    (def y (%pt-abs b))
    (def xh (int/ x 1000))
    (def xl (int% x 1000))
    (def yh (int/ y 1000))
    (def yl (int% y 1000))
    (def v (int+ (int+ (int* (int* xh yh) 1000) (int* xh yl)) (int+ (int* xl yh) (int/ (int* xl yl) 1000))))
    (match ((int< a 0) (match ((int< b 0) v) (#t (int- 0 v)))) ((int< b 0) (int- 0 v)) (#t v))))
; A number object in thousandths: an integer, or (real TEXT) read to three
; places.  Anything else is 0.
(def %pt-milli
  (fn (_ x)
    (match
      ((number? x) (int* x 1000))
      ((%pt-tagged? x (lit real))
        ((fn (_ t)
           (def n (str-byte-len t))
           (def at (fn (_ i) (char->int (str-byte-ref t i))))
           (def neg (match ((int= n 0) #f) (#t (int= (at 0) 45))))
           (def v
             ((fn (self i whole frac places point?)
                (match ((int= i n) (int+ (int* whole 1000) (match ((int= places 0) 0) ((int= places 1) (int* frac 100)) ((int= places 2) (int* frac 10)) (#t frac))))
                       ((int= (at i) 46) (self (int+ i 1) whole frac places #t))
                       ((match ((int< (at i) 48) #t) ((int< 57 (at i)) #t) (#t #f)) (self (int+ i 1) whole frac places point?))
                       (point? (match ((int< places 3) (self (int+ i 1) whole (int+ (int* frac 10) (int- (at i) 48)) (int+ places 1) #t))
                                      (#t (self (int+ i 1) whole frac places #t))))
                       (#t (self (int+ i 1) (int+ (int* whole 10) (int- (at i) 48)) frac places #f))))
              0 0 0 0 #f))
           (match (neg (int- 0 v)) (#t v)))
         (first (rest x))))
      (#t 0))))
; Matrices are (A B C D E F) in thousandths; M then N.
(def %pt-identity (list 1000 0 0 1000 0 0))
(def %pt-concat
  (fn (_ m n)
    ((fn (_ a b c d e f a2 b2 c2 d2 e2 f2)
       (list (int+ (%pt-mul a a2) (%pt-mul b c2)) (int+ (%pt-mul a b2) (%pt-mul b d2))
             (int+ (%pt-mul c a2) (%pt-mul d c2)) (int+ (%pt-mul c b2) (%pt-mul d d2))
             (int+ (int+ (%pt-mul e a2) (%pt-mul f c2)) e2) (int+ (int+ (%pt-mul e b2) (%pt-mul f d2)) f2)))
     (%pt-nth m 0) (%pt-nth m 1) (%pt-nth m 2) (%pt-nth m 3) (%pt-nth m 4) (%pt-nth m 5)
     (%pt-nth n 0) (%pt-nth n 1) (%pt-nth n 2) (%pt-nth n 3) (%pt-nth n 4) (%pt-nth n 5))))
; The matrix six number objects spell, most recent first as an operand
; stack holds them.
(def %pt-matrix
  (fn (_ args)
    (match ((int< (List length args) 6) %pt-identity)
           (#t (List reverse (List map %pt-milli (List take 6 args)))))))

; --- fonts ------------------------------------------------------------------
; A font read is (WIDE? MAP WIDTHS DEFAULT STYLE): whether a code is two
; bytes; a vector from a code to its text, nil for none; a vector from a
; code to its width in thousandths of the font's size, nil for the default.
(def %pt-big (fn (_ p i n) ((fn (self k v) (match ((int< k n) (self (int+ k 1) (int| (int<< v 8) (%pt-u8 p (int+ i k))))) (#t v))) 0 0)))
; The code a string object's bytes spell, most significant first.
(def %pt-code (fn (_ s) (%pt-big (str->ptr (first (rest s))) 0 (first (rest (rest s))))))
; A string object's bytes as UTF-16, most significant byte first, in UTF-8:
; (TEXT . LAST), LAST the last code unit.
(def %pt-utf16
  (fn (_ s add)
    (def p (str->ptr (first (rest s))))
    (def n (first (rest (rest s))))
    ((fn (self i acc)
       (match ((int< (int+ i 1) n)
                ((fn (_ u last?)
                   (match ((match ((int< u 55296) #f) ((int< u 56320) (int< (int+ i 3) n)) (#t #f))
                            ((fn (_ lo)
                               (self (int+ i 4)
                                     (pair (%pt-char (int+ (int+ 65536 (int<< (int- u 55296) 10)) (int+ (int- lo 56320) (match ((int< (int+ i 5) n) 0) (#t add)))))
                                           acc)))
                             (%pt-big p (int+ i 2) 2)))
                          (#t (self (int+ i 2) (pair (%pt-char (int+ u (match (last? add) (#t 0)))) acc)))))
                 (%pt-big p i 2) (match ((int< (int+ i 3) n) #f) (#t #t))))
              (#t (%str-concat (List reverse acc)))))
     0 ())))
; The entries of a /ToUnicode map: ((CODE . TEXT) ...), and whether its
; codes are two bytes.  VALUES is the map's stream as objects.
(def %pt-cmap
  (fn (_ values)
    (def wide #f)
    (def out ())
    (def string? (fn (_ x) (%pt-tagged? x (lit string))))
    ((fn (self l mode)
       (match
         ((null? l) ())
         ((%pt-op? (first l) "begincodespacerange")
           (do (when (match ((null? (rest l)) #f) (#t (string? (first (rest l)))))
                 (set! wide (int< 1 (first (rest (rest (first (rest l))))))))
               (self (rest l) ())))
         ((%pt-op? (first l) "beginbfchar") (self (rest l) (lit char)))
         ((%pt-op? (first l) "beginbfrange") (self (rest l) (lit range)))
         ((%pt-tagged? (first l) (lit op)) (self (rest l) ()))
         ((match ((eq? mode (lit char)) (match ((null? (rest l)) #f) ((string? (first l)) (string? (first (rest l)))) (#t #f))) (#t #f))
           (do (set! out (pair (pair (%pt-code (first l)) (%pt-utf16 (first (rest l)) 0)) out))
               (self (rest (rest l)) mode)))
         ((match ((eq? mode (lit range)) (match ((null? (rest l)) #f) ((null? (rest (rest l))) #f) (#t (string? (first l))))) (#t #f))
           ((fn (_ lo hi dst)
              (match
                ((string? dst)
                  ((fn (each c)
                     (when (match ((int< hi c) #f) ((int< (int+ lo 65535) c) #f) (#t #t))
                       (set! out (pair (pair c (%pt-utf16 dst (int- c lo))) out))
                       (each (int+ c 1))))
                   lo))
                (#t ((fn (each c ds)
                       (unless (null? ds)
                         (when (string? (first ds)) (set! out (pair (pair c (%pt-utf16 (first ds) 0)) out)))
                         (each (int+ c 1) (rest ds))))
                     lo (%pt-items dst))))
              (self (rest (rest (rest l))) mode))
            (%pt-code (first l)) (%pt-code (first (rest l))) (first (rest (rest l)))))
         (#t (self (rest l) mode))))
     values ())
    (pair out wide)))
; A vector from each key of the pairs ES to its value.
(def %pt-table
  (fn (_ es)
    (def most ((fn (self l m) (match ((null? l) m) (#t (self (rest l) (%pt-max m (first (first l))))))) es 0))
    (def v (%pt-node (int+ (match ((int< 65535 most) 65535) (#t most)) 1)))
    ((fn (self l)
       (unless (null? l)
         (when (match ((int< (first (first l)) 0) #f) (#t (int< (first (first l)) (%pt-size v))))
           (%pt-put! v (first (first l)) (rest (first l))))
         (self (rest l))))
     es)
    v))
; The codes an embedded Type 1 font program names, ((CODE . NAME) ...): its
; clear text's dup CODE /NAME put.
(def %pt-builtin
  (fn (_ f font)
    (def file (Pdf lookup f (Pdf lookup f font "FontDescriptor") "FontFile"))
    (match
      ((%pt-tagged? file (lit stream))
        ((fn (_ r)
           (def clear
             ((fn (_ said at)
                (match ((match ((int< 0 said) (int< said (List ref 2 r))) (#t #f)) said)
                       ((null? at) (List ref 2 r))
                       (#t at)))
              (%pt-int (Pdf lookup f file "Length1") 0) (Bytes find r "eexec")))
           ((fn (self l acc)
              (match ((null? l) acc)
                     ((match ((%pt-op? (first l) "dup")
                               (match ((null? (rest l)) #f) ((null? (rest (rest l))) #f)
                                      ((number? (first (rest l))) (%pt-tagged? (first (rest (rest l))) (lit name)))
                                      (#t #f)))
                             (#t #f))
                       (self (rest (rest (rest l))) (pair (pair (first (rest l)) (first (rest (first (rest (rest l)))))) acc)))
                     (#t (self (rest l) acc))))
            (guard (e ()) (Pdf read (first r) 0 clear)) ()))
         (guard (e (list "" 0 0)) (Pdf data f file))))
      (#t ()))))
; A simple font's map from its /Encoding: a named encoding, changed by
; /Differences; with no /Encoding the names its font program gives.
(def %pt-simple-map
  (fn (_ f font)
    (def enc (Pdf lookup f font "Encoding"))
    (def base
      ((fn (_ named)
         (match ((str=? named "") (match ((str=? (%pt-name (Pdf lookup f font "Subtype")) "TrueType") "WinAnsiEncoding") (#t "StandardEncoding")))
                (#t named)))
       (match ((%pt-tagged? enc (lit name)) (%pt-name enc))
              (#t (%pt-name (Pdf lookup f enc "BaseEncoding"))))))
    (def v (%pt-node 256))
    ((fn (self c)
       (when (int< c 256)
         ((fn (_ cp) (unless (null? cp) (%pt-put! v c (%pt-char cp)))) (pdf-encoding base c))
         (self (int+ c 1))))
     0)
    (def name! (fn (_ c name) (when (match ((int< c 0) #f) (#t (int< c 256))) ((fn (_ cp) (unless (null? cp) (%pt-put! v c (%pt-char cp)))) (pdf-glyph name)))))
    (when (null? enc) (List for-each (fn (_ e) (name! (first e) (rest e))) (%pt-builtin f font)))
    ((fn (self l c)
       (unless (null? l)
         (match ((number? (first l)) (self (rest l) (first l)))
                (#t (do (name! c (%pt-name (first l))) (self (rest l) (int+ c 1)))))))
     (%pt-items (Pdf lookup f enc "Differences")) 0)
    v))
; A composite font's widths: /W's CODE [W...] and FIRST LAST W.
(def %pt-wide-widths
  (fn (_ f w)
    (def out ())
    ((fn (self l)
       (match ((null? l) ())
              ((null? (rest l)) ())
              (#t ((fn (_ c second)
                     (match ((%pt-tagged? second (lit array))
                              (do ((fn (each ws k) (unless (null? ws) (set! out (pair (pair k (int/ (%pt-milli (first ws)) 1000)) out)) (each (rest ws) (int+ k 1))))
                                   (rest second) c)
                                  (self (rest (rest l)))))
                            ((null? (rest (rest l))) ())
                            (#t (do ((fn (each k) (when (match ((int< second k) #f) ((int< (int+ c 65535) k) #f) (#t #t))
                                                    (set! out (pair (pair k (int/ (%pt-milli (first (rest (rest l)))) 1000)) out)) (each (int+ k 1))))
                                     c)
                                    (self (rest (rest (rest l))))))))
                   (%pt-int (first l) 0) (Pdf resolve f (first (rest l)))))))
     (%pt-items w))
    (%pt-table out)))
; A font's style from its name: 1 bold, 2 italic, 4 fixed-width, added.
(def %pt-style
  (fn (_ name)
    (def has? (fn (_ part) (not (null? (Str8 index-of part name)))))
    (int+ (match ((has? "Bold") 1) ((has? "bold") 1) ((has? "CMBX") 1) ((has? "Black") 1) ((has? "Heavy") 1) (#t 0))
          (int+ (match ((has? "Italic") 2) ((has? "italic") 2) ((has? "Oblique") 2) ((has? "CMTI") 2) ((has? "CMSL") 2) (#t 0))
                (match ((has? "Courier") 4) ((has? "Mono") 4) ((has? "CMTT") 4) ((has? "Consolas") 4) ((has? "Menlo") 4) (#t 0))))))
(def %pt-font
  (fn (_ f font)
    (def wide? (str=? (%pt-name (Pdf lookup f font "Subtype")) "Type0"))
    (def to-unicode (Pdf lookup f font "ToUnicode"))
    (def cmap
      (match ((%pt-tagged? to-unicode (lit stream))
               (guard (e ()) ((fn (_ r) (%pt-cmap (Pdf read (first r) 0 (int+ (List ref 2 r) 1)))) (Pdf data f to-unicode))))
             (#t ())))
    (def base (%pt-name (Pdf lookup f font "BaseFont")))
    (match
      (wide?
        ((fn (_ sub)
           (list #t (match ((null? cmap) (%pt-node 1)) (#t (%pt-table (first cmap))))
                 (%pt-wide-widths f (Pdf lookup f sub "W"))
                 (%pt-int (Pdf lookup f sub "DW") 1000)
                 (%pt-style base)))
         (first (%pt-items (Pdf lookup f font "DescendantFonts")))))
      (#t
        (list (match ((null? cmap) #f) (#t (rest cmap)))
              (match ((null? cmap) (%pt-simple-map f font)) ((null? (first cmap)) (%pt-simple-map f font)) (#t (%pt-table (first cmap))))
              ((fn (_ from ws)
                 (%pt-table ((fn (self l k acc) (match ((null? l) acc) (#t (self (rest l) (int+ k 1) (pair (pair k (int/ (%pt-milli (Pdf resolve f (first l))) 1000)) acc))))) ws from ())))
               (%pt-int (Pdf lookup f font "FirstChar") 0) (%pt-items (Pdf lookup f font "Widths")))
              (%pt-int (Pdf lookup f (Pdf lookup f font "FontDescriptor") "MissingWidth")
                       (match ((null? (Str8 index-of "Courier" base)) 500) (#t 600)))
              (%pt-style base))))))

; --- runs -------------------------------------------------------------------
; The state a content stream is followed in.
(def %S-CTM 0)
(def %S-TM 1)
(def %S-TLM 2)
(def %S-FONT 3)
(def %S-SIZE 4)
(def %S-TC 5)
(def %S-TW 6)
(def %S-TH 7)
(def %S-TL 8)
(def %S-RISE 9)
(def %S-STACK 10)
(def %S-RUNS 11)
(def %S-FONTS 12)
(def %pt-state
  (fn (_)
    (def s (%pt-node 13))
    (%pt-put! s %S-CTM %pt-identity)
    (%pt-put! s %S-TM %pt-identity)
    (%pt-put! s %S-TLM %pt-identity)
    (%pt-put! s %S-SIZE 0)
    (%pt-put! s %S-TC 0)
    (%pt-put! s %S-TW 0)
    (%pt-put! s %S-TH 1000)
    (%pt-put! s %S-TL 0)
    (%pt-put! s %S-RISE 0)
    s))
; Move the text matrix TX along its own x axis.
(def %pt-advance!
  (fn (_ s tx)
    ((fn (_ m)
       (%pt-put! s %S-TM
         (list (%pt-nth m 0) (%pt-nth m 1) (%pt-nth m 2) (%pt-nth m 3)
               (int+ (%pt-nth m 4) (%pt-mul tx (%pt-nth m 0))) (int+ (%pt-nth m 5) (%pt-mul tx (%pt-nth m 1))))))
     (%pt-get s %S-TM))))
; Show a string object: one run of its codes' text, and the text matrix
; moved past them.
(def %pt-show!
  (fn (_ s str)
    (def font (%pt-get s %S-FONT))
    (unless (null? font)
      (def p (str->ptr (first (rest str))))
      (def n (first (rest (rest str))))
      (def step (match ((first font) 2) (#t 1)))
      (def chars (%pt-nth font 1))
      (def widths (%pt-nth font 2))
      (def size (%pt-get s %S-SIZE))
      (def got
        ((fn (self i texts adv)
           (match ((int< (int+ i (int- step 1)) n)
                    ((fn (_ c)
                       (self (int+ i step)
                             ((fn (_ t) (match ((null? t) texts) (#t (pair t texts))))
                              (match ((int< c (%pt-size chars)) (%pt-get chars c)) (#t ())))
                             (int+ adv
                                   (int+ (int+ (%pt-mul ((fn (_ w) (match ((null? w) (%pt-nth font 3)) (#t w)))
                                                         (match ((int< c (%pt-size widths)) (%pt-get widths c)) (#t ())))
                                                        size)
                                               (%pt-get s %S-TC))
                                         (match ((match ((int= c 32) (int= step 1)) (#t #f)) (%pt-get s %S-TW)) (#t 0))))))
                     (%pt-big p i step)))
                  (#t (pair (%str-concat (List reverse texts)) (%pt-mul adv (%pt-get s %S-TH))))))
         0 () 0))
      (def m (%pt-concat (%pt-get s %S-TM) (%pt-get s %S-CTM)))
      (def sx (%pt-max (%pt-abs (%pt-nth m 0)) (%pt-abs (%pt-nth m 1))))
      (def sy (%pt-max (%pt-abs (%pt-nth m 2)) (%pt-abs (%pt-nth m 3))))
      (unless (str=? (first got) "")
        (%pt-put! s %S-RUNS
          (pair (list (int+ (%pt-nth m 4) (%pt-mul (%pt-get s %S-RISE) (%pt-nth m 2)))
                      (int+ (%pt-nth m 5) (%pt-mul (%pt-get s %S-RISE) (%pt-nth m 3)))
                      (%pt-mul size sy) (%pt-mul (rest got) sx) (first got) (%pt-nth font 4))
                (%pt-get s %S-RUNS))))
      (%pt-advance! s (rest got)))))
; Start the next line: the line matrix moved by TX TY, the text matrix it.
(def %pt-line!
  (fn (_ s tx ty)
    ((fn (_ m) (%pt-put! s %S-TLM m) (%pt-put! s %S-TM m))
     (%pt-concat (list 1000 0 0 1000 tx ty) (%pt-get s %S-TLM)))))
; The font NAME of the resources RES, read once a font object.
(def %pt-font-of
  (fn (_ f s res name)
    (def ref (Pdf lookup f (Pdf lookup f res "Font") name))
    ((fn (_ held)
       (match ((null? held)
                ((fn (_ font)
                   (when (%pt-tagged? ref (lit ref))
                     (%pt-put! s %S-FONTS (pair (pair (first (rest ref)) font) (%pt-get s %S-FONTS))))
                   font)
                 (guard (e ()) (%pt-font f ref))))
              (#t (rest held))))
     (match ((%pt-tagged? ref (lit ref)) (List find (fn (_ e) (int= (first e) (first (rest ref)))) (%pt-get s %S-FONTS)))
            (#t ())))))
; Follow the objects VALUES of a content stream with the resources RES,
; adding runs to the state S.  DEPTH bounds forms inside forms.
(def %pt-run!
  (fn (run f s res values depth)
    (def arg (fn (_ args k) (%pt-nth args k)))
    ; x collects only when asked: every 256 operators here.
    ((fn (self l args ops)
       (unless (null? l)
         ((fn (_ v)
            (match
              ((not (%pt-tagged? v (lit op))) (self (rest l) (pair v args) ops))
              (#t (do
                ((fn (_ op)
                   (match
                     ((str=? op "Tj") (when (%pt-tagged? (arg args 0) (lit string)) (%pt-show! s (arg args 0))))
                     ((str=? op "TJ")
                       (List for-each
                         (fn (_ x)
                           (match ((%pt-tagged? x (lit string)) (%pt-show! s x))
                                  (#t (%pt-advance! s (%pt-mul (int- 0 (%pt-mul (int/ (%pt-milli x) 1000) (%pt-get s %S-SIZE))) (%pt-get s %S-TH))))))
                         (%pt-items (arg args 0))))
                     ((str=? op "Td") (%pt-line! s (%pt-milli (arg args 1)) (%pt-milli (arg args 0))))
                     ((str=? op "TD") (do (%pt-put! s %S-TL (int- 0 (%pt-milli (arg args 0))))
                                          (%pt-line! s (%pt-milli (arg args 1)) (%pt-milli (arg args 0)))))
                     ((str=? op "T*") (%pt-line! s 0 (int- 0 (%pt-get s %S-TL))))
                     ((str=? op "'") (do (%pt-line! s 0 (int- 0 (%pt-get s %S-TL)))
                                         (when (%pt-tagged? (arg args 0) (lit string)) (%pt-show! s (arg args 0)))))
                     ((str=? op "\"") (do (%pt-put! s %S-TW (%pt-milli (arg args 2)))
                                          (%pt-put! s %S-TC (%pt-milli (arg args 1)))
                                          (%pt-line! s 0 (int- 0 (%pt-get s %S-TL)))
                                          (when (%pt-tagged? (arg args 0) (lit string)) (%pt-show! s (arg args 0)))))
                     ((str=? op "Tm") ((fn (_ m) (%pt-put! s %S-TLM m) (%pt-put! s %S-TM m)) (%pt-matrix args)))
                     ((str=? op "Tf") (do (%pt-put! s %S-FONT (%pt-font-of f s res (%pt-name (arg args 1))))
                                          (%pt-put! s %S-SIZE (%pt-milli (arg args 0)))))
                     ((str=? op "BT") (do (%pt-put! s %S-TM %pt-identity) (%pt-put! s %S-TLM %pt-identity)))
                     ((str=? op "Tc") (%pt-put! s %S-TC (%pt-milli (arg args 0))))
                     ((str=? op "Tw") (%pt-put! s %S-TW (%pt-milli (arg args 0))))
                     ((str=? op "Tz") (%pt-put! s %S-TH (int/ (%pt-milli (arg args 0)) 100)))
                     ((str=? op "TL") (%pt-put! s %S-TL (%pt-milli (arg args 0))))
                     ((str=? op "Ts") (%pt-put! s %S-RISE (%pt-milli (arg args 0))))
                     ((str=? op "cm") (%pt-put! s %S-CTM (%pt-concat (%pt-matrix args) (%pt-get s %S-CTM))))
                     ((str=? op "q")
                       (%pt-put! s %S-STACK
                         (pair (List map (fn (_ k) (%pt-get s k)) (list %S-CTM %S-FONT %S-SIZE %S-TC %S-TW %S-TH %S-TL %S-RISE))
                               (%pt-get s %S-STACK))))
                     ((str=? op "Q")
                       (unless (null? (%pt-get s %S-STACK))
                         ((fn (each ks vs) (unless (null? ks) (%pt-put! s (first ks) (first vs)) (each (rest ks) (rest vs))))
                          (list %S-CTM %S-FONT %S-SIZE %S-TC %S-TW %S-TH %S-TL %S-RISE) (first (%pt-get s %S-STACK)))
                         (%pt-put! s %S-STACK (rest (%pt-get s %S-STACK)))))
                     ((str=? op "Do")
                       ((fn (_ form)
                          (when (match ((int< 0 depth) (match ((%pt-tagged? form (lit stream)) (str=? (%pt-name (Pdf lookup f form "Subtype")) "Form")) (#t #f))) (#t #f))
                            ((fn (_ ctm r)
                               (%pt-put! s %S-CTM (%pt-concat (%pt-matrix (List reverse (%pt-items (Pdf lookup f form "Matrix")))) ctm))
                               (run f s ((fn (_ own) (match ((null? own) res) (#t own))) (Pdf lookup f form "Resources"))
                                    (Pdf read (first r) 0 (int+ (List ref 2 r) 1)) (int- depth 1))
                               (%pt-put! s %S-CTM ctm))
                             (%pt-get s %S-CTM) (Pdf data f form))))
                        (Pdf lookup f (Pdf lookup f res "XObject") (%pt-name (arg args 0)))))
                     (#t ())))
                 (first (rest v)))
                (when (int= (int& ops 255) 255) (heap-collect))
                (self (rest l) () (int+ ops 1))))))
          (first l))))
     values () 0)))
; A page's runs, in the order shown.
(def %pt-runs
  (fn (_ f page)
    (def s (%pt-state))
    (def contents (Pdf lookup f page "Contents"))
    (def values
      (List flat-map
        (fn (_ c)
          ((fn (_ stream)
             (match ((%pt-tagged? stream (lit stream))
                      ((fn (_ r) (Pdf read (first r) 0 (int+ (List ref 2 r) 1))) (Pdf data f stream)))
                    (#t ())))
           (Pdf resolve f c)))
        (match ((%pt-tagged? contents (lit array)) (rest contents)) ((null? contents) ()) (#t (list contents)))))
    (%pt-run! f s (Pdf lookup f page "Resources") values 8)
    (List reverse (%pt-get s %S-RUNS))))

; --- lines ------------------------------------------------------------------
; A line is (X Y SIZE END PIECES): where it starts, its baseline, its
; largest font size, where its last run ends, and its pieces in order, each
; (TEXT . STYLE).
(def %pt-last-byte (fn (_ t) ((fn (_ n) (match ((int= n 0) 0) (#t (char->int (str-byte-ref t (int- n 1)))))) (str-byte-len t))))
(def %pt-first-byte (fn (_ t) (match ((int= (str-byte-len t) 0) 0) (#t (char->int (str-byte-ref t 0))))))
; How many spaces TEXT starts with, or ends with when END? is true.
(def %pt-spaces
  (fn (_ t end?)
    (def n (str-byte-len t))
    ((fn (self k)
       (match ((int< k n) (match ((int= (char->int (str-byte-ref t (match (end? (int- (int- n 1) k)) (#t k)))) 32) (self (int+ k 1))) (#t k)))
              (#t k)))
     0)))
; A finished line onto ACC: the spaces at its ends taken off its first and
; last pieces and off its extent, by its mean byte width.  A line of spaces
; alone is dropped.
(def %pt-closed
  (fn (_ x y size end pieces acc)
    (def t (%str-concat (List map first pieces)))
    (def n (str-byte-len t))
    (def lead (%pt-spaces t #f))
    (def trail (%pt-spaces t #t))
    (match
      ((int= lead n) acc)
      (#t (pair
            (list (int+ x (int/ (int* (int- end x) lead) n)) y size (int- end (int/ (int* (int- end x) trail) n))
                  ((fn (self l first?)
                     (match ((null? l) ())
                            (#t ((fn (_ text)
                                   ((fn (_ a)
                                      ((fn (_ b) (pair (pair (str-byte-sub text a (int- b a)) (rest (first l))) (self (rest l) #f)))
                                       (match ((null? (rest l)) (%pt-max a (int- (str-byte-len text) (%pt-spaces text #t)))) (#t (str-byte-len text)))))
                                    (match (first? (%pt-spaces text #f)) (#t 0))))
                                 (first (first l))))))
                   pieces #t))
            acc)))))
(def %pt-lines
  (fn (_ runs)
    ; LINE is (X Y SIZE END PIECES-REVERSED), or nil before the first run.
    (def close (fn (_ line acc) (match ((null? line) acc) (#t (%pt-closed (%pt-nth line 0) (%pt-nth line 1) (%pt-nth line 2) (%pt-nth line 3) (List reverse (%pt-nth line 4)) acc)))))
    ((fn (self l line acc)
       (match
         ((null? l) (List reverse (close line acc)))
         (#t ((fn (_ x y size width text style)
                (match
                  ((match ((null? line) #f)
                          ((int< (int* (%pt-abs (int- y (%pt-nth line 1))) 100) (int* (%pt-max size (%pt-nth line 2)) 35))
                            (int< (int- (%pt-nth line 3) (int* 2 size)) x))
                          (#t #f))
                    ((fn (_ gap pieces)
                       (self (rest l)
                             (list (%pt-nth line 0) (%pt-nth line 1) (%pt-max size (%pt-nth line 2)) (%pt-max (%pt-nth line 3) (int+ x width))
                                   (pair (pair text style)
                                         (match ((match ((int< (int* size 15) (int* gap 100))
                                                          (match ((int= (%pt-last-byte (first (first pieces))) 32) #f) ((int= (%pt-first-byte text) 32) #f) (#t #t)))
                                                         (#t #f))
                                                  (pair (pair " " (rest (first pieces))) pieces))
                                                (#t pieces))))
                             acc))
                     (int- x (%pt-nth line 3)) (%pt-nth line 4)))
                  (#t (self (rest l) (list x y size (int+ x width) (list (pair text style))) (close line acc)))))
              (%pt-nth (first l) 0) (%pt-nth (first l) 1) (%pt-nth (first l) 2) (%pt-nth (first l) 3) (%pt-nth (first l) 4) (%pt-nth (first l) 5)))))
     runs () ())))
; A line's text, its pieces joined.
(def %pt-line-text (fn (_ line) (%str-concat (List map first (%pt-nth line 4)))))
; TEXT with no space at either end.
(def %pt-trim
  (fn (_ t)
    (def n (str-byte-len t))
    (def at (fn (_ i) (char->int (str-byte-ref t i))))
    (def a ((fn (self i) (match ((int< i n) (match ((int= (at i) 32) (self (int+ i 1))) (#t i))) (#t i))) 0))
    (def b ((fn (self j) (match ((int< a j) (match ((int= (at (int- j 1)) 32) (self (int- j 1))) (#t j))) (#t j))) n))
    (str-byte-sub t a (int- b a))))

; --- blocks -----------------------------------------------------------------
; The size most of the text is set in: each line's size, to the half point,
; weighed by its bytes.
(def %pt-body
  (fn (_ lines)
    (def counts
      (List fold
        (fn (_ acc line)
          ((fn (_ key n)
             ((fn (_ held) (match ((null? held) (pair (pair key n) acc)) (#t (do (%set-rest! held (int+ (rest held) n)) acc))))
              (List find (fn (_ e) (int= (first e) key)) acc)))
           (int/ (int+ (%pt-nth line 2) 250) 500) (str-byte-len (%pt-line-text line))))
        () lines))
    (int* 500 (first (List fold (fn (_ best e) (match ((int< (rest best) (rest e)) e) (#t best))) (pair 0 0) counts)))))
(def %pt-heading? (fn (_ line body) (int< (int* body 115) (int* (%pt-nth line 2) 100))))
(def %pt-lower? (fn (_ c) (match ((int< c 97) #f) ((int< 122 c) #f) (#t #t))))
(def %pt-letter? (fn (_ c) (match ((int< c 65) #f) ((int< c 91) #t) ((int< c 97) #f) ((int< c 123) #t) (#t (int< 127 c)))))
; The width the first word of LINE takes, by the line's mean byte width.
(def %pt-first-word
  (fn (_ line)
    (def t (%pt-trim (%pt-line-text line)))
    (def n (str-byte-len t))
    (def w ((fn (_ at) (match ((null? at) n) (#t at))) (Str8 index-of " " t)))
    (match ((int= n 0) 0) (#t (int/ (int* (int- (%pt-nth line 3) (%pt-nth line 0)) w) n)))))
; Whether B starts a new block after A, the last of COUNT lines so far.
; RIGHT is the page's right edge, BODY the body's size.
(def %pt-break?
  (fn (_ a b count right body)
    (def size (%pt-nth a 2))
    (def dy (int- (%pt-nth a 1) (%pt-nth b 1)))
    (match
      ((not (eq? (%pt-heading? a body) (%pt-heading? b body))) #t)
      ((int< (int* size 10) (int* (%pt-abs (int- size (%pt-nth b 2))) 100)) #t)
      ((int< dy 1) #t)
      ((int< (int* size 16) (int* dy 10)) #t)
      ((%pt-heading? a body) #f)
      ((match ((int< 1 count) (int< (int+ (%pt-nth a 0) (int/ size 2)) (%pt-nth b 0))) (#t #f)) #t)
      ((int< (int+ (int+ (%pt-nth a 3) (int/ size 3)) (%pt-first-word b)) right) #t)
      (#t #f))))
; The lines of one page as groups, each the lines of a block in order.
(def %pt-groups
  (fn (_ lines body)
    (def right (List fold (fn (_ m line) (%pt-max m (%pt-nth line 3))) 0 lines))
    ((fn (self l group count acc)
       (match
         ((null? l) (List reverse (match ((null? group) acc) (#t (pair (List reverse group) acc)))))
         ((null? group) (self (rest l) (list (first l)) 1 acc))
         ((%pt-break? (first group) (first l) count right body)
           (self (rest l) (list (first l)) 1 (pair (List reverse group) acc)))
         (#t (self (rest l) (pair (first l) group) (int+ count 1) acc))))
     lines () 0 ())))
; A group's pieces in order, lines joined: a hyphen that ends a line before
; a small letter is dropped and the word joined; else a break marker, a
; piece whose text is nil.
(def %pt-joined
  (fn (_ group)
    ((fn (self l acc)
       (match
         ((null? l) (List reverse acc))
         (#t ((fn (_ pieces next)
                (match
                  ((null? next) (self (rest l) (List append (List reverse pieces) acc)))
                  (#t ((fn (_ last)
                         (def t (%pt-trim (first last)))
                         (def n (str-byte-len t))
                         (match
                           ((match ((int< 1 n)
                                     (match ((int= (%pt-last-byte t) 45)
                                              (match ((%pt-letter? (char->int (str-byte-ref t (int- n 2))))
                                                       (%pt-lower? (%pt-first-byte (%pt-trim (%pt-line-text next)))))
                                                     (#t #f)))
                                            (#t #f)))
                                   (#t #f))
                             (self (rest l) (pair (pair (str-byte-sub t 0 (int- n 1)) (rest last)) (List append (rest (List reverse pieces)) acc))))
                           (#t (self (rest l) (pair (pair () 0) (List append (List reverse pieces) acc))))))
                       (first (List reverse pieces))))))
              (%pt-nth (first l) 4) (match ((null? (rest l)) ()) (#t (first (rest l))))))))
     group ())))
; Pieces as inlines: neighbours of one style joined, a bold piece strong, an
; italic one emph, a break marker a softbreak.
(def %pt-inlines
  (fn (_ pieces)
    (def wrap
      (fn (_ text style)
        (match ((int< 3 style) (list (lit code) text))
               ((int= style 1) (list (lit strong) (list text)))
               ((int= style 2) (list (lit emph) (list text)))
               ((int= style 3) (list (lit strong) (list (list (lit emph) (list text)))))
               (#t text))))
    ((fn (self l text style acc)
       ; A styled piece's space at either end goes beside the node, not in it.
       (def flush
         (fn (_)
           (match ((null? text) acc)
                  ((str=? text "") acc)
                  ((int= style 0) (pair text acc))
                  (#t ((fn (_ inner)
                         (match ((str=? inner "") (pair text acc))
                                (#t ((fn (_ led)
                                       (match ((int= (%pt-last-byte text) 32) (pair " " (pair (wrap inner style) led)))
                                              (#t (pair (wrap inner style) led))))
                                     (match ((int= (%pt-first-byte text) 32) (pair " " acc)) (#t acc))))))
                       (%pt-trim text))))))
       (match
         ((null? l) (List reverse (flush)))
         ((null? (first (first l))) (self (rest l) () 0 (pair (list (lit softbreak)) (flush))))
         ((null? text) (self (rest l) (first (first l)) (rest (first l)) acc))
         ((int= style (rest (first l))) (self (rest l) (%str-concat (list text (first (first l)))) style acc))
         (#t (self (rest l) (first (first l)) (rest (first l)) (flush)))))
     pieces () 0 ())))
; Inlines with strings side by side made one.
(def %pt-merged
  (fn (self l)
    (match ((null? l) ())
           ((null? (rest l)) l)
           ((match ((str? (first l)) (str? (first (rest l)))) (#t #f))
             (self (pair (%str-concat (list (first l) (first (rest l)))) (rest (rest l)))))
           (#t (pair (first l) (self (rest l)))))))
; The heading sizes of the lines, largest first.
(def %pt-heading-sizes
  (fn (_ lines body)
    (def sizes
      (List fold
        (fn (_ acc line)
          ((fn (_ key) (match ((%pt-heading? line body) (match ((List includes? key acc) acc) (#t (pair key acc)))) (#t acc)))
           (int/ (int+ (%pt-nth line 2) 250) 500)))
        () lines))
    ; An insertion sort, largest first: a document has a handful of sizes.
    (List fold
      (fn (_ sorted k)
        ((fn (self l) (match ((null? l) (list k)) ((int< (first l) k) (pair k l)) (#t (pair (first l) (self (rest l)))))) sorted))
      () sizes)))
; The blocks of the pages' lines.
(def %pt-blocks
  (fn (_ pages)
    (def all (List flat-map (fn (_ lines) lines) pages))
    (def body (%pt-body all))
    (def sizes (%pt-heading-sizes all body))
    (def level
      (fn (_ line)
        ((fn (_ at) (match ((null? at) 6) ((int< 5 at) 6) (#t (int+ at 1))))
         (List index-of (int/ (int+ (%pt-nth line 2) 250) 500) sizes))))
    (List flat-map
      (fn (_ lines)
        (List flat-map
          (fn (_ group)
            (match
              ((%pt-heading? (first group) body)
                ((fn (_ text)
                   (match ((str=? text "") ()) (#t (list (list (lit heading) (level (first group)) (list text))))))
                 (%pt-trim (Str8 join " " (List map (fn (_ line) (%pt-trim (%pt-line-text line))) group)))))
              (#t ((fn (_ inlines) (match ((null? inlines) ()) (#t (list (list (lit paragraph) inlines)))))
                   (%pt-merged (%pt-inlines (%pt-joined group)))))))
          (%pt-groups lines body)))
      pages)))

; A text string object in UTF-8: UTF-16 after a byte order mark, else a byte
; a character.
(def %pt-text
  (fn (_ s)
    (def p (str->ptr (first (rest s))))
    (def n (first (rest (rest s))))
    (match ((match ((int< 1 n) (match ((int= (%pt-u8 p 0) 254) (int= (%pt-u8 p 1) 255)) (#t #f))) (#t #f))
             ((fn (self i acc)
                (match ((int< (int+ i 1) n) (self (int+ i 2) (pair (%pt-char (%pt-big p i 2)) acc)))
                       (#t (%str-concat (List reverse acc)))))
              2 ()))
           (#t ((fn (self i acc)
                  (match ((int< i n) (self (int+ i 1) (pair (%pt-char (%pt-u8 p i)) acc)))
                         (#t (%str-concat (List reverse acc)))))
                0 ())))))

(def-class PdfText ()
  (doc "A PDF's text as a document: (PdfText parse bytes length) answers the blocks (x/codec/document) the pages' runs of glyphs spell, headings and paragraphs, lines joined again and bold and italic fonts kept as strong and emph. (PdfText runs) answers one page's runs as they are placed, and (PdfText title) the document's title."
    (sample "(PdfText parse bytes size)" "(('heading 1 (\"1 Hello\")) ('paragraph (\"A paragraph, \" ('softbreak) \"its lines joined.\")))")
    (see parse) (see runs) (see title))
  (static
    (method runs (self (param f OBJECT "An open file, from (Pdf open)")
                       (param page LIST "A page, from (Pdf pages)"))
      (doc "The runs a page's content stream shows, in the order shown, each (X Y SIZE WIDTH TEXT STYLE): where the run starts in thousandths of a point from the page's lower left, its font size there, how far it runs, its text, and its font's style: 1 bold, 2 italic, 4 fixed-width, added together."
        (returns LIST "((X Y SIZE WIDTH TEXT STYLE) ...)")
        (sample "(PdfText runs f (first (Pdf pages f)))" "((72000 720000 12000 27336 \"Hello\" 0))"))
      (%pt-runs f page))
    (method blocks (self (param f OBJECT "An open file, from (Pdf open)"))
      (doc "The file's text as blocks: each page's runs gathered into lines and the lines into headings and paragraphs. A paragraph ends with its page."
        (returns LIST "A document's blocks")
        (sample "(PdfText blocks (Pdf open bytes size))" "what (PdfText parse bytes size) answers"))
      (%pt-blocks
        (List map
          (fn (_ page)
            ((fn (_ lines) (heap-collect) lines) (%pt-lines (%pt-runs f page))))
          (Pdf pages f))))
    (method parse (self (param s STRING "Bytes holding a PDF file")
                        . (param length INTEGER "How many bytes; default s's length to its first NUL"))
      (doc "Read a PDF into blocks: (heading LEVEL INLINES) for a line set larger than the body's size, the largest level 1, and (paragraph INLINES) for the rest, a line end a (softbreak), a bold run (strong INLINES) and an italic one (emph INLINES). Raises a label 'value for a file (Pdf open) refuses."
        (returns LIST "A document's blocks")
        (sample "(PdfText parse bytes size)" "(('heading 1 (\"1 Hello\")) ('paragraph (\"This is a small paragraph\" ('softbreak) \"of text.\")))"))
      (PdfText blocks (Pdf open s (match ((null? length) (str-byte-len s)) (#t (first length))))))
    (method title (self (param s STRING "Bytes holding a PDF file")
                        . (param length INTEGER "How many bytes; default s's length to its first NUL"))
      (doc "The document's title: the /Title of its /Info dictionary, or nil with none or an empty one."
        (returns ANY "The title, or nil")
        (sample "(PdfText title bytes size)" "\"Annual Report\""))
      ((fn (_ f)
         ((fn (_ t) (match ((%pt-tagged? t (lit string)) ((fn (_ text) (match ((str=? text "") ()) (#t text))) (%pt-trim (%pt-text t)))) (#t ())))
          (Pdf lookup f (Pdf lookup f (Pdf trailer f) "Info") "Title")))
       (Pdf open s (match ((null? length) (str-byte-len s)) (#t (first length))))))))

(doc (provide x/codec/pdf-text PdfText)
  (sample "(PdfText parse bytes size)" "a PDF file's headings and paragraphs")
  (note "The blocks are a reading of where glyphs were placed, not a record the file holds: a file whose text was set out of order, or in columns, reads as it was set.")
  (see Pdf)
  "A PDF's text as the document tree: runs of glyphs gathered into lines, and lines into headings and paragraphs, homed on the PdfText class.")
