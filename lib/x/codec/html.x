; codec/html.x -- HTML: a page as the blocks (Markdown parse) answers.
;
; (Html parse TEXT) answers a page as a list of blocks, the same lists
; (Markdown parse) answers, so what lays Markdown out lays HTML out:
;
;   h1 to h6                  (heading LEVEL INLINES)
;   p, and text in no block   (paragraph INLINES)
;   pre                       (code-block INFO TEXT), INFO from a
;                             class="language-NAME" on the pre or its code
;   blockquote                (block-quote BLOCKS)
;   ul, ol                    (list ORDERED? START #t ITEMS), an item a list
;                             of blocks, START an ol's start or 1
;   hr                        (thematic-break)
;   table                     a paragraph a row, its cells parted by " | ",
;                             a th's bold; a caption a paragraph before them
;   dl                        a dt a paragraph, bold; a dd's blocks
;
; and inlines: a (link HREF TITLE INLINES), b and strong (strong INLINES),
; i, em, cite, dfn and var (emph INLINES), code, kbd, samp and tt (code
; TEXT), br (hardbreak), img its alt text.  A form's fields are inlines
; too, each (field TYPE NAME VALUE ON OPTIONS FORM):
;
;   input                     TYPE text, search, password, email, url,
;                             number, hidden, checkbox, radio or submit
;                             (an unknown type is text; a button, reset,
;                             image or file input is nothing), VALUE its
;                             value ("on" for a box, "Submit" for a button)
;   textarea                  TYPE textarea, VALUE its text
;   select                    TYPE select, OPTIONS its options, each
;                             (VALUE . LABEL), VALUE the selected one's
;   button                    TYPE submit, VALUE its value or its text,
;                             OPTIONS its one (VALUE . TEXT) (a button or
;                             reset button is nothing)
;
; NAME is the name attribute or nil, ON whether a checkbox or radio is
; checked, and FORM the form the field is in, (INDEX ACTION METHOD): the
; form's number among the page's forms from 0, its action ("" with none)
; and get or post; nil for a field in no form.  Any other element is its
; content: div and the other sectioning elements part blocks, span and the
; other phrasing elements join inlines.  head, script, style, template and
; iframe are dropped, as comments, doctypes and processing instructions
; are.  (Html title TEXT) answers the <title>'s text, or nil.
;
; The parse is as tolerant as a browser's: tag and attribute names in any
; case, attribute values in either quote or none, p, li, dt, dd, tr, td and
; th closed by what follows them, a close tag with no open element of its
; name ignored, what is still open at the end closed.  Character references
; are x/codec/entity's.  Runs of white space collapse to one space, none at
; the start or end of a block or beside a line break; pre keeps its text.
;
; The scan runs per byte, so it is module functions over primitives bound
; once, and the element tree is raw vectors read by slot, as x/codec/markdown
; is built.

(module x/codec/html)
(import x/type/class)
(import x/type/vector)
(import x/codec/entity entity-decode)

(import x/core/doors char->int int+ int< obj-make obj-ref obj-set! str-byte-len str-byte-ref str-byte-sub)
(def %ht-cvt (prim-ref (lit convert) (lit to)))
(def %ht-integer (Type named INTEGER))
(def %ht-vector ((prim-ref (lit type) (lit of)) (Vector make 0 ())))

; --- bytes -----------------------------------------------------------------
; The byte at I of S as an integer, -1 past either end.
(def %ht-at
  (fn (_ s i)
    (match ((int< i 0) -1) ((int< i (str-byte-len s)) (char->int (str-byte-ref s i))) (#t -1))))
(def %ht-sub (fn (_ s i j) (str-byte-sub s i (- j i))))
(def %ht-white?
  (fn (_ c) (match ((= c 32) #t) ((= c 10) #t) ((= c 9) #t) ((= c 13) #t) ((= c 12) #t) (#t #f))))
(def %ht-digit? (fn (_ c) (match ((int< c #\0) #f) ((int< #\9 c) #f) (#t #t))))
(def %ht-alpha?
  (fn (_ c) (match ((int< c #\A) #f) ((int< #\z c) #f) ((int< c #\[) #t) ((int< c #\a) #f) (#t #t))))
(def %ht-upper? (fn (_ c) (match ((int< c #\A) #f) ((int< #\Z c) #f) (#t #t))))
; Whether C ends a tag or attribute name.
(def %ht-name-end?
  (fn (_ c)
    (match ((= c -1) #t) ((= c #\>) #t) ((= c #\/) #t) ((= c #\=) #t) (#t (%ht-white? c)))))
; I past the bytes of S from I that PRED? holds for; on to the byte B or the end.
(def %ht-skip
  (fn (self pred? s i) (match ((pred? (%ht-at s i)) (self pred? s (int+ i 1))) (#t i))))
(def %ht-upto
  (fn (self s i b)
    (match ((= (%ht-at s i) b) i) ((= (%ht-at s i) -1) i) (#t (self s (int+ i 1) b)))))
; Whether PAT is in S at I, from PAT's byte K; where PAT next starts in S at
; or after I, or -1.
(def %ht-at?
  (fn (self pat s i k)
    (match ((= k (str-byte-len pat)) #t)
           ((= (%ht-at s (int+ i k)) (char->int (str-byte-ref pat k))) (self pat s i (int+ k 1)))
           (#t #f))))
(def %ht-find
  (fn (self pat s i)
    (match ((= (%ht-at s i) -1) -1) ((%ht-at? pat s i 0) i) (#t (self pat s (int+ i 1))))))
; S in lower case; S itself when it has no upper-case letter.
(def %ht-lower
  (fn (_ s)
    ((fn (go i)
       (def c (%ht-at s i))
       (match
         ((= c -1) s)
         ((%ht-upper? c)
           (bytes->str
             ((fn (walk k out)
                (def b (%ht-at s k))
                (match ((= b -1) (%reverse out))
                       ((%ht-upper? b) (walk (int+ k 1) (pair (int+ b 32) out)))
                       (#t (walk (int+ k 1) (pair b out)))))
              0 ())))
         (#t (go (int+ i 1)))))
     0)))
; S without its trailing spaces.
(def %ht-rtrim
  (fn (_ s)
    ((fn (go j) (match ((= (%ht-at s (int+ j -1)) 32) (go (int+ j -1))) ((= j (str-byte-len s)) s) (#t (%ht-sub s 0 j))))
     (str-byte-len s))))
; List helpers: a class send costs hundreds of objects, and the tree pass
; makes one a node.
(def %ht-nth (fn (self k l) (match ((= k 0) (first l)) (#t (self (int+ k -1) (rest l))))))
(def %ht-map (fn (self f l) (match ((eq? l ()) ()) (#t (pair (f (first l)) (self f (rest l)))))))
(def %ht-each (fn (self f l) (match ((eq? l ()) ()) (#t (do (f (first l)) (self f (rest l)))))))
(def %ht-onto (fn (self l acc) (match ((eq? l ()) acc) (#t (self (rest l) (pair (first l) acc))))))
(def %ht-append (fn (_ a b) (%ht-onto (%reverse a) b)))
(def %ht-member?
  (fn (self s l) (match ((eq? l ()) #f) ((str=? s (first l)) #t) (#t (self s (rest l))))))
(def %ht-assoc
  (fn (self k al) (match ((eq? al ()) ()) ((str=? k (first (first al))) (first al)) (#t (self k (rest al))))))

; --- elements --------------------------------------------------------------
(def %ht-void
  (list "area" "base" "br" "col" "embed" "hr" "img" "input" "link" "meta" "param" "source" "track" "wbr"))
; Elements whose content is text to their close tag.
(def %ht-raw (list "script" "style" "textarea" "title" "iframe" "xmp"))
; Elements, and their content, that no block or inline comes from.
(def %ht-dropped
  (list "head" "script" "style" "template" "iframe" "title" "xmp" "object" "datalist" "noframes"))
; What may open inside head; anything else closes it.
(def %ht-head (list "base" "link" "meta" "noscript" "script" "style" "template" "title"))
; Start tags that close an open p, and the elements a p is looked for below.
(def %ht-closes-p
  (list "address" "article" "aside" "blockquote" "center" "dd" "details" "dialog" "dir" "div" "dl" "dt"
        "fieldset" "figcaption" "figure" "footer" "form" "h1" "h2" "h3" "h4" "h5" "h6" "header" "hgroup"
        "hr" "li" "main" "menu" "nav" "ol" "p" "pre" "search" "section" "summary" "table" "ul"))
(def %ht-p-stop (list "html" "table" "td" "th" "caption" "button"))
(def %ht-headings (list "h1" "h2" "h3" "h4" "h5" "h6"))
(def %ht-strongs (list "b" "strong"))
(def %ht-emphs (list "i" "em" "cite" "dfn" "var"))
(def %ht-codes (list "code" "kbd" "samp" "tt"))
; Elements that part blocks: the rest join inlines.
(def %ht-block?
  (fn (_ name)
    (match ((%ht-member? name %ht-closes-p) #t)
           ((%ht-member? name %ht-dropped) #t)
           (#t (%ht-member? name (list "body" "html" "tr" "td" "th" "thead" "tbody" "tfoot" "caption"
                                       "colgroup" "noscript" "legend" "option" "optgroup"))))))

; An element is a vector: 0 its name, 1 its attributes ((NAME . VALUE) ...),
; 2 its children, last first, each a string or an element, 3 its parent, 4
; a form's (INDEX ACTION METHOD), nil on any other element.  (eq? compares
; a vector by its value word, its length: identity is same?.)
(def %ht-node
  (fn (_ name attrs parent)
    (def v (obj-make %ht-vector 6))
    (obj-set! v 0 5) (obj-set! v 1 name) (obj-set! v 2 attrs) (obj-set! v 3 ()) (obj-set! v 4 parent)
    (obj-set! v 5 ())
    v))
(def %ht-name (fn (_ nd) (obj-ref nd 1)))
(def %ht-kids (fn (_ nd) (%reverse (obj-ref nd 3))))
(def %ht-parent (fn (_ nd) (obj-ref nd 4)))
(def %ht-add! (fn (_ nd x) (obj-set! nd 3 (pair x (obj-ref nd 3)))))
; ND's attribute NAME, or nil.
(def %ht-attr
  (fn (_ nd name) ((fn (_ hit) (match ((null? hit) ()) (#t (rest hit)))) (%ht-assoc name (obj-ref nd 2)))))
(def %ht-attr-or (fn (_ nd name default) ((fn (_ v) (match ((null? v) default) (#t v))) (%ht-attr nd name))))
(def %ht-named? (fn (_ x name) (match ((str? x) #f) (#t (str=? (%ht-name x) name)))))

; --- tags ------------------------------------------------------------------
; The attributes from I of S to the tag's >: (ATTRS . END), END past the >.
; A name alone has the value ""; a value is in either quote or none.
(def %ht-attrs
  (fn (go s i attrs)
    (def w (%ht-skip (fn (_ c) (match ((= c #\/) #t) (#t (%ht-white? c)))) s i))
    (def c (%ht-at s w))
    (match
      ((= c -1) (pair (%reverse attrs) w))
      ((= c #\>) (pair (%reverse attrs) (int+ w 1)))
      (#t
        ((fn (_ e)
           (def name (%ht-lower (%ht-sub s w e)))
           (def q (%ht-skip %ht-white? s e))
           (match
             ((= (%ht-at s q) #\=)
               ((fn (_ v)
                  (def d (%ht-at s v))
                  (match
                    ((match ((= d #\") #t) ((= d #\') #t) (#t #f))
                      ((fn (_ z)
                         (go s (match ((= (%ht-at s z) -1) z) (#t (int+ z 1)))
                             (pair (pair name (entity-decode (%ht-sub s (int+ v 1) z))) attrs)))
                       (%ht-upto s (int+ v 1) d)))
                    (#t ((fn (_ z) (go s z (pair (pair name (entity-decode (%ht-sub s v z))) attrs)))
                         (%ht-skip (fn (_ b) (match ((= b -1) #f) ((= b #\>) #f) (#t (not (%ht-white? b))))) s v)))))
                (%ht-skip %ht-white? s (int+ q 1))))
             (#t (go s e (pair (pair name "") attrs)))))
         (%ht-skip (fn (_ b) (not (%ht-name-end? b))) s (int+ w 1)))))))
; I past the > of the tag that ends at or after I.
(def %ht-past (fn (_ s i) ((fn (_ k) (match ((= (%ht-at s k) -1) k) (#t (int+ k 1)))) (%ht-upto s i #\>))))
; The tag at I of S, a <, as (KIND NAME ATTRS END): KIND open, close or
; skip (a comment, doctype or processing instruction); nil when the < is
; text.
(def %ht-tag
  (fn (_ s i)
    (def c (%ht-at s (int+ i 1)))
    (match
      ((%ht-at? "<!--" s i 0)
        (list (lit skip) "" () ((fn (_ k) (match ((int< k 0) (str-byte-len s)) (#t (int+ k 3)))) (%ht-find "-->" s (int+ i 4)))))
      ((match ((= c #\!) #t) (#t (= c #\?))) (list (lit skip) "" () (%ht-past s i)))
      ((match ((= c #\/) (%ht-alpha? (%ht-at s (int+ i 2)))) (#t #f))
        ((fn (_ e) (list (lit close) (%ht-lower (%ht-sub s (int+ i 2) e)) () (%ht-past s e)))
         (%ht-skip (fn (_ b) (not (%ht-name-end? b))) s (int+ i 2))))
      ((%ht-alpha? c)
        ((fn (_ e)
           ((fn (_ a) (list (lit open) (%ht-lower (%ht-sub s (int+ i 1) e)) (first a) (rest a)))
            (%ht-attrs s e ())))
         (%ht-skip (fn (_ b) (not (%ht-name-end? b))) s (int+ i 1))))
      (#t ()))))
; Where the close tag of NAME starts in S at or after I, in any case, or the end.
(def %ht-raw-end
  (fn (go s i name)
    (def k (%ht-upto s i #\<))
    (match
      ((= (%ht-at s k) -1) k)
      ((match ((= (%ht-at s (int+ k 1)) #\/)
                (str=? (%ht-lower (%ht-sub s (int+ k 2) (%ht-skip (fn (_ b) (not (%ht-name-end? b))) s (int+ k 2)))) name))
              (#t #f))
        k)
      (#t (go s (int+ k 1) name)))))

; --- the tree --------------------------------------------------------------
; The outermost open element at or above CUR named in NAMES below one named
; in STOP or the root, or nil; the nearest one named NAME, or nil.
(def %ht-outermost
  (fn (go cur names stop found)
    (match ((null? (%ht-parent cur)) found)
           ((%ht-member? (%ht-name cur) stop) found)
           ((%ht-member? (%ht-name cur) names) (go (%ht-parent cur) names stop cur))
           (#t (go (%ht-parent cur) names stop found)))))
(def %ht-nearest
  (fn (go cur name)
    (match ((null? (%ht-parent cur)) ())
           ((str=? (%ht-name cur) name) cur)
           (#t (go (%ht-parent cur) name)))))
; The form ND is in, (INDEX ACTION METHOD), or nil.
(def %ht-form
  (fn (_ nd) ((fn (_ f) (match ((null? f) ()) (#t (obj-ref f 5)))) (%ht-nearest nd "form"))))
; CUR with the outermost open element named in NAMES closed, when one is
; open below an element named in STOP.
(def %ht-closed
  (fn (_ cur names stop)
    ((fn (_ nd) (match ((null? nd) cur) (#t (%ht-parent nd)))) (%ht-outermost cur names stop ()))))
; What a start tag closes first: (NAMES CLOSES STOP) -- a tag named in NAMES
; closes the nearest open element named in CLOSES, unless one named in STOP
; is nearer.
(def %ht-implied
  (list (list (list "li") (list "li") (list "ul" "ol" "menu" "dir" "table" "td" "th"))
        (list (list "dt" "dd") (list "dt" "dd") (list "dl" "table" "td" "th"))
        (list (list "td" "th") (list "td" "th") (list "tr" "table"))
        (list (list "tr") (list "td" "th" "tr") (list "thead" "tbody" "tfoot" "table"))
        (list (list "thead" "tbody" "tfoot") (list "td" "th" "tr" "thead" "tbody" "tfoot") (list "table"))
        (list (list "option") (list "option") (list "select" "datalist"))))
(def %ht-implied-closed
  (fn (go cur name rules)
    (match ((null? rules) cur)
           ((%ht-member? name (first (first rules)))
             (%ht-closed cur (%ht-nth 1 (first rules)) (%ht-nth 2 (first rules))))
           (#t (go cur name (rest rules))))))
; A start tag NAME with ATTRS under CUR: the open head, p, li, dt, dd, td, th
; or tr it cannot be in closed first, and a heading under a heading; the new
; element, its parent the element it is in.
(def %ht-opened
  (fn (_ cur name attrs)
    (def c1 (match ((%ht-member? name %ht-head) cur) (#t (%ht-closed cur (list "head") ()))))
    (def c2 (match ((%ht-member? name %ht-closes-p) (%ht-closed c1 (list "p") %ht-p-stop)) (#t c1)))
    (def c3 (match ((not (%ht-member? name %ht-headings)) (%ht-implied-closed c2 name %ht-implied))
                   ((%ht-member? (%ht-name c2) %ht-headings) (%ht-parent c2))
                   (#t c2)))
    (def nd (%ht-node name attrs c3))
    (%ht-add! c3 nd)
    nd))
; TEXT's elements under a root: a start tag closes what it cannot be in; a
; close tag closes to the nearest open element of its name, or nothing.
(def %ht-tree
  (fn (_ s)
    (def root (%ht-node "" () ()))
    (def cur root)
    (def forms 0)
    (def text! (fn (_ i j) (unless (= i j) (%ht-add! cur (entity-decode (%ht-sub s i j))))))
    (def raw! (fn (_ nd name i j)
      (unless (match ((str=? name "script") #t) (#t (str=? name "style")))
        (%ht-add! nd (entity-decode (%ht-sub s i j))))))
    (def open! (fn (_ name attrs end)
      (def nd (%ht-opened cur name attrs))
      (when (str=? name "form")
        (do (obj-set! nd 5
              (list forms (%ht-attr-or nd "action" "")
                    (match ((str=? (%ht-lower (%ht-attr-or nd "method" "")) "post") (lit post)) (#t (lit get)))))
            (set! forms (int+ forms 1))))
      (set! cur (%ht-parent nd))
      (match
        ((%ht-member? name %ht-void) end)
        ((%ht-member? name %ht-raw) ((fn (_ e) (raw! nd name end e) e) (%ht-raw-end s end name)))
        (#t (do (set! cur nd) end)))))
    (def close! (fn (_ name)
      (unless (str=? name "br")
        ((fn (_ nd) (unless (null? nd) (set! cur (%ht-parent nd)))) (%ht-nearest cur name)))))
    ((fn (go i from)
       (def k (%ht-upto s i #\<))
       (def tag (match ((= (%ht-at s k) -1) ()) (#t (%ht-tag s k))))
       (match
         ((= (%ht-at s k) -1) (text! from k))
         ((null? tag) (go (int+ k 1) from))
         (#t (do (text! from k)
                 ((fn (_ kind name end)
                    (match
                      ((eq? kind (lit open)) ((fn (_ e) (go e e)) (open! name (%ht-nth 2 tag) end)))
                      ((eq? kind (lit close)) (do (close! name) (go end end)))
                      (#t (go end end))))
                  (first tag) (%ht-nth 1 tag) (%ht-nth 3 tag))))))
     0 0)
    root))

; --- inlines ---------------------------------------------------------------
; S's white space collapsed, a run one space, none at the start when SP (a
; space is pending, or the block begins): (TEXT . SP) after.
(def %ht-collapse
  (fn (_ s sp)
    ((fn (go i out pending)
       (def c (%ht-at s i))
       (match
         ((= c -1) (pair (bytes->str (%reverse out)) pending))
         ((%ht-white? c) (go (int+ i 1) (match (pending out) (#t (pair 32 out))) #t))
         (#t (go (int+ i 1) (pair c out) #f))))
     0 () sp)))
; The text T onto OUT (inlines, last first), joined to a string there.
(def %ht-text-onto
  (fn (_ t out)
    (match ((str=? t "") out)
           ((match ((null? out) #f) (#t (str? (first out)))) (pair (%str-concat (list (first out) t)) (rest out)))
           (#t (pair t out)))))
; INNER (inlines in order) onto OUT, its first text joined to a string there.
(def %ht-splice
  (fn (self inner out)
    (match ((null? inner) out)
           ((str? (first inner)) (self (rest inner) (%ht-text-onto (first inner) out)))
           (#t (self (rest inner) (pair (first inner) out))))))
(def %ht-wrap (fn (_ t inner out) (match ((null? inner) out) (#t (pair (list t inner) out)))))
; OUT without what ends it: a trailing space, inside a trailing link,
; emphasis or strong too, and a trailing line break.
(def %ht-trim-end
  (fn (self out)
    (match
      ((null? out) ())
      ((str? (first out))
        ((fn (_ t) (match ((str=? t "") (self (rest out))) (#t (pair t (rest out))))) (%ht-rtrim (first out))))
      (#t ((fn (_ t)
             (match
               ((eq? t (lit hardbreak)) (self (rest out)))
               ((eq? t (lit code))
                 ((fn (_ c) (match ((str=? c "") (self (rest out))) (#t (pair (list t c) (rest out)))))
                  (%ht-rtrim (%ht-nth 1 (first out)))))
               ((match ((eq? t (lit emph)) #t) (#t (eq? t (lit strong))))
                 ((fn (_ inner) (match ((null? inner) (self (rest out))) (#t (pair (list t inner) (rest out)))))
                  (%reverse (self (%reverse (%ht-nth 1 (first out)))))))
               ((eq? t (lit link))
                 (pair (list t (%ht-nth 1 (first out)) (%ht-nth 2 (first out))
                             (%reverse (self (%reverse (%ht-nth 3 (first out))))))
                       (rest out)))
               (#t out)))
           (first (first out)))))))
; The text of ND's descendants as written, a br a line end, an img its alt.
(def %ht-text
  (fn (self nd)
    (%str-concat
      (%ht-map (fn (_ x)
                  (match ((str? x) x)
                         ((str=? (%ht-name x) "br") "\n")
                         ((str=? (%ht-name x) "img") (%ht-attr-or x "alt" ""))
                         ((%ht-member? (%ht-name x) %ht-dropped) "")
                         (#t (self x))))
               (%ht-kids nd)))))
; --- fields ----------------------------------------------------------------
; A field inline, (field TYPE NAME VALUE ON OPTIONS FORM), for the element X.
(def %ht-field
  (fn (_ type x value on options)
    (list (lit field) type (%ht-attr x "name") value on options (%ht-form x))))
; ND's text collapsed to one line, none at either end.
(def %ht-label (fn (_ nd) (%ht-rtrim (first (%ht-collapse (%ht-text nd) #t)))))
(def %ht-input-types
  (list (pair "text" (lit text)) (pair "search" (lit search)) (pair "password" (lit password))
        (pair "email" (lit email)) (pair "url" (lit url)) (pair "number" (lit number))
        (pair "hidden" (lit hidden)) (pair "checkbox" (lit checkbox)) (pair "radio" (lit radio))
        (pair "submit" (lit submit))))
; An input's field: an unknown type is text; a button, reset, image or file
; input is nil.
(def %ht-input
  (fn (_ x)
    (def kind (%ht-lower (%ht-attr-or x "type" "text")))
    (def hit (%ht-assoc kind %ht-input-types))
    (def type
      (match ((not (null? hit)) (rest hit))
             ((%ht-member? kind (list "button" "reset" "image" "file")) ())
             (#t (lit text))))
    (match
      ((null? type) ())
      ((match ((eq? type (lit checkbox)) #t) (#t (eq? type (lit radio))))
        (%ht-field type x (%ht-attr-or x "value" "on") (not (null? (%ht-attr x "checked"))) ()))
      ((eq? type (lit submit)) (%ht-field type x (%ht-attr-or x "value" "Submit") #f ()))
      (#t (%ht-field type x (%ht-attr-or x "value" "") #f ())))))
; A textarea's field: its text as written, one line end after the tag left off.
(def %ht-textarea
  (fn (_ x)
    (def t (Str8 replace "\r" "" (%ht-text x)))
    (%ht-field (lit textarea) x (match ((= (%ht-at t 0) #\newline) (%ht-sub t 1 (str-byte-len t))) (#t t)) #f ())))
; A select's field: its options, in order, each (VALUE . LABEL), VALUE the
; value attribute or the label; the value selected, else the first's.
(def %ht-select
  (fn (_ x)
    (def chosen ())
    (def options
      ((fn (walk kids out)
         (match
           ((null? kids) out)
           ((str? (first kids)) (walk (rest kids) out))
           ((%ht-named? (first kids) "optgroup") (walk (rest kids) (walk (%ht-kids (first kids)) out)))
           ((%ht-named? (first kids) "option")
             ((fn (_ o label)
                ((fn (_ value)
                   (when (match ((null? chosen) #t) (#t (not (null? (%ht-attr o "selected")))))
                     (set! chosen value))
                   (walk (rest kids) (pair (pair value label) out)))
                 (%ht-attr-or o "value" label)))
              (first kids) (%ht-label (first kids))))
           (#t (walk (rest kids) out))))
       (%ht-kids x) ()))
    (%ht-field (lit select) x (match ((null? chosen) "") (#t chosen)) #f (%reverse options))))
; A button's field: a submit button's value, else its text, with its text
; as the one option's label, since the two differ; a button or reset
; button is nil.
(def %ht-button
  (fn (_ x)
    (def kind (%ht-lower (%ht-attr-or x "type" "submit")))
    (match
      ((not (str=? kind "submit")) ())
      (#t ((fn (_ label)
             ((fn (_ value) (%ht-field (lit submit) x value #f (list (pair value label))))
              (%ht-attr-or x "value" label)))
           ((fn (_ t) (match ((str=? t "") "Submit") (#t t))) (%ht-label x)))))))
; The field F (or nil) onto OUT; after one that is drawn a space is a space.
(def %ht-field-onto
  (fn (_ f sp out)
    (match ((null? f) out)
           (#t (do (unless (eq? (%ht-nth 1 f) (lit hidden)) (%set-first! sp #f))
                   (pair f out))))))

; KIDS, in order, as inlines onto OUT, last first; SP a cell holding whether
; a space is pending.
(def %ht-inlines
  (fn (self kids sp out)
    (def collapsed! (fn (_ s) ((fn (_ r) (%set-first! sp (rest r)) (first r)) (%ht-collapse s (first sp)))))
    (match
      ((null? kids) out)
      (#t (self (rest kids) sp
            ((fn (_ x)
               (match
                 ((str? x) (%ht-text-onto (collapsed! x) out))
                 (#t ((fn (_ name)
                        (match
                          ((%ht-member? name %ht-dropped) out)
                          ((str=? name "br") (do (%set-first! sp #t) (pair (list (lit hardbreak)) (%ht-trim-end out))))
                          ((str=? name "img") (%ht-text-onto (collapsed! (%ht-attr-or x "alt" "")) out))
                          ((str=? name "input") (%ht-field-onto (%ht-input x) sp out))
                          ((str=? name "textarea") (%ht-field-onto (%ht-textarea x) sp out))
                          ((str=? name "select") (%ht-field-onto (%ht-select x) sp out))
                          ((str=? name "button") (%ht-field-onto (%ht-button x) sp out))
                          ((str=? name "a")
                            ((fn (_ href inner)
                               (match ((null? href) (%ht-splice inner out))
                                      (#t (pair (list (lit link) href (%ht-attr x "title") inner) out))))
                             (%ht-attr x "href") (%reverse (self (%ht-kids x) sp ()))))
                          ((%ht-member? name %ht-strongs) (%ht-wrap (lit strong) (%reverse (self (%ht-kids x) sp ())) out))
                          ((%ht-member? name %ht-emphs) (%ht-wrap (lit emph) (%reverse (self (%ht-kids x) sp ())) out))
                          ((%ht-member? name %ht-codes)
                            ((fn (_ t) (match ((str=? t "") out) (#t (pair (list (lit code) t) out))))
                             (collapsed! (%ht-text x))))
                          (#t (self (%ht-kids x) sp out))))
                      (%ht-name x)))))
             (first kids)))))))
; KIDS as a block's inlines, in order: collapsed, none at either end.
(def %ht-phrase (fn (_ kids) (%reverse (%ht-trim-end (%ht-inlines kids (pair #t ()) ())))))

; --- blocks ----------------------------------------------------------------
(def %ht-level (fn (_ name) (- (%ht-at name 1) #\0)))
; An ol's start: its start attribute when that is a number, else 1.
(def %ht-start
  (fn (_ nd)
    (def v (%ht-attr-or nd "start" ""))
    (match ((str=? v "") 1)
           ((= (%ht-skip %ht-digit? v 0) (str-byte-len v)) (%ht-cvt v %ht-integer 10))
           (#t 1))))
; The language of a pre: a class language-NAME on it, else on its code.
(def %ht-info
  (fn (_ nd)
    (def lang (fn (_ x)
      ((fn (go cs)
         (match ((null? cs) ())
                ((Str8 starts? "language-" (first cs)) (Str8 sub 9 (- (Str8 length (first cs)) 9) (first cs)))
                (#t (go (rest cs)))))
       (Str8 split " " (%ht-attr-or x "class" "")))))
    (def own (lang nd))
    (match
      ((null? own)
        ((fn (go kids)
           (match ((null? kids) "")
                  ((%ht-named? (first kids) "code") ((fn (_ l) (match ((null? l) "") (#t l))) (lang (first kids))))
                  (#t (go (rest kids)))))
         (%ht-kids nd)))
      (#t own))))
; A pre's text: as written, one line end after the <pre> left off, one at
; the end.
(def %ht-pre-text
  (fn (_ nd)
    (def t (Str8 replace "\r" "" (%ht-text nd)))
    (def u (match ((= (%ht-at t 0) #\newline) (%ht-sub t 1 (str-byte-len t))) (#t t)))
    (match ((str=? u "") "")
           ((= (%ht-at u (int+ (str-byte-len u) -1)) #\newline) u)
           (#t (%str-concat (list u "\n"))))))
; A list's items: each li's blocks; what is not an li joins the item before it.
(def %ht-list
  (fn (_ nd flow)
    (def ordered? (str=? (%ht-name nd) "ol"))
    (def items
      ((fn (go kids acc)
         (match
           ((null? kids) (%reverse acc))
           ((%ht-named? (first kids) "li") (go (rest kids) (pair (flow (%ht-kids (first kids))) acc)))
           (#t (go (rest kids)
                   ((fn (_ bs)
                      (match ((null? bs) acc)
                             ((null? acc) (list bs))
                             (#t (pair (%ht-append (first acc) bs) (rest acc)))))
                    (flow (list (first kids))))))))
       (%ht-kids nd) ()))
    (match ((null? items) ())
           (#t (list (list (lit list) ordered? (match (ordered? (%ht-start nd)) (#t ())) #t items))))))
; A table's rows as paragraphs, a row's cells parted by " | ", a th's bold;
; its caption a paragraph first.
(def %ht-table
  (fn (_ nd)
    (def rows ())
    (def row! (fn (_ inl) (unless (null? inl) (set! rows (pair (list (lit paragraph) inl) rows)))))
    (def cells (fn (go kids out)
      (match
        ((null? kids) (%reverse out))
        ((match ((%ht-named? (first kids) "td") #t) (#t (%ht-named? (first kids) "th")))
          (go (rest kids)
              ((fn (_ inl)
                 (match ((null? inl) out)
                        (#t (%ht-splice (match ((%ht-named? (first kids) "th") (list (list (lit strong) inl))) (#t inl))
                                        (match ((null? out) out) (#t (%ht-text-onto " | " out)))))))
               (%ht-phrase (%ht-kids (first kids))))))
        (#t (go (rest kids) out)))))
    ((fn (walk kids)
       (%ht-each
         (fn (_ x)
           (unless (str? x)
             (match ((str=? (%ht-name x) "tr") (row! (cells (%ht-kids x) ())))
                    ((str=? (%ht-name x) "caption") (row! (%ht-phrase (%ht-kids x))))
                    ((%ht-member? (%ht-name x) (list "thead" "tbody" "tfoot")) (walk (%ht-kids x)))
                    (#t ()))))
         kids))
     (%ht-kids nd))
    (%reverse rows)))
; KIDS, in order, as blocks: text and phrasing elements between blocks a
; paragraph, each block element its block or blocks.
(def %ht-flow
  (fn (self kids)
    (def out ()) (def phrase ())
    (def flush! (fn (_)
      (unless (null? phrase)
        ((fn (_ inl) (unless (null? inl) (set! out (pair (list (lit paragraph) inl) out))))
         (%ht-phrase (%reverse phrase)))
        (set! phrase ()))))
    (def block! (fn (_ b) (flush!) (set! out (pair b out))))
    (def blocks! (fn (_ bs) (flush!) (set! out (%ht-onto bs out))))
    (def paragraph! (fn (_ inl) (flush!) (unless (null? inl) (set! out (pair (list (lit paragraph) inl) out)))))
    (%ht-each
      (fn (_ x)
        (match
          ((str? x) (set! phrase (pair x phrase)))
          ((not (%ht-block? (%ht-name x))) (set! phrase (pair x phrase)))
          (#t ((fn (_ name)
                 (match
                   ((%ht-member? name %ht-dropped) (flush!))
                   ((%ht-member? name %ht-headings)
                     ((fn (_ inl) (flush!) (unless (null? inl) (set! out (pair (list (lit heading) (%ht-level name) inl) out))))
                      (%ht-phrase (%ht-kids x))))
                   ((str=? name "p") (paragraph! (%ht-phrase (%ht-kids x))))
                   ((str=? name "pre") (block! (list (lit code-block) (%ht-info x) (%ht-pre-text x))))
                   ((str=? name "blockquote") (block! (list (lit block-quote) (self (%ht-kids x)))))
                   ((match ((str=? name "ul") #t) ((str=? name "ol") #t) (#t (str=? name "menu")))
                     (blocks! (%ht-list x self)))
                   ((str=? name "hr") (block! (list (lit thematic-break))))
                   ((str=? name "table") (blocks! (%ht-table x)))
                   ((str=? name "dt")
                     ((fn (_ inl) (flush!) (unless (null? inl) (set! out (pair (list (lit paragraph) (list (list (lit strong) inl))) out))))
                      (%ht-phrase (%ht-kids x))))
                   (#t (blocks! (self (%ht-kids x))))))
               (%ht-name x)))))
      kids)
    (flush!)
    (%reverse out)))

; --- the title -------------------------------------------------------------
; The text of the first <title> in S, collapsed, or nil when there is none
; or it is blank.
(def %ht-title
  (fn (_ s)
    ((fn (go i)
       (def k (%ht-upto s i #\<))
       (match
         ((= (%ht-at s k) -1) ())
         (#t ((fn (_ tag)
                (match
                  ((null? tag) (go (int+ k 1)))
                  ((match ((eq? (first tag) (lit open)) (str=? (%ht-nth 1 tag) "title")) (#t #f))
                    ((fn (_ e)
                       ((fn (_ t) (match ((str=? t "") ()) (#t t)))
                        (%ht-rtrim (first (%ht-collapse (entity-decode (%ht-sub s (%ht-nth 3 tag) e)) #t)))))
                     (%ht-raw-end s (%ht-nth 3 tag) "title")))
                  ((match ((eq? (first tag) (lit open)) (%ht-member? (%ht-nth 1 tag) %ht-raw)) (#t #f))
                    (go (%ht-raw-end s (%ht-nth 3 tag) (%ht-nth 1 tag))))
                  (#t (go (%ht-nth 3 tag)))))
              (%ht-tag s k)))))
     0)))

(def-class Html ()
  (doc "HTML: (Html parse text) -> the page as the blocks (Markdown parse) answers; (Html title text) -> its <title>."
    (example "(Html parse \"<h1>Hi <b>there</b></h1><p>a\\n  b</p>\")" "(('heading 1 (\"Hi \" ('strong (\"there\")))) ('paragraph (\"a b\")))")
    (example "(Html title \"<head><title> A &amp; B </title></head>\")" "\"A & B\"")
    (see parse) (see title))
  (static
    (method parse (self (param text STRING "HTML text"))
      (doc "Parse HTML into a list of blocks as (Markdown parse) answers them: (heading LEVEL INLINES), (paragraph INLINES), (code-block INFO TEXT), (block-quote BLOCKS), (list ORDERED? START TIGHT? ITEMS) with each item a list of blocks, (thematic-break); a table a paragraph a row.  Inlines are strings and (emph INLINES), (strong INLINES), (code TEXT), (link HREF TITLE INLINES), (hardbreak), and a form's fields, (field TYPE NAME VALUE ON OPTIONS FORM): TYPE text, search, password, email, url, number, hidden, textarea, checkbox, radio, select or submit, ON whether a box is checked, OPTIONS a select's (VALUE . LABEL) options or a button element's one, FORM the form's (INDEX ACTION METHOD) or nil.  Tolerant of unclosed p, li, td and th, attributes in either quote or none, and names in any case; head, script, style and comments are dropped, entities decoded, white space collapsed."
        (returns LIST "The page's blocks")
        (example "(Html parse \"<UL><li>one<li><a href=/u title='t'>two</a></UL>\")" "(('list #f () #t ((('paragraph (\"one\"))) (('paragraph (('link \"/u\" \"t\" (\"two\"))))))))")
        (example "(Html parse \"<pre>\\nx &lt; y\\n</pre><hr><blockquote>q</blockquote>\")" "(('code-block \"\" \"x < y\\n\") ('thematic-break) ('block-quote (('paragraph (\"q\")))))")
        (example "(Html parse \"<form action=/s><input name=q> <input type=submit value=Go></form>\")" "(('paragraph (('field 'text \"q\" \"\" #f () (0 \"/s\" 'get)) \" \" ('field 'submit () \"Go\" #f () (0 \"/s\" 'get)))))"))
      (%ht-flow (%ht-kids (%ht-tree text))))
    (method title (self (param text STRING "HTML text"))
      (doc "The text of the page's <title>, its white space collapsed, or nil when it has none."
        (returns ANY "The title, or nil")
        (example "(Html title \"<title>One\\n two</title>\")" "\"One two\"")
        (example "(Html title \"<p>no title\")" ""))
      (%ht-title text))))

(provide x/codec/html Html)
