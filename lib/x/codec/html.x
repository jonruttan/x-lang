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
;   table                     (table HEADER? ALIGNS ROWS), a row a list of
;                             cells, a cell its inlines; a caption a
;                             paragraph before it
;   dl                        a dt a paragraph, bold; a dd's blocks
;
; and inlines: a (link HREF TITLE INLINES), b and strong (strong INLINES),
; i, em, cite, dfn and var (emph INLINES), code, kbd, samp and tt (code
; TEXT), br (hardbreak), img its alt text.  A form's fields are inlines
; too, each (field TYPE NAME VALUE ON OPTIONS FORM):
;
;   input                     TYPE text, search, password, email, url,
;                             number, hidden, checkbox, radio, file or
;                             submit (an unknown type is text; a button,
;                             reset or image input is nothing), VALUE its
;                             value ("on" for a box, "Submit" for a button,
;                             "" for a file, whose value a page cannot set)
;   textarea                  TYPE textarea, VALUE its text
;   select                    TYPE select, OPTIONS its options, each
;                             (VALUE . LABEL), VALUE the selected one's
;   button                    TYPE submit, VALUE its value or its text,
;                             OPTIONS its one (VALUE . TEXT) (a button or
;                             reset button is nothing)
;
; NAME is the name attribute or nil, ON whether a checkbox or radio is
; checked, and FORM the form the field is in, (INDEX ACTION METHOD
; ENCODING): the form's number among the page's forms from 0, its action
; ("" with none), get or post, and multipart when its enctype is
; multipart/form-data, else urlencoded; nil for a field in no form.  Any other element is its
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

(import x/protocol/str/str8 str-find-byte)
(import x/core/doors char->int heap-collect int& int* int+ int- int< int= int| obj-make obj-ref obj-same? obj-set! str->sym str-byte-len str-byte-ref str-byte-sub)
(def %ht-cvt (prim-ref (lit convert) (lit to)))
(def %ht-integer (Type named INTEGER))
(def %ht-vector ((prim-ref (lit type) (lit of)) (Vector make 0 ())))

; --- bytes -----------------------------------------------------------------
; A string's length is a strlen, a walk of the whole string, so the page
; being read keeps its length here: slot 1 the text, 2 its length, set as
; a parse or a title begins.  Any other string's is asked for.
(def %ht-doc (obj-make %ht-vector 3))
(obj-set! %ht-doc 0 2)
; F's answer for S, S's length held while F reads it.
(def %ht-reading
  (fn (_ s f)
    (obj-set! %ht-doc 1 s) (obj-set! %ht-doc 2 (str-byte-len s))
    ((fn (_ r) (obj-set! %ht-doc 1 ()) r) (f s))))
(def %ht-size
  (fn (_ s) (match ((obj-same? s (obj-ref %ht-doc 1)) (obj-ref %ht-doc 2)) (#t (str-byte-len s)))))
; The byte at I of S as an integer, -1 past either end.
(def %ht-at
  (fn (_ s i)
    (match ((int< i 0) -1)
           ((int< i (match ((obj-same? s (obj-ref %ht-doc 1)) (obj-ref %ht-doc 2)) (#t (str-byte-len s))))
             (char->int (str-byte-ref s i)))
           (#t -1))))
(def %ht-sub (fn (_ s i j) (str-byte-sub s i (int- j i))))
(def %ht-white?
  (fn (_ c) (match ((int= c 32) #t) ((int= c 10) #t) ((int= c 9) #t) ((int= c 13) #t) ((int= c 12) #t) (#t #f))))
(def %ht-digit? (fn (_ c) (match ((int< c #\0) #f) ((int< #\9 c) #f) (#t #t))))
(def %ht-alpha?
  (fn (_ c) (match ((int< c #\A) #f) ((int< #\z c) #f) ((int< c #\[) #t) ((int< c #\a) #f) (#t #t))))
(def %ht-upper? (fn (_ c) (match ((int< c #\A) #f) ((int< #\Z c) #f) (#t #t))))
; Where the tag or attribute name in S from I ends: at >, /, =, white
; space or the end.  It reads the bytes itself, a byte past > in one
; comparison: a name is read for every tag and every attribute.
(def %ht-name-end
  (fn (go s i)
    (def b (char->int (str-byte-ref s i)))
    (match ((int< 62 b) (go s (int+ i 1)))
           ((int= b 62) i) ((int= b 47) i) ((int= b 61) i)
           ((int< 32 b) (go s (int+ i 1)))
           ((int= b 0) i)
           ((%ht-white? b) i)
           (#t (go s (int+ i 1))))))
; I past the bytes of S from I that PRED? holds for; on to the byte B, an
; integer, or the end.
(def %ht-lt (char->int #\<))
(def %ht-gt (char->int #\>))
(def %ht-skip
  (fn (self pred? s i) (match ((pred? (%ht-at s i)) (self pred? s (int+ i 1))) (#t i))))
(def %ht-upto
  (fn (_ s i b)
    (match ((int< i 0) i)
           ((int< i (%ht-size s)) ((fn (_ k) (match ((eq? k ()) (%ht-size s)) (#t k))) (str-find-byte s b i)))
           (#t i))))
; Whether PAT is in S at I, from PAT's byte K; where PAT next starts in S at
; or after I, or -1.
(def %ht-at?
  (fn (self pat s i k)
    (match ((int= k (str-byte-len pat)) #t)
           ((int= (%ht-at s (int+ i k)) (char->int (str-byte-ref pat k))) (self pat s i (int+ k 1)))
           (#t #f))))
(def %ht-find
  (fn (self pat s i)
    ((fn (_ k)
       (match ((int= (%ht-at s k) -1) -1) ((%ht-at? pat s k 0) k) (#t (self pat s (int+ k 1)))))
     (%ht-upto s i (char->int (str-byte-ref pat 0))))))
; S in lower case; S itself when it has no upper-case letter.
(def %ht-lower
  (fn (_ s)
    ((fn (go i)
       (def c (char->int (str-byte-ref s i)))
       (match
         ((int< 90 c) (go (int+ i 1)))
         ((int= c 0) s)
         ((%ht-upper? c)
           (bytes->str
             ((fn (walk k out)
                (def b (%ht-at s k))
                (match ((int= b -1) (%reverse out))
                       ((%ht-upper? b) (walk (int+ k 1) (pair (int+ b 32) out)))
                       (#t (walk (int+ k 1) (pair b out)))))
              0 ())))
         (#t (go (int+ i 1)))))
     0)))
; S without its trailing spaces.
(def %ht-rtrim
  (fn (_ s)
    ((fn (go j) (match ((int= (%ht-at s (int+ j -1)) 32) (go (int+ j -1))) ((int= j (str-byte-len s)) s) (#t (%ht-sub s 0 j))))
     (str-byte-len s))))
; List helpers: a class send costs hundreds of objects, and the tree pass
; makes one a node.
(def %ht-nth (fn (self k l) (match ((int= k 0) (first l)) (#t (self (int+ k -1) (rest l))))))
(def %ht-map (fn (self f l) (match ((eq? l ()) ()) (#t (pair (f (first l)) (self f (rest l)))))))
(def %ht-each (fn (self f l) (match ((eq? l ()) ()) (#t (do (f (first l)) (self f (rest l)))))))
(def %ht-onto (fn (self l acc) (match ((eq? l ()) acc) (#t (self (rest l) (pair (first l) acc))))))
(def %ht-append (fn (_ a b) (%ht-onto (%reverse a) b)))
; Names are compared a first byte before the whole: most names asked about
; are not the one compared, and differ there.
(def %ht-member?
  (fn (self s l)
    (match ((eq? l ()) #f)
           ((match ((int= (str-byte-ref s 0) (str-byte-ref (first l) 0)) (str=? s (first l))) (#t #f)) #t)
           (#t (self s (rest l))))))
(def %ht-memq? (fn (self x l) (match ((eq? l ()) #f) ((eq? x (first l)) #t) (#t (self x (rest l))))))
(def %ht-assoc
  (fn (self k al) (match ((eq? al ()) ()) ((str=? k (first (first al))) (first al)) (#t (self k (rest al))))))

; --- elements --------------------------------------------------------------
; A name the parse knows is a symbol, and the sets it is in are the bits of
; a number kept with it, so a tag's name is looked up once, as it is read,
; and whether it is in a set is an int&.  Any other name stays its lowered
; string: a page's names are not interned, since a symbol is never freed.
(def %ht-void 1)
; Elements whose content is text to their close tag.
(def %ht-raw 2)
; Elements, and their content, that no block or inline comes from.
(def %ht-dropped 4)
; What may open inside head; anything else closes it.
(def %ht-head 8)
; Start tags that close an open p, and the elements a p is looked for below.
(def %ht-closes-p 16)
(def %ht-p-stop 32)
(def %ht-headings 64)
(def %ht-strongs 128)
(def %ht-emphs 256)
(def %ht-codes 512)
(def %ht-parts 1024)
; The names a rule of %ht-implied is for, and every name the parse knows.
(def %ht-implied-names 2048)
(def %ht-known 4096)
; Elements that part blocks: the rest join inlines.
(def %ht-blocks (int| %ht-closes-p (int| %ht-dropped %ht-parts)))
(def %ht-in? (fn (_ flags set) (match ((int= (int& flags set) 0) #f) (#t #t))))
; The names known, a vector of 64 buckets by a name's first and last bytes
; and length, since a first letter alone puts a dozen names in t; each
; name's entry a vector: 1 the name, 2 its symbol, 3 its sets.
(def %ht-bucket
  (fn (_ s)
    ((fn (_ n)
       (match ((int= n 0) 1)
              (#t (int+ 1 (int& 63 (int+ (int* 7 (char->int (str-byte-ref s 0)))
                                         (int+ (int* 3 (char->int (str-byte-ref s (int+ n -1)))) n)))))))
     (str-byte-len s))))
(def %ht-names (obj-make %ht-vector 65))
(obj-set! %ht-names 0 64)
((fn (go k) (match ((int< k 65) (do (obj-set! %ht-names k ()) (go (int+ k 1)))) (#t ()))) 1)
; The entry of the lowered name S, or nil.
(def %ht-entry
  (fn (self s l)
    (match ((eq? l ()) ())
           ((match ((int= (str-byte-ref s 0) (str-byte-ref (obj-ref (first l) 1) 0)) (str=? s (obj-ref (first l) 1))) (#t #f))
             (first l))
           (#t (self s (rest l))))))
(def %ht-lookup (fn (_ s) (%ht-entry s (obj-ref %ht-names (%ht-bucket s)))))
; NAMES, strings, known and in the sets SET.
(def %ht-know!
  (fn (_ set names)
    (%ht-each
      (fn (_ n)
        ((fn (_ e)
           (match
             ((null? e)
               ((fn (_ v b)
                  (obj-set! v 0 3) (obj-set! v 1 n) (obj-set! v 2 (str->sym n)) (obj-set! v 3 (int| set %ht-known))
                  (obj-set! %ht-names b (pair v (obj-ref %ht-names b))))
                (obj-make %ht-vector 4) (%ht-bucket n)))
             (#t (obj-set! e 3 (int| set (obj-ref e 3))))))
         (%ht-lookup n)))
      names)))
; The name S, lowered: its symbol when known, else S.
(def %ht-sym (fn (_ s) ((fn (_ e) (match ((null? e) s) (#t (obj-ref e 2)))) (%ht-lookup s))))
(%ht-know! %ht-void
  (list "area" "base" "br" "col" "embed" "hr" "img" "input" "link" "meta" "param" "source" "track" "wbr"))
(%ht-know! %ht-raw (list "script" "style" "textarea" "title" "iframe" "xmp"))
(%ht-know! %ht-dropped
  (list "head" "script" "style" "template" "iframe" "title" "xmp" "object" "datalist" "noframes"))
(%ht-know! %ht-head (list "base" "link" "meta" "noscript" "script" "style" "template" "title"))
(%ht-know! %ht-closes-p
  (list "address" "article" "aside" "blockquote" "center" "dd" "details" "dialog" "dir" "div" "dl" "dt"
        "fieldset" "figcaption" "figure" "footer" "form" "h1" "h2" "h3" "h4" "h5" "h6" "header" "hgroup"
        "hr" "li" "main" "menu" "nav" "ol" "p" "pre" "search" "section" "summary" "table" "ul"))
(%ht-know! %ht-p-stop (list "html" "table" "td" "th" "caption" "button"))
(%ht-know! %ht-headings (list "h1" "h2" "h3" "h4" "h5" "h6"))
(%ht-know! %ht-strongs (list "b" "strong"))
(%ht-know! %ht-emphs (list "i" "em" "cite" "dfn" "var"))
(%ht-know! %ht-codes (list "code" "kbd" "samp" "tt"))
(%ht-know! %ht-parts
  (list "body" "html" "tr" "td" "th" "thead" "tbody" "tfoot" "caption"
        "colgroup" "noscript" "legend" "option" "optgroup"))
; The names compared one by one below.
(%ht-know! 0 (list "a" "button" "img" "input" "select" "textarea"))

; An element is a vector: 0 its name, 1 its attributes ((NAME . VALUE) ...),
; 2 its children, last first, each a string or an element, 3 its parent, 4
; a form's (INDEX ACTION METHOD ENCODING), nil on any other element; 5 the
; outermost head at or above it, 6 the outermost p at or above it below
; any element named in %ht-p-stop, each nil for none or the root; 7 the
; sets its name is in.  A start tag asks for the head and p, and they are
; kept as an element is made, from its parent's, where asking walked every
; element open above.  (eq? compares a vector by its value word, its
; length: identity is same?.)
(def %ht-node
  (fn (_ name flags attrs parent)
    (def v (obj-make %ht-vector 9))
    (obj-set! v 0 8) (obj-set! v 1 name) (obj-set! v 2 attrs) (obj-set! v 3 ()) (obj-set! v 4 parent)
    (obj-set! v 5 ())
    (obj-set! v 6
      (match ((null? parent) ())
             ((not (null? (obj-ref parent 6))) (obj-ref parent 6))
             ((eq? name (lit head)) v)
             (#t ())))
    (obj-set! v 7
      (match ((null? parent) ())
             ((%ht-in? flags %ht-p-stop) ())
             ((not (null? (obj-ref parent 7))) (obj-ref parent 7))
             ((eq? name (lit p)) v)
             (#t ())))
    (obj-set! v 8 flags)
    v))
; The open head or p at or above ND, as %ht-node keeps them, closed: ND's
; place after.
(def %ht-closed-kept
  (fn (_ nd slot) ((fn (_ x) (match ((null? x) nd) (#t (%ht-parent x)))) (obj-ref nd slot))))
(def %ht-name (fn (_ nd) (obj-ref nd 1)))
(def %ht-kids (fn (_ nd) (%reverse (obj-ref nd 3))))
(def %ht-parent (fn (_ nd) (obj-ref nd 4)))
(def %ht-add! (fn (_ nd x) (obj-set! nd 3 (pair x (obj-ref nd 3)))))
; ND's attribute NAME, or nil.
(def %ht-attr
  (fn (_ nd name) ((fn (_ hit) (match ((null? hit) ()) (#t (rest hit)))) (%ht-assoc name (obj-ref nd 2)))))
(def %ht-attr-or (fn (_ nd name default) ((fn (_ v) (match ((null? v) default) (#t v))) (%ht-attr nd name))))
(def %ht-flags (fn (_ nd) (obj-ref nd 8)))
(def %ht-named? (fn (_ x name) (match ((str? x) #f) (#t (eq? (%ht-name x) name)))))

; --- tags ------------------------------------------------------------------
; The attributes from I of S to the tag's >: (ATTRS . END), END past the >.
; A name alone has the value ""; a value is in either quote or none.
(def %ht-gap? (fn (_ c) (match ((int= c #\/) #t) (#t (%ht-white? c)))))
(def %ht-bare? (fn (_ b) (match ((int= b -1) #f) ((int= b #\>) #f) (#t (not (%ht-white? b))))))
(def %ht-attrs
  (fn (go s i attrs)
    (def w (%ht-skip %ht-gap? s i))
    (def c (%ht-at s w))
    (match
      ((int= c -1) (pair (%reverse attrs) w))
      ((int= c #\>) (pair (%reverse attrs) (int+ w 1)))
      (#t
        ((fn (_ e)
           (def name (%ht-lower (%ht-sub s w e)))
           (def q (%ht-skip %ht-white? s e))
           (match
             ((int= (%ht-at s q) #\=)
               ((fn (_ v)
                  (def d (%ht-at s v))
                  (match
                    ((match ((int= d #\") #t) ((int= d #\') #t) (#t #f))
                      ((fn (_ z)
                         (go s (match ((int= (%ht-at s z) -1) z) (#t (int+ z 1)))
                             (pair (pair name (entity-decode (%ht-sub s (int+ v 1) z))) attrs)))
                       (%ht-upto s (int+ v 1) d)))
                    (#t ((fn (_ z) (go s z (pair (pair name (entity-decode (%ht-sub s v z))) attrs)))
                         (%ht-skip %ht-bare? s v)))))
                (%ht-skip %ht-white? s (int+ q 1))))
             (#t (go s e (pair (pair name "") attrs)))))
         (%ht-name-end s (int+ w 1)))))))
; I past the > of the tag that ends at or after I.
(def %ht-past (fn (_ s i) ((fn (_ k) (match ((int= (%ht-at s k) -1) k) (#t (int+ k 1)))) (%ht-upto s i %ht-gt))))
; The tag at I of S, a <, as (KIND NAME ATTRS END FLAGS): KIND open, close
; or skip (a comment, doctype or processing instruction), NAME as %ht-sym
; answers it and FLAGS its sets, 0 for a name not known; nil when the < is
; text.
(def %ht-named
  (fn (_ kind low attrs end)
    ((fn (_ e) (match ((null? e) (list kind low attrs end 0)) (#t (list kind (obj-ref e 2) attrs end (obj-ref e 3)))))
     (%ht-lookup low))))
(def %ht-tag
  (fn (_ s i)
    (def c (%ht-at s (int+ i 1)))
    (match
      ((match ((int= c #\!) (%ht-at? "<!--" s i 0)) (#t #f))
        (list (lit skip) "" () ((fn (_ k) (match ((int< k 0) (str-byte-len s)) (#t (int+ k 3)))) (%ht-find "-->" s (int+ i 4))) 0))
      ((match ((int= c #\!) #t) (#t (int= c #\?))) (list (lit skip) "" () (%ht-past s i) 0))
      ((match ((int= c #\/) (%ht-alpha? (%ht-at s (int+ i 2)))) (#t #f))
        ((fn (_ e) (%ht-named (lit close) (%ht-lower (%ht-sub s (int+ i 2) e)) () (%ht-past s e)))
         (%ht-name-end s (int+ i 2))))
      ((%ht-alpha? c)
        ((fn (_ e)
           ((fn (_ a) (%ht-named (lit open) (%ht-lower (%ht-sub s (int+ i 1) e)) (first a) (rest a)))
            (%ht-attrs s e ())))
         (%ht-name-end s (int+ i 1))))
      (#t ()))))
; Where the close tag of NAME, a known name, starts in S at or after I, in
; any case, or the end.
(def %ht-raw-end
  (fn (go s i name)
    (def k (%ht-upto s i %ht-lt))
    (match
      ((int= (%ht-at s k) -1) k)
      ((match ((int= (%ht-at s (int+ k 1)) #\/)
                (eq? (%ht-sym (%ht-lower (%ht-sub s (int+ k 2) (%ht-name-end s (int+ k 2))))) name))
              (#t #f))
        k)
      (#t (go s (int+ k 1) name)))))

; --- the tree --------------------------------------------------------------
; The outermost open element at or above CUR named in the list NAMES below
; one named in the list STOP or the root, or nil; the nearest one named
; NAME, a symbol, or nil; the nearest one named NAME, a name not known.
(def %ht-outermost
  (fn (go cur names stop found)
    (match ((null? (%ht-parent cur)) found)
           ((%ht-memq? (%ht-name cur) stop) found)
           ((%ht-memq? (%ht-name cur) names) (go (%ht-parent cur) names stop cur))
           (#t (go (%ht-parent cur) names stop found)))))
(def %ht-nearest
  (fn (go cur name)
    (match ((null? (%ht-parent cur)) ())
           ((eq? (%ht-name cur) name) cur)
           (#t (go (%ht-parent cur) name)))))
(def %ht-nearest-unknown
  (fn (go cur name)
    (match ((null? (%ht-parent cur)) ())
           ((%ht-in? (%ht-flags cur) %ht-known) (go (%ht-parent cur) name))
           ((str=? (%ht-name cur) name) cur)
           (#t (go (%ht-parent cur) name)))))
; The form ND is in, (INDEX ACTION METHOD ENCODING), or nil.
(def %ht-form
  (fn (_ nd) ((fn (_ f) (match ((null? f) ()) (#t (obj-ref f 5)))) (%ht-nearest nd (lit form)))))
; CUR with the outermost open element named in the list NAMES closed, when
; one is open below an element named in the list STOP.
(def %ht-closed
  (fn (_ cur names stop)
    ((fn (_ nd) (match ((null? nd) cur) (#t (%ht-parent nd)))) (%ht-outermost cur names stop ()))))
; What a start tag closes first: (NAMES CLOSES STOP) -- a tag named in NAMES
; closes the nearest open element named in CLOSES, unless one named in STOP
; is nearer.  Each is a list of symbols; every NAMES is in the set
; %ht-implied-names, so a tag no rule names is not looked for in each.
(def %ht-rule
  (fn (_ names closes stop)
    (%ht-know! %ht-implied-names names) (%ht-know! 0 closes) (%ht-know! 0 stop)
    (list (%ht-map %ht-sym names) (%ht-map %ht-sym closes) (%ht-map %ht-sym stop))))
(def %ht-implied
  (list (%ht-rule (list "li") (list "li") (list "ul" "ol" "menu" "dir" "table" "td" "th"))
        (%ht-rule (list "dt" "dd") (list "dt" "dd") (list "dl" "table" "td" "th"))
        (%ht-rule (list "td" "th") (list "td" "th") (list "tr" "table"))
        (%ht-rule (list "tr") (list "td" "th" "tr") (list "thead" "tbody" "tfoot" "table"))
        (%ht-rule (list "thead" "tbody" "tfoot") (list "td" "th" "tr" "thead" "tbody" "tfoot") (list "table"))
        (%ht-rule (list "option") (list "option") (list "select" "datalist"))))
(def %ht-implied-closed
  (fn (go cur name rules)
    (match ((null? rules) cur)
           ((%ht-memq? name (first (first rules)))
             (%ht-closed cur (%ht-nth 1 (first rules)) (%ht-nth 2 (first rules))))
           (#t (go cur name (rest rules))))))
; A start tag NAME, in the sets FLAGS, with ATTRS under CUR: the open head,
; p, li, dt, dd, td, th or tr it cannot be in closed first, and a heading
; under a heading; the new element, its parent the element it is in.
(def %ht-opened
  (fn (_ cur name flags attrs)
    (def c1 (match ((%ht-in? flags %ht-head) cur) (#t (%ht-closed-kept cur 6))))
    (def c2 (match ((%ht-in? flags %ht-closes-p) (%ht-closed-kept c1 7)) (#t c1)))
    (def c3 (match ((%ht-in? flags %ht-headings) (match ((%ht-in? (%ht-flags c2) %ht-headings) (%ht-parent c2)) (#t c2)))
                   ((%ht-in? flags %ht-implied-names) (%ht-implied-closed c2 name %ht-implied))
                   (#t c2)))
    (def nd (%ht-node name flags attrs c3))
    (%ht-add! c3 nd)
    nd))
; TEXT's elements under a root: a start tag closes what it cannot be in; a
; close tag closes to the nearest open element of its name, or nothing.
; Reading a tag leaves about a thousand objects behind and only a collect
; takes them back, so the heap is collected every 1024 tags: a page's
; garbage would otherwise outgrow the machine before the parse ends.
(def %ht-tree
  (fn (_ s)
    (def root (%ht-node "" 0 () ()))
    (def cur root)
    (def forms 0)
    (def tags 0)
    (def tagged! (fn (_) (set! tags (int+ tags 1)) (match ((int= (int& tags 1023) 0) (heap-collect)) (#t ()))))
    (def text! (fn (_ i j) (match ((int= i j) ()) (#t (%ht-add! cur (entity-decode (%ht-sub s i j)))))))
    (def raw! (fn (_ nd name i j)
      (match ((eq? name (lit script)) ()) ((eq? name (lit style)) ())
             (#t (%ht-add! nd (entity-decode (%ht-sub s i j)))))))
    (def open! (fn (_ name flags attrs end)
      (def nd (%ht-opened cur name flags attrs))
      (match
        ((eq? name (lit form))
          (do (obj-set! nd 5
                (list forms (%ht-attr-or nd "action" "")
                      (match ((str=? (%ht-lower (%ht-attr-or nd "method" "")) "post") (lit post)) (#t (lit get)))
                      (match ((str=? (%ht-lower (%ht-attr-or nd "enctype" "")) "multipart/form-data") (lit multipart))
                             (#t (lit urlencoded)))))
              (set! forms (int+ forms 1))))
        (#t ()))
      (set! cur (%ht-parent nd))
      (match
        ((%ht-in? flags %ht-void) end)
        ((%ht-in? flags %ht-raw) ((fn (_ e) (raw! nd name end e) e) (%ht-raw-end s end name)))
        (#t (do (set! cur nd) end)))))
    (def close! (fn (_ name flags)
      (match ((eq? name (lit br)) ())
             (#t ((fn (_ nd) (match ((null? nd) ()) (#t (set! cur (%ht-parent nd)))))
                  (match ((%ht-in? flags %ht-known) (%ht-nearest cur name)) (#t (%ht-nearest-unknown cur name))))))))
    ((fn (go i from)
       (def k (%ht-upto s i %ht-lt))
       (def tag (match ((int= (%ht-at s k) -1) ()) (#t (%ht-tag s k))))
       (match
         ((int= (%ht-at s k) -1) (text! from k))
         ((null? tag) (go (int+ k 1) from))
         (#t (do (text! from k)
                 (tagged!)
                 ((fn (_ kind name end flags)
                    (match
                      ((eq? kind (lit open)) ((fn (_ e) (go e e)) (open! name flags (%ht-nth 2 tag) end)))
                      ((eq? kind (lit close)) (do (close! name flags) (go end end)))
                      (#t (go end end))))
                  (first tag) (%ht-nth 1 tag) (%ht-nth 3 tag) (%ht-nth 4 tag))))))
     0 0)
    root))

; --- inlines ---------------------------------------------------------------
; S's white space collapsed, a run one space, none at the start when SP (a
; space is pending, or the block begins): (TEXT . SP) after.
; Text whose white space is spaces alone, none beside another, is already
; collapsed but for a leading space: found by strchr, a call a space, where
; the walk below makes several calls a byte.
(def %ht-spaced?
  (fn (_ s)
    (match ((eq? (str-find-byte s 10 0) ())
             (match ((eq? (str-find-byte s 9 0) ())
                      (match ((eq? (str-find-byte s 13 0) ())
                               (match ((eq? (str-find-byte s 12 0) ())
                                        ((fn (go i)
                                           ((fn (_ k) (match ((eq? k ()) #t) ((int= (char->int (str-byte-ref s (int+ k 1))) 32) #f) (#t (go (int+ k 1)))))
                                            (str-find-byte s 32 i)))
                                         0))
                                      (#t #f)))
                             (#t #f)))
                    (#t #f)))
           (#t #f))))
(def %ht-collapse
  (fn (_ s sp)
    (def n (str-byte-len s))
    (match
      ((int= n 0) (pair s sp))
      ((%ht-spaced? s)
        (pair (match ((match (sp (int= (%ht-at s 0) 32)) (#t #f)) (%ht-sub s 1 n)) (#t s))
              (int= (%ht-at s (int+ n -1)) 32)))
      (#t (%ht-collapse-walk s sp)))))
(def %ht-collapse-walk
  (fn (_ s sp)
    ((fn (go i out pending)
       (def c (%ht-at s i))
       (match
         ((int= c -1) (pair (bytes->str (%reverse out)) pending))
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
                         ((eq? (%ht-name x) (lit br)) "\n")
                         ((eq? (%ht-name x) (lit img)) (%ht-attr-or x "alt" ""))
                         ((%ht-in? (%ht-flags x) %ht-dropped) "")
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
        (pair "file" (lit file)) (pair "submit" (lit submit))))
; An input's field: an unknown type is text; a button, reset or image input
; is nil.  A file input's value is "": a page cannot name the file.
(def %ht-input
  (fn (_ x)
    (def kind (%ht-lower (%ht-attr-or x "type" "text")))
    (def hit (%ht-assoc kind %ht-input-types))
    (def type
      (match ((not (null? hit)) (rest hit))
             ((%ht-member? kind (list "button" "reset" "image")) ())
             (#t (lit text))))
    (match
      ((null? type) ())
      ((match ((eq? type (lit checkbox)) #t) (#t (eq? type (lit radio))))
        (%ht-field type x (%ht-attr-or x "value" "on") (not (null? (%ht-attr x "checked"))) ()))
      ((eq? type (lit submit)) (%ht-field type x (%ht-attr-or x "value" "Submit") #f ()))
      ((eq? type (lit file)) (%ht-field type x "" #f ()))
      (#t (%ht-field type x (%ht-attr-or x "value" "") #f ())))))
; A textarea's field: its text as written, one line end after the tag left off.
(def %ht-textarea
  (fn (_ x)
    (def t (Str8 replace "\r" "" (%ht-text x)))
    (%ht-field (lit textarea) x (match ((int= (%ht-at t 0) #\newline) (%ht-sub t 1 (str-byte-len t))) (#t t)) #f ())))
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
           ((%ht-named? (first kids) (lit optgroup)) (walk (rest kids) (walk (%ht-kids (first kids)) out)))
           ((%ht-named? (first kids) (lit option))
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
                          ((%ht-in? (%ht-flags x) %ht-dropped) out)
                          ((eq? name (lit br)) (do (%set-first! sp #t) (pair (list (lit hardbreak)) (%ht-trim-end out))))
                          ((eq? name (lit img)) (%ht-text-onto (collapsed! (%ht-attr-or x "alt" "")) out))
                          ((eq? name (lit input)) (%ht-field-onto (%ht-input x) sp out))
                          ((eq? name (lit textarea)) (%ht-field-onto (%ht-textarea x) sp out))
                          ((eq? name (lit select)) (%ht-field-onto (%ht-select x) sp out))
                          ((eq? name (lit button)) (%ht-field-onto (%ht-button x) sp out))
                          ((eq? name (lit a))
                            ((fn (_ href inner)
                               (match ((null? href) (%ht-splice inner out))
                                      (#t (pair (list (lit link) href (%ht-attr x "title") inner) out))))
                             (%ht-attr x "href") (%reverse (self (%ht-kids x) sp ()))))
                          ((%ht-in? (%ht-flags x) %ht-strongs) (%ht-wrap (lit strong) (%reverse (self (%ht-kids x) sp ())) out))
                          ((%ht-in? (%ht-flags x) %ht-emphs) (%ht-wrap (lit emph) (%reverse (self (%ht-kids x) sp ())) out))
                          ((%ht-in? (%ht-flags x) %ht-codes)
                            ((fn (_ t) (match ((str=? t "") out) (#t (pair (list (lit code) t) out))))
                             (collapsed! (%ht-text x))))
                          (#t (self (%ht-kids x) sp out))))
                      (%ht-name x)))))
             (first kids)))))))
; KIDS as a block's inlines, in order: collapsed, none at either end.
(def %ht-phrase (fn (_ kids) (%reverse (%ht-trim-end (%ht-inlines kids (pair #t ()) ())))))

; --- blocks ----------------------------------------------------------------
(def %ht-level
  (fn (_ name)
    (match ((eq? name (lit h1)) 1) ((eq? name (lit h2)) 2) ((eq? name (lit h3)) 3)
           ((eq? name (lit h4)) 4) ((eq? name (lit h5)) 5) (#t 6))))
; An ol's start: its start attribute when that is a number, else 1.
(def %ht-start
  (fn (_ nd)
    (def v (%ht-attr-or nd "start" ""))
    (match ((str=? v "") 1)
           ((int= (%ht-skip %ht-digit? v 0) (str-byte-len v)) (%ht-cvt v %ht-integer 10))
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
                  ((%ht-named? (first kids) (lit code)) ((fn (_ l) (match ((null? l) "") (#t l))) (lang (first kids))))
                  (#t (go (rest kids)))))
         (%ht-kids nd)))
      (#t own))))
; A pre's text: as written, one line end after the <pre> left off, one at
; the end.
(def %ht-pre-text
  (fn (_ nd)
    (def t (Str8 replace "\r" "" (%ht-text nd)))
    (def u (match ((int= (%ht-at t 0) #\newline) (%ht-sub t 1 (str-byte-len t))) (#t t)))
    (match ((str=? u "") "")
           ((int= (%ht-at u (int+ (str-byte-len u) -1)) #\newline) u)
           (#t (%str-concat (list u "\n"))))))
; A list's items: each li's blocks; what is not an li joins the item before it.
(def %ht-list
  (fn (_ nd flow)
    (def ordered? (eq? (%ht-name nd) (lit ol)))
    (def items
      ((fn (go kids acc)
         (match
           ((null? kids) (%reverse acc))
           ((%ht-named? (first kids) (lit li)) (go (rest kids) (pair (flow (%ht-kids (first kids))) acc)))
           (#t (go (rest kids)
                   ((fn (_ bs)
                      (match ((null? bs) acc)
                             ((null? acc) (list bs))
                             (#t (pair (%ht-append (first acc) bs) (rest acc)))))
                    (flow (list (first kids))))))))
       (%ht-kids nd) ()))
    (match ((null? items) ())
           (#t (list (list (lit list) ordered? (match (ordered? (%ht-start nd)) (#t ())) #t items))))))
; A cell's align attribute: left, center, right, or nil.
(def %ht-align
  (fn (_ nd)
    ((fn (_ a) (match ((null? a) ()) ((str=? a "left") (lit left)) ((str=? a "center") (lit center))
                      ((str=? a "right") (lit right)) (#t ())))
     (%ht-lower (%ht-attr-or nd "align" "")))))
(def %ht-len (fn (self l) (match ((null? l) 0) (#t (int+ 1 (self (rest l)))))))
; L's first N, nil after its end.
(def %ht-pad (fn (self l n) (match ((int< n 1) ()) ((null? l) (pair () (self l (int+ n -1)))) (#t (pair (first l) (self (rest l) (int+ n -1)))))))
; A table: its caption a paragraph, then (table HEADER? ALIGNS ROWS), a
; cell a column whatever its colspan.  The first row is a header when it is
; in a thead or every cell of it is a th; ALIGNS are its cells' align
; attributes, and a th in any other row is bold.  A row with no cells is
; dropped.
(def %ht-table
  (fn (_ nd)
    (def rows ()) (def head #f) (def aligns ()) (def caption ())
    (def cell? (fn (_ x) (match ((%ht-named? x (lit td)) #t) (#t (%ht-named? x (lit th))))))
    (def all-th? (fn (self l) (match ((null? l) #t) ((%ht-named? (first l) (lit th)) (self (rest l))) (#t #f))))
    (def add-row! (fn (_ cells in-head)
      (def first? (null? rows))
      (def header (match (first? (match (in-head #t) (#t (all-th? cells)))) (#t #f)))
      (when first? (set! head header) (set! aligns (%ht-map %ht-align cells)))
      (set! rows (pair (%ht-map (fn (_ c)
                                  ((fn (_ inl) (match ((match (header #f) ((null? inl) #f) (#t (%ht-named? c (lit th))))
                                                        (list (list (lit strong) inl)))
                                                       (#t inl)))
                                   (%ht-phrase (%ht-kids c))))
                                cells)
                       rows))))
    (def row! (fn (_ tr in-head)
      ((fn (_ cells) (unless (null? cells) (add-row! cells in-head)))
       ((fn (go kids) (match ((null? kids) ()) ((cell? (first kids)) (pair (first kids) (go (rest kids)))) (#t (go (rest kids)))))
        (%ht-kids tr)))))
    ((fn (walk kids in-head)
       (%ht-each
         (fn (_ x)
           (unless (str? x)
             (match ((eq? (%ht-name x) (lit tr)) (row! x in-head))
                    ((eq? (%ht-name x) (lit caption)) (when (null? caption) (set! caption (%ht-phrase (%ht-kids x)))))
                    ((eq? (%ht-name x) (lit thead)) (walk (%ht-kids x) #t))
                    ((match ((eq? (%ht-name x) (lit tbody)) #t) (#t (eq? (%ht-name x) (lit tfoot)))) (walk (%ht-kids x) #f))
                    (#t ()))))
         kids))
     (%ht-kids nd) #f)
    (def width ((fn (go l n) (match ((null? l) n) ((int< n (%ht-len (first l))) (go (rest l) (%ht-len (first l)))) (#t (go (rest l) n))))
                rows 0))
    (%ht-onto (match ((null? caption) ()) (#t (list (list (lit paragraph) caption))))
              (match ((null? rows) ())
                     (#t (list (list (lit table) head (%ht-pad aligns width)
                                     (%reverse (%ht-map (fn (_ r) (%ht-pad r width)) rows)))))))))
; KIDS, in order, as blocks: text and phrasing elements between blocks a
; paragraph, each block element its block or blocks.
(def %ht-flow
  (fn (self kids)
    (def out ()) (def phrase ())
    (def flush! (fn (_)
      (match
        ((null? phrase) ())
        (#t (do ((fn (_ inl) (match ((null? inl) ()) (#t (set! out (pair (list (lit paragraph) inl) out)))))
                 (%ht-phrase (%reverse phrase)))
                (set! phrase ()))))))
    (def block! (fn (_ b) (flush!) (set! out (pair b out))))
    (def blocks! (fn (_ bs) (flush!) (set! out (%ht-onto bs out))))
    (def paragraph! (fn (_ inl) (flush!) (match ((null? inl) ()) (#t (set! out (pair (list (lit paragraph) inl) out))))))
    (%ht-each
      (fn (_ x)
        (match
          ((str? x) (set! phrase (pair x phrase)))
          ((not (%ht-in? (%ht-flags x) %ht-blocks)) (set! phrase (pair x phrase)))
          (#t ((fn (_ name)
                 (match
                   ((%ht-in? (%ht-flags x) %ht-dropped) (flush!))
                   ((%ht-in? (%ht-flags x) %ht-headings)
                     ((fn (_ inl) (flush!) (unless (null? inl) (set! out (pair (list (lit heading) (%ht-level name) inl) out))))
                      (%ht-phrase (%ht-kids x))))
                   ((eq? name (lit p)) (paragraph! (%ht-phrase (%ht-kids x))))
                   ((eq? name (lit pre)) (block! (list (lit code-block) (%ht-info x) (%ht-pre-text x))))
                   ((eq? name (lit blockquote)) (block! (list (lit block-quote) (self (%ht-kids x)))))
                   ((match ((eq? name (lit ul)) #t) ((eq? name (lit ol)) #t) (#t (eq? name (lit menu))))
                     (blocks! (%ht-list x self)))
                   ((eq? name (lit hr)) (block! (list (lit thematic-break))))
                   ((eq? name (lit table)) (blocks! (%ht-table x)))
                   ((eq? name (lit dt))
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
       (def k (%ht-upto s i %ht-lt))
       (match
         ((int= (%ht-at s k) -1) ())
         (#t ((fn (_ tag)
                (match
                  ((null? tag) (go (int+ k 1)))
                  ((match ((eq? (first tag) (lit open)) (eq? (%ht-nth 1 tag) (lit title))) (#t #f))
                    ((fn (_ e)
                       ((fn (_ t) (match ((str=? t "") ()) (#t t)))
                        (%ht-rtrim (first (%ht-collapse (entity-decode (%ht-sub s (%ht-nth 3 tag) e)) #t)))))
                     (%ht-raw-end s (%ht-nth 3 tag) (lit title))))
                  ((match ((eq? (first tag) (lit open)) (%ht-in? (%ht-nth 4 tag) %ht-raw)) (#t #f))
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
      (doc "Parse HTML into a list of blocks as (Markdown parse) answers them: (heading LEVEL INLINES), (paragraph INLINES), (code-block INFO TEXT), (block-quote BLOCKS), (list ORDERED? START TIGHT? ITEMS) with each item a list of blocks, (thematic-break), (table HEADER? ALIGNS ROWS) with each row a list of cells and each cell its inlines, a caption a paragraph before it.  Inlines are strings and (emph INLINES), (strong INLINES), (code TEXT), (link HREF TITLE INLINES), (hardbreak), and a form's fields, (field TYPE NAME VALUE ON OPTIONS FORM): TYPE text, search, password, email, url, number, hidden, file, textarea, checkbox, radio, select or submit, ON whether a box is checked, OPTIONS a select's (VALUE . LABEL) options or a button element's one, FORM the form's (INDEX ACTION METHOD ENCODING), ENCODING multipart or urlencoded, or nil.  Tolerant of unclosed p, li, td and th, attributes in either quote or none, and names in any case; head, script, style and comments are dropped, entities decoded, white space collapsed."
        (returns LIST "The page's blocks")
        (example "(Html parse \"<UL><li>one<li><a href=/u title='t'>two</a></UL>\")" "(('list #f () #t ((('paragraph (\"one\"))) (('paragraph (('link \"/u\" \"t\" (\"two\"))))))))")
        (example "(Html parse \"<pre>\\nx &lt; y\\n</pre><hr><blockquote>q</blockquote>\")" "(('code-block \"\" \"x < y\\n\") ('thematic-break) ('block-quote (('paragraph (\"q\")))))")
        (example "(Html parse \"<form action=/s><input name=q> <input type=submit value=Go></form>\")" "(('paragraph (('field 'text \"q\" \"\" #f () (0 \"/s\" 'get 'urlencoded)) \" \" ('field 'submit () \"Go\" #f () (0 \"/s\" 'get 'urlencoded)))))"))
      (%ht-reading text (fn (_ s) (%ht-flow (%ht-kids (%ht-tree s))))))
    (method title (self (param text STRING "HTML text"))
      (doc "The text of the page's <title>, its white space collapsed, or nil when it has none."
        (returns ANY "The title, or nil")
        (example "(Html title \"<title>One\\n two</title>\")" "\"One two\"")
        (example "(Html title \"<p>no title\")" ""))
      (%ht-reading text %ht-title))))

(provide x/codec/html Html)
