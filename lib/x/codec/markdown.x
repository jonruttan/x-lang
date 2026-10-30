; codec/markdown.x -- Markdown: CommonMark parse, and HTML out.
;
; (Markdown parse TEXT) answers the document as a list of blocks, each a list led
; by its CommonMark name:
;
;   (heading LEVEL INLINES)          (paragraph INLINES)
;   (code-block INFO TEXT)           (block-quote BLOCKS)
;   (list ORDERED? START TIGHT? ITEMS), each item a list of blocks
;   (thematic-break)                 (html-block TEXT)
;
; and inlines a list of strings (text) and lists:
;
;   (emph INLINES) (strong INLINES) (code TEXT) (softbreak) (hardbreak)
;   (link DESTINATION TITLE INLINES) (image DESTINATION TITLE INLINES)
;   (html-inline TEXT)
;
; START is nil for a bullet list, TITLE nil when there is none.  Destinations and
; titles are decoded (backslash escapes and entities); (Markdown html BLOCKS)
; percent-encodes and escapes them, rendering as the CommonMark reference does.
;
; The parse is commonmark.js's: a line at a time against the stack of open
; blocks (continue each, start new ones, then add the rest as text), then each
; paragraph and heading's text through the delimiter and bracket stacks.
; Character references are x/codec/entity's.  Not yet here: Unicode case
; folding and punctuation (labels fold ASCII; flanking sees ASCII punctuation).
;
; The scan runs per byte, so it is module functions over primitives bound once,
; and nodes are raw vectors read by slot: a class call costs a few hundred
; objects, a prim-ref a few thousand, and Vector ref ~200 against obj ref's 13.

(module x/codec/markdown)
(import x/type/class)
(import x/core/list)
(import x/type/vector)
(import x/codec/entity entity-at)

(import x/core/doors char->int int% int+ int< obj-make obj-ref obj-same? obj-set! str-byte-len str-byte-ref str-byte-sub)
(def %md-cvt (prim-ref (lit convert) (lit to)))
(def %md-vector ((prim-ref (lit type) (lit of)) (Vector make 0 ())))

; --- nodes -----------------------------------------------------------------
; A node is a vector of N slots, each nil; slot K is read and written by K.
; (eq? compares a vector by its value word, its length: identity is same?.)
(def %md-node
  (fn (_ n)
    (def v (obj-make %md-vector (int+ n 1)))
    (obj-set! v 0 n)
    ((fn (go k) (match ((int< 0 k) (do (obj-set! v k ()) (go (int+ k -1)))) (#t ()))) n)
    v))
(def %md-get (fn (_ v k) (obj-ref v (int+ k 1))))
(def %md-put! (fn (_ v k x) (obj-set! v (int+ k 1) x)))

; --- bytes -----------------------------------------------------------------
; The per-byte functions are match over int doors: if is an operative (an eval
; and a tail-eval a call), null? and not are closures, generic + dispatches.
; The byte at I of S as an integer, -1 past either end.
(def %md-at
  (fn (_ s i)
    (match ((int< i 0) -1) ((int< i (str-byte-len s)) (char->int (str-byte-ref s i))) (#t -1))))
(def %md-sub (fn (_ s i j) (str-byte-sub s i (- j i))))
(def %md-rest (fn (_ s i) (str-byte-sub s i (- (str-byte-len s) i))))
(def %md-space? (fn (_ c) (match ((= c #\space) #t) ((= c #\tab) #t) (#t #f))))
(def %md-white?
  (fn (_ c)
    (match ((= c #\space) #t) ((= c #\tab) #t) ((= c #\newline) #t) ((= c #\return) #t)
           ((= c 11) #t) ((= c 12) #t) (#t #f))))
(def %md-punct?
  (fn (_ c)
    (match ((int< c 33) #f) ((int< c 48) #t) ((int< c 58) #f) ((int< c 65) #t) ((int< c 91) #f)
           ((int< c 97) #t) ((int< c 123) #f) ((int< c 127) #t) (#t #f))))
(def %md-digit? (fn (_ c) (match ((int< c #\0) #f) ((int< #\9 c) #f) (#t #t))))
(def %md-alpha?
  (fn (_ c) (match ((int< c #\A) #f) ((int< #\z c) #f) ((int< c #\[) #t) ((int< c #\a) #f) (#t #t))))
(def %md-alnum?
  (fn (_ c) (match ((int< c #\0) #f) ((int< c #\:) #t) (#t (%md-alpha? c)))))
(def %md-hyphen-alnum? (fn (_ c) (match ((= c #\-) #t) (#t (%md-alnum? c)))))
(def %md-join (fn (_ pieces) (%str-concat (%reverse pieces))))
; List ref, map, for-each and filter, and Assoc find with string keys: a class
; send costs hundreds of objects, and the tree and HTML passes make one a node.
(def %md-nth (fn (self k l) (match ((= k 0) (first l)) (#t (self (int+ k -1) (rest l))))))
(def %md-map (fn (self f l) (match ((eq? l ()) ()) (#t (pair (f (first l)) (self f (rest l)))))))
(def %md-each (fn (self f l) (match ((eq? l ()) ()) (#t (do (f (first l)) (self f (rest l)))))))
(def %md-filter
  (fn (self f l)
    (match ((eq? l ()) ()) ((f (first l)) (pair (first l) (self f (rest l)))) (#t (self f (rest l))))))
(def %md-assoc
  (fn (self k al) (match ((eq? al ()) ()) ((str=? k (first (first al))) (first al)) (#t (self k (rest al))))))
(def %md-spaces (fn (self n) (match ((int< n 1) "") (#t (%str-concat (list " " (self (- n 1))))))))
; I past the bytes of S from I that PRED? holds for; back from J the same way.
(def %md-skip
  (fn (self pred? s i) (match ((pred? (%md-at s i)) (self pred? s (int+ i 1))) (#t i))))
(def %md-skip-back
  (fn (self pred? s j) (match ((pred? (%md-at s (int+ j -1))) (self pred? s (int+ j -1))) (#t j))))
; I past the bytes B from I; back from J the same way; on to the byte B or the end.
(def %md-run (fn (self s i b) (match ((= (%md-at s i) b) (self s (int+ i 1) b)) (#t i))))
(def %md-run-back
  (fn (self s j b) (match ((= (%md-at s (int+ j -1)) b) (self s (int+ j -1) b)) (#t j))))
(def %md-upto
  (fn (self s i b)
    (match ((= (%md-at s i) b) i) ((= (%md-at s i) -1) i) (#t (self s (int+ i 1) b)))))
(def %md-trim
  (fn (_ s)
    ((fn (_ i) (%md-sub s i (match ((= i (str-byte-len s)) i) (#t (%md-skip-back %md-white? s (str-byte-len s))))))
     (%md-skip %md-white? s 0))))
; I past spaces and tabs, and one line end and the spaces and tabs after it.
(def %md-spnl
  (fn (_ s i)
    ((fn (_ a) (match ((= (%md-at s a) #\newline) (%md-skip %md-space? s (int+ a 1))) (#t a)))
     (%md-skip %md-space? s i))))
; I past spaces and tabs to a line end (past it), or -1.
(def %md-line-end
  (fn (_ s i)
    ((fn (_ k) (match ((= (%md-at s k) -1) k) ((= (%md-at s k) #\newline) (int+ k 1)) (#t -1)))
     (%md-skip %md-space? s i))))
; Whether PAT is in S at I, from PAT's byte K.
(def %md-at?
  (fn (self pat s i k)
    (match ((= k (str-byte-len pat)) #t)
           ((= (%md-at s (int+ i k)) (char->int (str-byte-ref pat k))) (self pat s i (int+ k 1)))
           (#t #f))))
; Where PAT next starts in S at or after I, or -1.
(def %md-find
  (fn (self pat s i)
    (match ((= (%md-at s i) -1) -1)
           ((%md-at? pat s i 0) i)
           (#t (self pat s (int+ i 1))))))
; Whether the byte C is one of the bytes of SET from K.
(def %md-in?
  (fn (self c set k)
    (match ((= k (str-byte-len set)) #f)
           ((= c (char->int (str-byte-ref set k))) #t)
           (#t (self c set (int+ k 1))))))
(def %md-one-of? (fn (_ c set) (%md-in? c set 0)))

; S with its backslash escapes and entities decoded.
(def %md-unescape-from
  (fn (self s i from out)
    (def c (%md-at s i))
    (match
      ((= i (str-byte-len s)) (match ((= from 0) s) (#t (%md-join (pair (%md-sub s from i) out)))))
      ((match ((= c #\\) (%md-punct? (%md-at s (int+ i 1)))) (#t #f))
        (self s (int+ i 2) (int+ i 2) (pair (%md-sub s (int+ i 1) (int+ i 2)) (pair (%md-sub s from i) out))))
      ((= c #\&)
        ((fn (_ e)
           (match ((eq? e ()) (self s (int+ i 1) from out))
                  (#t (self s (rest e) (rest e) (pair (first e) (pair (%md-sub s from i) out))))))
         (entity-at s i)))
      (#t (self s (int+ i 1) from out)))))
(def %md-unescape (fn (_ s) (%md-unescape-from s 0 0 ())))

; --- links: labels, destinations, titles ----------------------------------
; The end of the link label at I of S ([ through ]), or -1.
(def %md-label
  (fn (_ s i)
    (if (not (= (%md-at s i) #\[)) -1
      ((fn (go k)
         (def c (%md-at s k))
         (match
           ((< 1000 (- k i)) -1)
           ((= c -1) -1)
           ((= c #\[) -1)
           ((= c #\]) (+ k 1))
           ((= c #\\) (if (= (%md-at s (+ k 1)) -1) -1 (go (+ k 2))))
           (#t (go (+ k 1)))))
       (+ i 1)))))
; A label as references are matched: no brackets, trimmed, inner white space one
; space, ASCII letters folded.
(def %md-normal-from
  (fn (self s i out white)
    (def c (%md-at s i))
    (match
      ((= i (str-byte-len s)) (bytes->str (%reverse out)))
      ((%md-white? c) (self s (int+ i 1) (match (white out) (#t (pair 32 out))) #t))
      ((match ((int< c #\A) #f) ((int< #\Z c) #f) (#t #t)) (self s (int+ i 1) (pair (int+ c 32) out) #f))
      (#t (self s (int+ i 1) (pair c out) #f)))))
(def %md-normal
  (fn (_ label) (%md-normal-from (%md-trim (%md-sub label 1 (- (str-byte-len label) 1))) 0 () #f)))
; The destination at I of S as (DESTINATION . END), or nil.
(def %md-destination
  (fn (_ s i)
    (if (= (%md-at s i) #\<)
      ((fn (go k)
         (def c (%md-at s k))
         (match
           ((= c #\>) (pair (%md-unescape (%md-sub s (+ i 1) k)) (+ k 1)))
           ((match ((= c -1) #t) ((= c #\<) #t) ((= c #\newline) #t) (#t #f)) ())
           ((= c #\\) (go (+ k (if (%md-punct? (%md-at s (+ k 1))) 2 1))))
           (#t (go (+ k 1)))))
       (+ i 1))
      ((fn (go k open)
         (def c (%md-at s k))
         (match
           ((if (= c #\\) (%md-punct? (%md-at s (+ k 1))) #f) (go (+ k 2) open))
           ((= c #\() (go (+ k 1) (+ open 1)))
           ((if (= c #\)) (< 0 open) #f) (go (+ k 1) (- open 1)))
           ((if (= c #\)) #t (if (int< c 33) #t (= c 127)))
             (match ((if (= k i) (not (= c #\))) #f) ())
                    ((< 0 open) ())
                    (#t (pair (%md-unescape (%md-sub s i k)) k))))
           (#t (go (+ k 1) open))))
       i 0))))
; The title at I of S as (TITLE . END), or nil.
(def %md-title
  (fn (_ s i)
    (def q (%md-at s i))
    (def close (match ((= q #\") q) ((= q #\') q) ((= q #\() #\)) (#t -1)))
    (if (= close -1) ()
      ((fn (go k)
         (def c (%md-at s k))
         (match
           ((= c close) (pair (%md-unescape (%md-sub s (+ i 1) k)) (+ k 1)))
           ((= c -1) ())
           ((if (= q #\() (= c #\() #f) ())
           ((= c #\\) (go (+ k (if (= (%md-at s (+ k 1)) -1) 1 2))))
           (#t (go (+ k 1)))))
       (+ i 1)))))
; The link reference definition that leads S, filed in REFS (a cell holding an
; alist) unless its label is there already: how many bytes it took, or 0.
(def %md-reference
  (fn (_ s refs)
    (def e (%md-label s 0))
    (def d (if (if (< 0 e) (= (%md-at s e) #\:) #f)
             (%md-destination s (%md-spnl s (+ e 1))) ()))
    (def label (if (null? d) "" (%md-normal (%md-sub s 0 e))))
    (def before (if (null? d) 0 (rest d)))
    (def t (if (null? d) ()
             ((fn (_ k) (if (= k before) () (%md-title s k))) (%md-spnl s before))))
    (def end (match
               ((null? d) -1)
               ((null? t) (%md-line-end s before))
               ((< -1 (%md-line-end s (rest t))) (%md-line-end s (rest t)))
               (#t (do (set! t ()) (%md-line-end s before)))))
    (if (if (< 0 end) (not (str=? label "")) #f)
      (do (when (null? (%md-assoc label (first refs)))
            (%set-first! refs (pair (pair label (pair (first d) (if (null? t) () (first t))))
                                    (first refs))))
          end)
      0)))

; --- raw HTML --------------------------------------------------------------
(def %md-tag-name-end
  (fn (_ s i)
    (if (%md-alpha? (%md-at s i))
      (%md-skip %md-hyphen-alnum? s (+ i 1))
      i)))
(def %md-attr-start? (fn (_ c) (if (%md-alpha? c) #t (if (= c #\_) #t (= c #\:)))))
(def %md-attr-char?
  (fn (_ c) (if (%md-alnum? c) #t (match ((= c #\_) #t) ((= c #\:) #t) ((= c #\.) #t) ((= c #\-) #t) (#t #f)))))
(def %md-unquoted?
  (fn (_ c)
    (match ((int< c 33) #f) ((= c #\") #f) ((= c #\') #f) ((= c #\=) #f) ((= c #\<) #f)
           ((= c #\>) #f) ((= c #\`) #f) (#t #t))))
; The end of the attribute value at I of S, or -1.
(def %md-value-end
  (fn (_ s i)
    (def q (%md-at s i))
    (match
      ((if (= q #\") #t (= q #\'))
        ((fn (_ k) (if (< k 0) -1 (+ k 1))) (%md-find (%md-sub s i (+ i 1)) s (+ i 1))))
      ((%md-unquoted? q) (%md-skip %md-unquoted? s (+ i 1)))
      (#t -1))))
; The end of the open tag at I of S (< through >), or -1.
(def %md-open-tag-end
  (fn (_ s i)
    (def name (%md-tag-name-end s (+ i 1)))
    (if (= name (+ i 1)) -1
      ((fn (go k)
         (def w (%md-skip %md-white? s k))
         (def c (%md-at s w))
         (match
           ((= c #\>) (+ w 1))
           ((= c #\/) (if (= (%md-at s (+ w 1)) #\>) (+ w 2) -1))
           ((if (< k w) (%md-attr-start? c) #f)
             ((fn (_ a)
                ((fn (_ v)
                   (if (= (%md-at s v) #\=)
                     ((fn (_ e) (if (< e 0) -1 (go e))) (%md-value-end s (%md-skip %md-white? s (+ v 1))))
                     (go a)))
                 (%md-skip %md-white? s a)))
              (%md-skip %md-attr-char? s (+ w 1))))
           (#t -1)))
       name))))
; The end of the closing tag at I of S (</ through >), or -1.
(def %md-close-tag-end
  (fn (_ s i)
    (def name (%md-tag-name-end s (+ i 2)))
    (def w (%md-skip %md-white? s name))
    (if (if (< (+ i 2) name) (= (%md-at s w) #\>) #f) (+ w 1) -1)))
; The end of the raw HTML at I of S (a tag, comment, processing instruction,
; declaration or CDATA section), or -1.
(def %md-html-end
  (fn (_ s i)
    (def c (%md-at s (+ i 1)))
    (def after (fn (_ pat from) ((fn (_ k) (if (< k 0) -1 (+ k (str-byte-len pat)))) (%md-find pat s from))))
    (def at? (fn (_ pat) (str=? (%md-sub s i (+ i (str-byte-len pat))) pat)))
    (match
      ((not (= (%md-at s i) #\<)) -1)
      ((= c #\/) (%md-close-tag-end s i))
      ((= c #\?) (after "?>" (+ i 2)))
      ((at? "<!-->") (+ i 5))
      ((at? "<!--->") (+ i 6))
      ((at? "<!--") (after "-->" (+ i 4)))
      ((at? "<![CDATA[") (after "]]>" (+ i 9)))
      ((if (= c #\!) (%md-alpha? (%md-at s (+ i 2))) #f) (after ">" (+ i 3)))
      ((%md-alpha? c) (%md-open-tag-end s i))
      (#t -1))))
(def %md-raw-tags (list "script" "pre" "textarea" "style"))
(def %md-block-tags
  (Str8 split " " (%str-concat (list
    "address article aside base basefont blockquote body caption center col colgroup "
    "dd details dialog dir div dl dt fieldset figcaption figure footer form frame "
    "frameset h1 h2 h3 h4 h5 h6 head header hr html iframe legend li link main menu "
    "menuitem nav noframes ol optgroup option p param search section summary table "
    "tbody td tfoot th thead title tr track ul"))))
(def %md-member? (fn (_ s l) (List any? (fn (_ t) (str=? t s)) l)))
; Which HTML block, 1 to 7, starts S; 0 for none.  Seven, a lone complete tag,
; only when PARA? (whether the line would interrupt a paragraph) is #f.
(def %md-html-block-kind
  (fn (_ s para?)
    (def close? (= (%md-at s 1) #\/))
    (def from (if close? 2 1))
    (def name (Str8 downcase (%md-sub s from (%md-tag-name-end s from))))
    (def after (%md-at s (+ from (str-byte-len name))))
    (def ends? (fn (_ slash?)
      (match ((= after -1) #t) ((%md-white? after) #t) ((= after #\>) #t)
             ((if slash? (= after #\/) #f) (= (%md-at s (+ from (str-byte-len name) 1)) #\>))
             (#t #f))))
    (def at? (fn (_ pat) (str=? (%md-sub s 0 (str-byte-len pat)) pat)))
    (match
      ((not (= (%md-at s 0) #\<)) 0)
      ((if close? #f (if (%md-member? name %md-raw-tags) (ends? #f) #f)) 1)
      ((at? "<!--") 2)
      ((at? "<?") 3)
      ((if (at? "<!") (%md-alpha? (%md-at s 2)) #f) 4)
      ((at? "<![CDATA[") 5)
      ((if (%md-member? name %md-block-tags) (ends? #t) #f) 6)
      (para? 0)
      ((if (if close? #f (%md-member? name %md-raw-tags)) #f
         ((fn (_ e) (if (< 0 e) (= (%md-line-end s e) (str-byte-len s)) #f))
          (if close? (%md-close-tag-end s 0) (%md-open-tag-end s 0))))
        7)
      (#t 0))))
; Whether LINE ends the HTML block of KIND (1 to 5).
(def %md-html-block-ends?
  (fn (_ kind line)
    (def has? (fn (_ pat) (< -1 (%md-find pat line 0))))
    (match
      ((= kind 1) ((fn (_ l) (List any? (fn (_ t) (< -1 (%md-find t l 0)))
                               (list "</script>" "</pre>" "</textarea>" "</style>")))
                   (Str8 downcase line)))
      ((= kind 2) (has? "-->"))
      ((= kind 3) (has? "?>"))
      ((= kind 4) (has? ">"))
      ((= kind 5) (has? "]]>"))
      (#t #f))))

; --- block helpers ---------------------------------------------------------
; Where the line at I of S ends: its LF or CR, or the end of S.
(def %md-eol
  (fn (self s i)
    (def c (%md-at s i))
    (match ((= c #\newline) i) ((= c #\return) i) ((= c -1) i) (#t (self s (int+ i 1))))))
; TEXT's lines, without their ends (LF, CRLF or CR); a last end adds none.
(def %md-lines-from
  (fn (self s i out)
    (def j (%md-eol s i))
    (def c (%md-at s j))
    (match
      ((= c -1) (%reverse (match ((= i j) out) (#t (pair (%md-sub s i j) out)))))
      (#t (self s (match ((match ((= c #\return) (= (%md-at s (int+ j 1)) #\newline)) (#t #f)) (int+ j 2))
                         (#t (int+ j 1)))
                (pair (%md-sub s i j) out))))))
(def %md-lines (fn (_ text) (%md-lines-from text 0 ())))
; An ATX heading's text: closing #s off when white space comes before them.
(def %md-heading-text
  (fn (_ s)
    (def e (%md-skip-back %md-space? s (str-byte-len s)))
    (def h (%md-run-back s e #\#))
    (def w (%md-skip-back %md-space? s h))
    (match ((= h e) s)
           ((= w 0) "")
           ((< w h) (%md-sub s 0 w))
           (#t s))))
; Whether S is a thematic break: three or more of one of * - _, and spaces.
(def %md-rule?
  (fn (_ s)
    (def c (%md-at s 0))
    (if (match ((= c #\*) #t) ((= c #\-) #t) ((= c #\_) #t) (#t #f))
      ((fn (go i k)
         (def b (%md-at s i))
         (match ((= b -1) (< 2 k))
                ((= b c) (go (+ i 1) (+ k 1)))
                ((%md-space? b) (go (+ i 1) k))
                (#t #f)))
       0 0)
      #f)))
; S up to its trailing lines of spaces, those lines and their ends gone.
(def %md-strip-blank-end
  (fn (go s j)
    ((fn (_ k) (if (= (%md-at s (- k 1)) #\newline) (go s (- k 1)) (%md-sub s 0 j)))
     (%md-run-back s j #\space))))
(def %md-special?
  (fn (_ c)
    (match ((%md-digit? c) #t) ((= c #\#) #t) ((= c #\`) #t) ((= c #\~) #t) ((= c #\*) #t)
           ((= c #\+) #t) ((= c #\_) #t) ((= c #\=) #t) ((= c #\<) #t) ((= c #\>) #t)
           ((= c #\-) #t) (#t #f))))

; --- blocks ----------------------------------------------------------------
; A block under construction is a node: 0 its type, 1 its parent, 2 its children
; (last first), 3 open?, 4 whether its last line was blank, 5 its text (last
; piece first), 6-9 what its type keeps, 10 whether the blank line search has
; passed it, 11 the line it began on.  A list keeps ordered?, its marker byte,
; its start and tight?; an item its marker's column and the width of marker and
; padding; a fenced code block its fence byte, length and indent, and its info;
; a heading its level; an HTML block its kind.
(def %md-blocks
  (fn (_ text refs)
    (def tip ()) (def oldtip ()) (def last-matched ()) (def all-closed #t)
    (def ln "") (def off 0) (def col 0) (def partial #f)
    (def nn 0) (def nncol 0) (def indent 0) (def blank #f) (def lineno 0)
    (def nget %md-get)
    (def nset! %md-put!)
    (def at (fn (_ i) (%md-at ln i)))
    (def type? (fn (_ nd t) (match ((eq? nd ()) #f) (#t (eq? (obj-ref nd 1) t)))))
    (def last-child (fn (_ nd) ((fn (_ ks) (match ((eq? ks ()) ()) (#t (first ks)))) (obj-ref nd 3))))
    (def make (fn (_ t parent)
      (def nd (%md-node 12))
      (nset! nd 0 t) (nset! nd 1 parent) (nset! nd 3 #t) (nset! nd 4 #f)
      (nset! nd 10 #f) (nset! nd 11 lineno)
      nd))
    (def push! (fn (_ nd s) (nset! nd 5 (pair s (nget nd 5)))))
    (def content (fn (_ nd) (%md-join (nget nd 5))))
    (def doc (make (lit document) ()))
    (set! tip doc)
    (def indented? (fn (_) (int< 3 indent)))
    (def find-nn! (fn (_)
      ((fn (go i c)
         (def b (at i))
         (match
           ((= b #\space) (go (+ i 1) (+ c 1)))
           ((= b #\tab) (go (+ i 1) (+ c (- 4 (& c 3)))))
           (#t (do (set! blank (= b -1)) (set! nn i) (set! nncol c) (set! indent (- c col))))))
       off col)))
    (def advance-nn! (fn (_) (set! off nn) (set! col nncol) (set! partial #f)))
    ; COUNT bytes on, or COUNT columns when COLS?, a tab taken partly when the
    ; columns end inside it.
    (def advance! (fn (go count cols?)
      (def c (at off))
      (when (if (int< 0 count) (int< -1 c) #f)
        (if (= c #\tab)
          ((fn (_ to-tab)
             (if cols?
               (do (set! partial (int< count to-tab))
                   ((fn (_ step)
                      (set! col (+ col step))
                      (unless partial (set! off (+ off 1)))
                      (go (- count step) cols?))
                    (if (int< count to-tab) count to-tab)))
               (do (set! partial #f) (set! col (+ col to-tab)) (set! off (+ off 1))
                   (go (- count 1) cols?))))
           (- 4 (& col 3)))
          (do (set! partial #f) (set! off (+ off 1)) (set! col (+ col 1))
              (go (- count 1) cols?))))))
    (def add-line! (fn (_)
      (when partial
        (set! off (+ off 1))
        (push! tip (%md-spaces (- 4 (& col 3)))))
      (push! tip (%md-rest ln off))
      (push! tip "\n")))
    (def unlink! (fn (_ nd)
      (def p (nget nd 1))
      (nset! p 2 (%md-filter (fn (_ k) (not (obj-same? k nd))) (nget p 2)))))
    ; Leading reference definitions off a paragraph's text: whether there were any.
    (def take-references! (fn (_ nd)
      ((fn (go s any)
         (def n (if (= (%md-at s 0) #\[) (%md-reference s refs) 0))
         (if (< 0 n) (go (%md-rest s n) #t)
           (do (nset! nd 5 (list s)) any)))
       (content nd) #f)))
    (def ends-blank? (fn (go nd)
      (match
        ((null? nd) #f)
        ((nget nd 4) #t)
        ((if (nget nd 10) #f (if (type? nd (lit list)) #t (type? nd (lit item))))
          (do (nset! nd 10 #t) (go (last-child nd))))
        (#t (do (nset! nd 10 #t) #f)))))
    (def kids-loose? (fn (go ks last-item?)
      (match ((null? ks) #f)
             ((if (ends-blank? (first ks)) (if last-item? (not (null? (rest ks))) #t) #f) #t)
             (#t (go (rest ks) last-item?)))))
    (def tight? (fn (go items)
      (match
        ((null? items) #t)
        ((if (null? (rest items)) #f (ends-blank? (first items))) #f)
        ((kids-loose? (%reverse (nget (first items) 2)) (null? (rest items))) #f)
        (#t (go (rest items))))))
    (def finalize! (fn (_ nd)
      (def p (nget nd 1))
      (nset! nd 3 #f)
      (match
        ((type? nd (lit paragraph))
          (when (take-references! nd)
            (when (str=? (%md-trim (content nd)) "") (unlink! nd))))
        ((type? nd (lit fenced))
          ((fn (_ s)
             ((fn (_ e)
                (nset! nd 9 (%md-trim (%md-unescape (%md-sub s 0 e))))
                (nset! nd 5 (list (%md-rest s (+ e 1)))))
              (%md-upto s 0 #\newline)))
           (content nd)))
        ((type? nd (lit indented))
          ((fn (_ s) (nset! nd 5 (list (%str-concat (list (%md-strip-blank-end s (str-byte-len s)) "\n")))))
           (content nd)))
        ((type? nd (lit html-block))
          ((fn (_ s) (nset! nd 5 (list (%md-strip-blank-end s (str-byte-len s))))) (content nd)))
        ((type? nd (lit list)) (nset! nd 9 (tight? (%reverse (nget nd 2)))))
        (#t ()))
      (set! tip p)))
    (def can-contain? (fn (_ parent t)
      (match
        ((type? parent (lit list)) (eq? t (lit item)))
        ((type? parent (lit document)) (not (eq? t (lit item))))
        ((type? parent (lit quote)) (not (eq? t (lit item))))
        ((type? parent (lit item)) (not (eq? t (lit item))))
        (#t #f))))
    (def add-child! (fn (_ t)
      ((fn (go) (unless (can-contain? tip t) (finalize! tip) (go))))
      (def nd (make t tip))
      (nset! tip 2 (pair nd (nget tip 2)))
      (set! tip nd)
      nd))
    (def close-unmatched! (fn (_)
      (unless all-closed
        ((fn (go)
           (unless (obj-same? oldtip last-matched)
             ((fn (_ p) (finalize! oldtip) (set! oldtip p) (go)) (nget oldtip 1)))))
        (set! all-closed #t))))
    ; Whether ND goes on with this line: 0 it does, 1 it does not, 2 the line
    ; closed it (a closing fence).
    (def continues (fn (_ nd)
      (match
        ((type? nd (lit quote))
          (if (if (indented?) #f (= (at nn) #\>))
            (do (advance-nn!) (advance! 1 #f)
                (when (%md-space? (at off)) (advance! 1 #t))
                0)
            1))
        ((type? nd (lit item))
          (match
            (blank (if (null? (nget nd 2)) 1 (do (advance-nn!) 0)))
            ((int< indent (+ (nget nd 6) (nget nd 7))) 1)
            (#t (do (advance! (+ (nget nd 6) (nget nd 7)) #t) 0))))
        ((type? nd (lit fenced))
          ((fn (_ run)
             (if (if (indented?) #f
                   (if (int< (- run nn) (nget nd 7)) #f
                     (= (%md-line-end ln run) (str-byte-len ln))))
               (do (finalize! nd) 2)
               (do ((fn (go i)
                      (when (if (int< 0 i) (%md-space? (at off)) #f)
                        (advance! 1 #t) (go (- i 1))))
                    (nget nd 8))
                   0)))
           (%md-run ln nn (nget nd 6))))
        ((type? nd (lit indented))
          (match ((indented?) (do (advance! 4 #t) 0))
                 (blank (do (advance-nn!) 0))
                 (#t 1)))
        ((type? nd (lit paragraph)) (if blank 1 0))
        ((type? nd (lit html-block)) (if (if blank (int< 5 (nget nd 6)) #f) 1 0))
        ((type? nd (lit heading)) 1)
        ((type? nd (lit rule)) 1)
        (#t 0))))
    ; The list marker at the next non-space byte, as (ORDERED? BYTE START COLUMN
    ; WIDTH), the offset left past it and its padding; or nil.
    (def marker (fn (_ container)
      (def c (at nn))
      (def digits (%md-skip %md-digit? ln nn))
      (def bullet? (match ((= c #\*) #t) ((= c #\+) #t) ((= c #\-) #t) (#t #f)))
      (def end (match
                 ((indented?) -1)
                 (bullet? (+ nn 1))
                 ((if (int< nn digits) (int< (- digits nn) 10) #f)
                   ((fn (_ d)
                      (if (if (= d #\.) #t (= d #\)))
                        (if (if (type? container (lit paragraph))
                              (not (str=? (%md-sub ln nn digits) "1")) #f)
                          -1 (+ digits 1))
                        -1))
                    (at digits)))
                 (#t -1)))
      (def after (if (int< end 0) -2 (at end)))
      (if (if (int< -2 after) (if (= after -1) #t (%md-space? after)) #f)
        (if (if (type? container (lit paragraph)) (= (%md-line-end ln end) (str-byte-len ln)) #f)
          ()
          ((fn (_ ordered? byte start column)
             (advance-nn!) (advance! (- end nn) #t)
             ((fn (_ start-col start-off)
                ((fn (go) (advance! 1 #t)
                   (when (if (int< (- col start-col) 5) (%md-space? (at off)) #f) (go))))
                ((fn (_ spaces)
                   (if (match ((int< 4 spaces) #t) ((int< spaces 1) #t) ((= (at off) -1) #t) (#t #f))
                     (do (set! col start-col) (set! off start-off) (set! partial #f)
                         (when (%md-space? (at off)) (advance! 1 #t))
                         (list ordered? byte start column (+ (- end nn) 1)))
                     (list ordered? byte start column (+ (- end nn) spaces))))
                 (- col start-col)))
              col off))
           (not bullet?) (if bullet? c (at (- end 1)))
           (if bullet? () (%md-cvt (%md-sub ln nn digits) (Type named INTEGER) 10))
           indent))
        ())))
    (def indented-code (fn (_ container)
      (if (if (indented?) (if (type? tip (lit paragraph)) #f (not blank)) #f)
        (do (advance! 4 #t) (close-unmatched!) (add-child! (lit indented)) 2)
        0)))
    ; A block starting at the next non-space byte: 0 none, 1 a container, 2 a leaf.
    (def starts (fn (_ container)
      (def c (at nn))
      (def atx (if (indented?) 0 (if (= c #\#) (- (%md-run ln nn #\#) nn) 0)))
      (def fence (if (indented?) 0
                   (if (if (= c #\`) #t (= c #\~))
                     ((fn (_ k) (if (if (int< 2 k) (if (= c #\~) #t (< (%md-find "`" ln (+ nn k)) 0)) #f) k 0))
                      (- (%md-run ln nn c) nn))
                     0)))
      (def html (if (if (indented?) #f (= c #\<))
                  (%md-html-block-kind (%md-rest ln nn)
                    (if (type? container (lit paragraph)) #t
                      (if all-closed #f (if blank #f (type? tip (lit paragraph))))))
                  0))
      (match
        ((if (indented?) #f (= c #\>))
          (do (advance-nn!) (advance! 1 #f)
              (when (%md-space? (at off)) (advance! 1 #t))
              (close-unmatched!) (add-child! (lit quote))
              1))
        ((if (if (int< 0 atx) (int< atx 7) #f)
           ((fn (_ a) (if (= a -1) #t (%md-space? a))) (at (+ nn atx))) #f)
          (do (advance-nn!) (advance! atx #f)
              (close-unmatched!)
              ((fn (_ nd)
                 (nset! nd 6 atx)
                 (push! nd (%md-heading-text (%md-rest ln off))))
               (add-child! (lit heading)))
              (advance! (- (str-byte-len ln) off) #f)
              2))
        ((int< 0 fence)
          (do (close-unmatched!)
              ((fn (_ nd) (nset! nd 6 c) (nset! nd 7 fence) (nset! nd 8 indent)) (add-child! (lit fenced)))
              (advance-nn!) (advance! fence #f)
              2))
        ((int< 0 html)
          (do (close-unmatched!)
              ((fn (_ nd) (nset! nd 6 html)) (add-child! (lit html-block)))
              2))
        ((if (indented?) #f
           (if (type? container (lit paragraph))
             (if (if (= c #\=) #t (= c #\-))
               (= (%md-line-end ln (%md-run ln nn c)) (str-byte-len ln)) #f)
             #f))
          (do (close-unmatched!)
              (take-references! container)
              (if (str=? (content container) "") 0
                ((fn (_ nd)
                   (nset! nd 6 (if (= c #\=) 1 2))
                   (nset! nd 5 (nget container 5))
                   ((fn (_ p) (nset! p 2 (pair nd (%md-filter (fn (_ k) (not (obj-same? k container))) (nget p 2)))))
                    (nget container 1))
                   (set! tip nd)
                   (advance! (- (str-byte-len ln) off) #f)
                   2)
                 (make (lit heading) (nget container 1))))))
        ((if (indented?) #f (%md-rule? (%md-rest ln nn)))
          (do (close-unmatched!) (add-child! (lit rule))
              (advance! (- (str-byte-len ln) off) #f)
              2))
        ((if (indented?) (type? container (lit list)) #t)
          ((fn (_ m)
             (if (null? m) (indented-code container)
               (do (close-unmatched!)
                   (unless (if (type? tip (lit list))
                             (if (eq? (nget tip 6) (%md-nth 0 m)) (= (nget tip 7) (%md-nth 1 m)) #f)
                             #f)
                     ((fn (_ l) (nset! l 6 (%md-nth 0 m)) (nset! l 7 (%md-nth 1 m))
                                (nset! l 8 (%md-nth 2 m)) (nset! l 9 #t))
                      (add-child! (lit list))))
                   ((fn (_ it) (nset! it 6 (%md-nth 3 m)) (nset! it 7 (%md-nth 4 m)))
                    (add-child! (lit item)))
                   1)))
           (marker container)))
        (#t (indented-code container)))))
    ; The open blocks the line goes on: (CONTAINER . ALL-MATCHED?), or nil when
    ; the line closed one (a closing fence) and is spent.
    (def walk (fn (go container)
      (def last (last-child container))
      (if (if (null? last) #t (not (nget last 3)))
        (pair container #t)
        (do (find-nn!)
            ((fn (_ r) (match ((= r 0) (go last)) ((= r 1) (pair container #f)) (#t ())))
             (continues last))))))
    ; New blocks starting where the open ones left off: the container the rest
    ; of the line goes to.
    (def start-blocks (fn (go container leaf?)
      (if leaf? container
        (do (find-nn!)
            (if (if (indented?) #f (not (%md-special? (at nn))))
              (do (advance-nn!) container)
              ((fn (_ r) (match ((= r 1) (go tip #f)) ((= r 2) tip)
                                (#t (do (advance-nn!) container))))
               (starts container)))))))
    (def leaf? (fn (_ nd)
      (match ((type? nd (lit fenced)) #t) ((type? nd (lit indented)) #t)
             ((type? nd (lit html-block)) #t) (#t #f))))
    ; The rest of the line as text: a paragraph's, lazily, or CONTAINER's.
    (def add-text! (fn (_ container)
      (if (if all-closed #f (if blank #f (type? tip (lit paragraph))))
        (add-line!)
        (do (close-unmatched!)
            (when (if blank (not (null? (last-child container))) #f)
              (nset! (last-child container) 4 #t))
            ((fn (_ last-blank)
               ((fn (go c) (unless (null? c) (nset! c 4 last-blank) (go (nget c 1)))) container))
             (if blank
               (match ((type? container (lit quote)) #f)
                      ((type? container (lit fenced)) #f)
                      ((type? container (lit item))
                        (not (if (null? (nget container 2)) (= (nget container 11) lineno) #f)))
                      (#t #t))
               #f))
            (match
              ((type? container (lit html-block))
                ((fn (_ from)
                   (add-line!)
                   (when (if (int< (nget container 6) 6)
                           (%md-html-block-ends? (nget container 6) (%md-rest ln from))
                           #f)
                     (finalize! container)))
                 off))
              ((if (type? container (lit paragraph)) #t (leaf? container)) (add-line!))
              ((if (int< off (str-byte-len ln)) (not blank) #f)
                (do (add-child! (lit paragraph)) (advance-nn!) (add-line!)))
              (#t ()))))))
    (def incorporate! (fn (_ line)
      (set! lineno (+ lineno 1))
      (set! ln line) (set! off 0) (set! col 0) (set! blank #f) (set! partial #f)
      (set! oldtip tip)
      ((fn (_ walked)
         (unless (null? walked)
           (set! all-closed (obj-same? (first walked) oldtip))
           (set! last-matched (first walked))
           (add-text! (start-blocks (first walked)
                        (if (type? (first walked) (lit paragraph)) #f (leaf? (first walked)))))))
       (walk doc))))
    (%md-each incorporate! (%md-lines text))
    ((fn (go) (unless (null? tip) (finalize! tip) (go))))
    doc))

; --- inlines ---------------------------------------------------------------
; An inline under construction is a node: 0 its type, 1 its text or
; destination, 2 first child, 3 last child, 4 next, 5 previous, 6 parent, 7
; title.  A delimiter run: 0 its byte, 1 how many are left, 2 how many there
; were, 3 its text inline, 4 previous, 5 next, 6 can open?, 7 can close?.  A
; bracket: 0 its text inline, 1 previous, 2 the delimiter below it, 3 where it
; is, 4 image?, 5 active?, 6 whether a bracket follows it.
(def %md-inline (fn (_ t v) (def nd (%md-node 8)) (%md-put! nd 0 t) (%md-put! nd 1 v) nd))
(def %md-append!
  (fn (_ p c)
    (%md-put! c 6 p) (%md-put! c 4 ())
    (if (null? (%md-get p 3))
      (do (%md-put! p 2 c) (%md-put! c 5 ()))
      (do (%md-put! (%md-get p 3) 4 c) (%md-put! c 5 (%md-get p 3))))
    (%md-put! p 3 c)))
(def %md-unlink!
  (fn (_ nd)
    (def pv (%md-get nd 5)) (def nx (%md-get nd 4)) (def p (%md-get nd 6))
    (if (null? pv) (unless (null? p) (%md-put! p 2 nx)) (%md-put! pv 4 nx))
    (if (null? nx) (unless (null? p) (%md-put! p 3 pv)) (%md-put! nx 5 pv))
    (%md-put! nd 4 ()) (%md-put! nd 5 ()) (%md-put! nd 6 ())))
(def %md-insert-after!
  (fn (_ nd new)
    (def nx (%md-get nd 4)) (def p (%md-get nd 6))
    (%md-put! new 4 nx) (%md-put! new 5 nd) (%md-put! new 6 p) (%md-put! nd 4 new)
    (if (null? nx) (unless (null? p) (%md-put! p 3 new)) (%md-put! nx 5 new))))
; Every child of FROM after AFTER (all of them when AFTER is nil) up to UPTO
; moved, in order, to the end of TO.
(def %md-move!
  (fn (go t upto to)
    (unless (if (null? t) #t (obj-same? t upto))
      ((fn (_ nx) (%md-unlink! t) (%md-append! to t) (go nx upto to)) (%md-get t 4)))))
; Whether C stops a run of plain text.
(def %md-stop?
  (fn (_ c)
    (match ((= c -1) #t) ((= c #\newline) #t) ((= c #\`) #t) ((= c #\[) #t)
           ((= c #\]) #t) ((= c #\\) #t) ((= c #\!) #t) ((= c #\<) #t)
           ((= c #\&) #t) ((= c #\*) #t) ((= c #\_) #t) (#t #f))))
(def %md-plain-end (fn (self s i) (match ((%md-stop? (%md-at s i)) i) (#t (self s (int+ i 1))))))
; The end of the email address at I of S, before its >, or -1.
(def %md-email-local? (fn (_ c) (if (%md-alnum? c) #t (%md-one-of? c ".!#$%&'*+/=?^_`{|}~-"))))
(def %md-email
  (fn (_ s i)
    (def at-sign (%md-skip %md-email-local? s i))
    (if (if (< i at-sign) (= (%md-at s at-sign) #\@) #f)
      ((fn (label k)
         (def e (%md-skip %md-hyphen-alnum? s k))
         (match
           ((if (< k e) (if (< (- e k) 64) (if (= (%md-at s k) #\-) #f (not (= (%md-at s (- e 1)) #\-))) #f) #f)
             (match ((= (%md-at s e) #\>) e)
                    ((= (%md-at s e) #\.) (label (+ e 1)))
                    (#t -1)))
           (#t -1)))
       (+ at-sign 1))
      -1)))
; The end of the URI autolink at I of S, before its >, or -1.
(def %md-uri
  (fn (_ s i)
    (def scheme (%md-skip (fn (_ c) (if (%md-alnum? c) #t (match ((= c #\+) #t) ((= c #\.) #t) ((= c #\-) #t) (#t #f))))
                  s (+ i 1)))
    (if (if (%md-alpha? (%md-at s i)) (if (< 1 (- scheme i)) (if (< (- scheme i) 33) (= (%md-at s scheme) #\:) #f) #f) #f)
      ((fn (go k)
         (def c (%md-at s k))
         (match ((= c #\>) k) ((int< c 33) -1) ((= c #\<) -1) (#t (go (+ k 1)))))
       (+ scheme 1))
      -1)))

(def %md-inlines
  (fn (_ text refs)
    (def subj (%md-trim text))
    (def pos 0) (def delims ()) (def brackets ())
    (def get %md-get)
    (def put! %md-put!)
    (def inline %md-inline)
    (def append! %md-append!)
    (def unlink! %md-unlink!)
    (def at (fn (_ i) (%md-at subj i)))
    (def root (inline (lit root) ()))
    (def text! (fn (_ s) (append! root (inline (lit text) s))))
    (def take! (fn (_ i j) (text! (%md-sub subj i j)) (set! pos j)))
    (def remove-delim! (fn (_ d)
      (unless (null? (get d 4)) (put! (get d 4) 5 (get d 5)))
      (if (null? (get d 5)) (set! delims (get d 4)) (put! (get d 5) 4 (get d 4)))))
    (def mod3 (fn (_ k) (int% k 3)))
    ; An opener and a closer of one byte: the emphasis between them, and the
    ; closer to go on from.
    (def pair! (fn (_ o c)
      (def use (if (if (int< 1 (get c 1)) (int< 1 (get o 1)) #f) 2 1))
      (def oi (get o 3)) (def ci (get c 3))
      (put! o 1 (- (get o 1) use)) (put! c 1 (- (get c 1) use))
      (put! oi 1 (%md-sub (get oi 1) 0 (get o 1)))
      (put! ci 1 (%md-sub (get ci 1) 0 (get c 1)))
      (def em (inline (if (= use 1) (lit emph) (lit strong)) ()))
      (%md-move! (get oi 4) ci em)
      (%md-insert-after! oi em)
      ((fn (go) (unless (obj-same? (get c 4) o) (remove-delim! (get c 4)) (go))))
      (when (= (get o 1) 0) (unlink! oi) (remove-delim! o))
      (if (= (get c 1) 0)
        ((fn (_ nx) (unlink! ci) (remove-delim! c) nx) (get c 5))
        c)))
    ; The opener for closer C below FLOOR, or nil.
    (def opener (fn (go o c floor bottom)
      (match
        ((null? o) ())
        ((obj-same? o bottom) ())
        ((obj-same? o floor) ())
        ((if (= (get o 0) (get c 0))
           (if (get o 6)
             (not (if (if (get c 6) #t (get o 7))
                    (if (= (mod3 (get c 2)) 0) #f (= (mod3 (+ (get o 2) (get c 2))) 0))
                    #f))
             #f)
           #f)
          o)
        (#t (go (get o 4) c floor bottom)))))
    (def emphasis! (fn (_ bottom)
      (def floors (%md-node 12))
      ((fn (go k) (when (int< -1 k) (put! floors k bottom) (go (- k 1)))) 11)
      (def start ((fn (go d) (if (if (null? d) #t (obj-same? (get d 4) bottom)) d (go (get d 4)))) delims))
      ((fn (go c)
         (unless (null? c)
           (if (not (get c 7)) (go (get c 5))
             ((fn (_ floor)
                ((fn (_ o)
                   (if (null? o)
                     ((fn (_ nx)
                        (put! floors floor (get c 4))
                        (unless (get c 6) (remove-delim! c))
                        (go nx))
                      (get c 5))
                     (go (pair! o c))))
                 (opener (get c 4) c (get floors floor) bottom)))
              (+ (if (= (get c 0) #\*) 0 6) (+ (if (get c 6) 3 0) (mod3 (get c 2))))))))
       start)
      ((fn (go) (unless (if (null? delims) #t (obj-same? delims bottom)) (remove-delim! delims) (go))))))
    (def delim! (fn (_ c)
      (def e (%md-run subj pos c))
      (def before (at (- pos 1)))
      (def after (at e))
      (def bw (if (= before -1) #t (%md-white? before)))
      (def aw (if (= after -1) #t (%md-white? after)))
      (def bp (%md-punct? before))
      (def ap (%md-punct? after))
      (def left (if aw #f (if ap (if bw #t bp) #t)))
      (def right (if bw #f (if bp (if aw #t ap) #t)))
      (def d (%md-node 8))
      (put! d 0 c) (put! d 1 (- e pos)) (put! d 2 (- e pos))
      (put! d 4 delims)
      (put! d 6 (if (= c #\_) (if left (if right bp #t) #f) left))
      (put! d 7 (if (= c #\_) (if right (if left ap #t) #f) right))
      (take! pos e)
      (put! d 3 (get root 3))
      (unless (null? delims) (put! delims 5 d))
      (set! delims d)))
    (def bracket! (fn (_ index image?)
      (unless (null? brackets) (put! brackets 6 #t))
      (def b (%md-node 7))
      (put! b 0 (get root 3)) (put! b 1 brackets) (put! b 2 delims) (put! b 3 index)
      (put! b 4 image?) (put! b 5 #t) (put! b 6 #f)
      (set! brackets b)))
    (def space? (fn (_ c) (= c #\space)))
    (def newline! (fn (_)
      (set! pos (+ pos 1))
      (def lc (get root 3))
      (def s (if (null? lc) "" (if (eq? (get lc 0) (lit text)) (get lc 1) "")))
      (def k (str-byte-len s))
      (if (= (%md-at s (- k 1)) #\space)
        ((fn (_ j)
           (put! lc 1 (%md-sub s 0 j))
           (append! root (inline (if (int< 1 (- k j)) (lit hardbreak) (lit softbreak)) ())))
         (%md-skip-back space? s k))
        (append! root (inline (lit softbreak) ())))
      (set! pos (%md-skip space? subj pos))))
    (def backslash! (fn (_)
      (def c (at (+ pos 1)))
      (match
        ((= c #\newline)
          (do (append! root (inline (lit hardbreak) ()))
              (set! pos (%md-skip space? subj (+ pos 2)))))
        ((%md-punct? c) (do (text! (%md-sub subj (+ pos 1) (+ pos 2))) (set! pos (+ pos 2))))
        (#t (take! pos (+ pos 1))))))
    (def backticks! (fn (_)
      (def after (%md-run subj pos #\`))
      (def k (- after pos))
      (def close
        ((fn (go i)
           (def j (%md-find "`" subj i))
           (if (< j 0) ()
             ((fn (_ e) (if (= (- e j) k) (pair j e) (go e))) (%md-run subj j #\`))))
         after))
      (if (null? close) (take! pos after)
        ((fn (_ s)
           ((fn (_ m)
              (append! root
                (inline (lit code)
                  (if (if (int< 1 m)
                        (if (= (%md-at s 0) #\space)
                          (if (= (%md-at s (- m 1)) #\space)
                            (not (str=? (%md-trim s) "")) #f) #f) #f)
                    (%md-sub s 1 (- m 1)) s)))
              (set! pos (rest close)))
            (str-byte-len s)))
         (Str8 replace "\n" " " (%md-sub subj after (first close)))))))
    ; An inline link's (DESTINATION TITLE END) after the ] at POS, or nil.
    (def inline-link (fn (_)
      (if (not (= (at pos) #\()) ()
        ((fn (_ d)
           (if (null? d) ()
             ((fn (_ k)
                ((fn (_ t)
                   ((fn (_ j) (if (= (at j) #\)) (list (first d) (if (null? t) () (first t)) (+ j 1)) ()))
                    (%md-spnl subj (if (null? t) k (rest t)))))
                 (if (= k (rest d)) () (%md-title subj k))))
              (%md-spnl subj (rest d)))))
         ((fn (_ i) (if (= (at i) #\)) (pair "" i) (%md-destination subj i)))
          (%md-spnl subj (+ pos 1)))))))
    ; A reference link's (DESTINATION TITLE) for opener O, the label after the
    ; ] at START, or nil.
    (def reference-link (fn (_ o start)
      ((fn (_ e)
         ((fn (_ label)
            ((fn (_ hit)
               (if (null? hit) ()
                 (do (when (< 0 e) (set! pos e)) (list (first (rest hit)) (rest (rest hit))))))
             (if (null? label) () (%md-assoc (%md-normal label) (first refs)))))
          (match ((< (+ start 2) e) (%md-sub subj start e))
                 ((get o 6) ())
                 (#t (%md-sub subj (get o 3) start)))))
       (%md-label subj start))))
    (def link! (fn (_ o found)
      ((fn (_ nd)
         (put! nd 7 (%md-nth 1 found))
         (%md-move! (get (get o 0) 4) () nd)
         (append! root nd)
         (emphasis! (get o 2))
         (set! brackets (get o 1))
         (unlink! (get o 0))
         (unless (get o 4)
           ((fn (go b) (unless (null? b) (unless (get b 4) (put! b 5 #f)) (go (get b 1))))
            brackets)))
       (inline (if (get o 4) (lit image) (lit link)) (first found)))))
    (def close-bracket! (fn (_)
      (set! pos (+ pos 1))
      (def start pos)
      (def o brackets)
      (match
        ((null? o) (text! "]"))
        ((not (get o 5)) (do (text! "]") (set! brackets (get o 1))))
        (#t ((fn (_ found)
               (if (null? found)
                 (do (set! brackets (get o 1)) (set! pos start) (text! "]"))
                 (link! o found)))
             ((fn (_ l) (if (null? l) (reference-link o start) (do (set! pos (%md-nth 2 l)) l)))
              (inline-link)))))))
    (def autolink! (fn (_)
      (def uri-end (%md-uri subj (+ pos 1)))
      (def mail-end (if (< 0 uri-end) -1 (%md-email subj (+ pos 1))))
      (def link (fn (_ dest end)
        ((fn (_ nd)
           (append! nd (inline (lit text) (%md-sub subj (+ pos 1) end)))
           (append! root nd)
           (set! pos (+ end 1)))
         (inline (lit link) dest))))
      (match
        ((< 0 uri-end) (link (%md-sub subj (+ pos 1) uri-end) uri-end))
        ((< 0 mail-end) (link (%str-concat (list "mailto:" (%md-sub subj (+ pos 1) mail-end))) mail-end))
        (#t ((fn (_ e)
               (if (< 0 e)
                 (do (append! root (inline (lit html-inline) (%md-sub subj pos e))) (set! pos e))
                 (take! pos (+ pos 1))))
             (%md-html-end subj pos))))))
    (def entity! (fn (_)
      ((fn (_ e) (if (null? e) (take! pos (+ pos 1)) (do (text! (first e)) (set! pos (rest e)))))
       (entity-at subj pos))))
    ((fn (go)
       (def c (at pos))
       (unless (= c -1)
         (match
           ((= c #\newline) (newline!))
           ((= c #\\) (backslash!))
           ((= c #\`) (backticks!))
           ((= c #\*) (delim! c))
           ((= c #\_) (delim! c))
           ((= c #\[) (do (take! pos (+ pos 1)) (bracket! (- pos 1) #f)))
           ((if (= c #\!) (= (at (+ pos 1)) #\[) #f) (do (take! pos (+ pos 2)) (bracket! (- pos 1) #t)))
           ((= c #\]) (close-bracket!))
           ((= c #\<) (autolink!))
           ((= c #\&) (entity!))
           (#t (take! pos (%md-plain-end subj (+ pos 1)))))
         (go))))
    (emphasis! ())
    (%md-inline-tree root)))
; An inline's children as the parse answers them: adjacent text joined, empty
; text dropped.
(def %md-inline-tree
  (fn (self nd)
    ((fn (go k out)
       (if (null? k) out
         ((fn (_ t v)
            (match
              ((eq? t (lit text))
                (go (%md-get k 5)
                    (match ((str=? v "") out)
                           ((if (null? out) #f (str? (first out)))
                             (pair (%str-concat (list v (first out))) (rest out)))
                           (#t (pair v out)))))
              ((if (eq? t (lit code)) #t (eq? t (lit html-inline))) (go (%md-get k 5) (pair (list t v) out)))
              ((if (eq? t (lit link)) #t (eq? t (lit image)))
                (go (%md-get k 5) (pair (list t v (%md-get k 7) (self k)) out)))
              ((if (eq? t (lit emph)) #t (eq? t (lit strong)))
                (go (%md-get k 5) (pair (list t (self k)) out)))
              (#t (go (%md-get k 5) (pair (list t) out)))))
          (%md-get k 0) (%md-get k 1))))
     (%md-get nd 3) ())))
; A block under construction as the parse answers it.
(def %md-tree
  (fn (self nd refs)
    (def t (%md-get nd 0))
    (def kids (fn (_ nd) (%md-map (fn (_ k) (self k refs)) (%reverse (%md-get nd 2)))))
    (def text (fn (_) (%md-join (%md-get nd 5))))
    (match
      ((eq? t (lit paragraph)) (list t (%md-inlines (text) refs)))
      ((eq? t (lit heading)) (list t (%md-get nd 6) (%md-inlines (text) refs)))
      ((eq? t (lit fenced)) (list (lit code-block) (%md-get nd 9) (text)))
      ((eq? t (lit indented)) (list (lit code-block) "" (text)))
      ((eq? t (lit rule)) (list (lit thematic-break)))
      ((eq? t (lit html-block)) (list t (text)))
      ((eq? t (lit quote)) (list (lit block-quote) (kids nd)))
      ((eq? t (lit list))
        (list t (%md-get nd 6) (if (%md-get nd 6) (%md-get nd 8) ()) (%md-get nd 9)
              (%md-map kids (%reverse (%md-get nd 2)))))
      (#t (kids nd)))))

; --- HTML ------------------------------------------------------------------
(def %md-escaped
  (fn (_ c) (match ((= c #\&) "&amp;") ((= c #\<) "&lt;") ((= c #\>) "&gt;") ((= c #\") "&quot;") (#t ()))))
(def %md-escape-from
  (fn (self s i from out)
    (def r (%md-escaped (%md-at s i)))
    (match
      ((= i (str-byte-len s)) (match ((= from 0) s) (#t (%md-join (pair (%md-sub s from i) out)))))
      ((eq? r ()) (self s (int+ i 1) from out))
      (#t (self s (int+ i 1) (int+ i 1) (pair r (pair (%md-sub s from i) out)))))))
(def %md-escape (fn (_ s) (%md-escape-from s 0 0 ())))
(def %md-hex?
  (fn (_ c)
    (match ((%md-digit? c) #t) ((int< c #\A) #f) ((int< c #\G) #t) ((int< c #\a) #f) ((int< c #\g) #t)
           (#t #f))))
(def %md-hex (fn (_ d) (bytes->str (list (match ((int< d 10) (int+ d 48)) (#t (int+ d 55)))))))
(def %md-url-safe?
  (fn (_ c) (match ((int< 127 c) #f) ((%md-alnum? c) #t) (#t (%md-one-of? c "-_.!~*'();/?:@&=+$,#")))))
; A destination percent-encoded as the reference encodes it: a % with two hex
; digits kept, every byte outside the URL's own set as %XX.
(def %md-encode-from
  (fn (self s i from out)
    (def c (%md-at s i))
    (match
      ((= i (str-byte-len s)) (match ((= from 0) s) (#t (%md-join (pair (%md-sub s from i) out)))))
      ((%md-url-safe? c) (self s (int+ i 1) from out))
      ((match ((= c #\%) (match ((%md-hex? (%md-at s (int+ i 1))) (%md-hex? (%md-at s (int+ i 2))))
                                (#t #f)))
              (#t #f))
        (self s (int+ i 3) from out))
      (#t (self s (int+ i 1) (int+ i 1)
            (pair (%str-concat (list "%" (%md-hex (>> c 4)) (%md-hex (& c 15))))
                  (pair (%md-sub s from i) out)))))))
(def %md-encode (fn (_ s) (%md-encode-from s 0 0 ())))
(def %md-plain
  (fn (self inlines)
    (%str-concat
      (%md-map (fn (_ x)
                  (def t (if (str? x) () (first x)))
                  (match ((str? x) x)
                         ((if (eq? t (lit code)) #t (eq? t (lit html-inline))) (%md-nth 1 x))
                         ((if (eq? t (lit softbreak)) #t (eq? t (lit hardbreak))) "\n")
                         ((if (eq? t (lit link)) #t (eq? t (lit image))) (self (%md-nth 3 x)))
                         (#t (self (%md-nth 1 x)))))
                inlines))))
(def %md-title-attr
  (fn (_ t) (if (null? t) "" (%str-concat (list " title=\"" (%md-escape t) "\"")))))
(def %md-html-inlines
  (fn (self inlines)
    (%str-concat
      (%md-map (fn (_ x)
                  (def t (if (str? x) () (first x)))
                  (match
                    ((str? x) (%md-escape x))
                    ((eq? t (lit emph)) (%str-concat (list "<em>" (self (%md-nth 1 x)) "</em>")))
                    ((eq? t (lit strong)) (%str-concat (list "<strong>" (self (%md-nth 1 x)) "</strong>")))
                    ((eq? t (lit code)) (%str-concat (list "<code>" (%md-escape (%md-nth 1 x)) "</code>")))
                    ((eq? t (lit softbreak)) "\n")
                    ((eq? t (lit hardbreak)) "<br />\n")
                    ((eq? t (lit html-inline)) (%md-nth 1 x))
                    ((eq? t (lit link))
                      (%str-concat (list "<a href=\"" (%md-escape (%md-encode (%md-nth 1 x))) "\""
                                         (%md-title-attr (%md-nth 2 x))
                                         ">" (self (%md-nth 3 x)) "</a>")))
                    ((eq? t (lit image))
                      (%str-concat (list "<img src=\"" (%md-escape (%md-encode (%md-nth 1 x)))
                                         "\" alt=\"" (%md-escape (%md-plain (%md-nth 3 x))) "\""
                                         (%md-title-attr (%md-nth 2 x)) " />")))
                    (#t "")))
                inlines))))
(def %md-html
  (fn (_ blocks)
    (def out ())
    (def nl #t)
    (def put! (fn (_ s)
      (unless (str=? s "")
        (set! out (pair s out))
        (set! nl (= (%md-at s (- (str-byte-len s) 1)) #\newline)))))
    (def cr! (fn (_) (unless nl (put! "\n"))))
    (def block (fn (go b tight)
      (def t (first b))
      (match
        ((eq? t (lit paragraph))
          (if tight (put! (%md-html-inlines (%md-nth 1 b)))
            (do (cr!) (put! "<p>") (put! (%md-html-inlines (%md-nth 1 b))) (put! "</p>") (cr!))))
        ((eq? t (lit heading))
          ((fn (_ h) (cr!) (put! (%str-concat (list "<h" h ">"))) (put! (%md-html-inlines (%md-nth 2 b)))
                     (put! (%str-concat (list "</h" h ">"))) (cr!))
           (Str8 str (%md-nth 1 b))))
        ((eq? t (lit code-block))
          ((fn (_ info)
             (cr!)
             (put! (if (str=? info "") "<pre><code>"
                     (%str-concat (list "<pre><code class=\"language-"
                                        (%md-escape (first (Str8 split " " info))) "\">"))))
             (put! (%md-escape (%md-nth 2 b)))
             (put! "</code></pre>") (cr!))
           (%md-nth 1 b)))
        ((eq? t (lit thematic-break)) (do (cr!) (put! "<hr />") (cr!)))
        ((eq? t (lit html-block)) (do (cr!) (put! (%md-nth 1 b)) (cr!)))
        ((eq? t (lit block-quote))
          (do (cr!) (put! "<blockquote>") (cr!)
              (%md-each (fn (_ k) (go k #f)) (%md-nth 1 b))
              (cr!) (put! "</blockquote>") (cr!)))
        ((eq? t (lit list))
          ((fn (_ tag)
             (cr!)
             (put! (if (if (%md-nth 1 b) (not (= (%md-nth 2 b) 1)) #f)
                     (%str-concat (list "<ol start=\"" (Str8 str (%md-nth 2 b)) "\">"))
                     (%str-concat (list "<" tag ">"))))
             (cr!)
             (List for-each
               (fn (_ item)
                 (cr!) (put! "<li>")
                 (%md-each (fn (_ k) (go k (%md-nth 3 b))) item)
                 (put! "</li>") (cr!))
               (%md-nth 4 b))
             (put! (%str-concat (list "</" tag ">"))) (cr!))
           (if (%md-nth 1 b) "ol" "ul")))
        (#t ()))))
    (%md-each (fn (_ b) (block b #f)) blocks)
    (%md-join out)))

(def-class Markdown ()
  (doc "CommonMark: (Markdown parse text) -> a list of blocks; (Markdown html blocks) -> HTML as the reference renders it."
    (example "(Markdown parse \"# Hi *there*\")" "(('heading 1 (\"Hi \" ('emph (\"there\")))))")
    (example "(Markdown html (Markdown parse \"a **b**\"))" "\"<p>a <strong>b</strong></p>\\n\"")
    (see parse) (see html))
  (static
    (method parse (self (param text STRING "Markdown text"))
      (doc "Parse Markdown (CommonMark) into a list of blocks: (heading LEVEL INLINES), (paragraph INLINES), (code-block INFO TEXT), (block-quote BLOCKS), (list ORDERED? START TIGHT? ITEMS) with each item a list of blocks, (thematic-break), (html-block TEXT). Inlines are strings and (emph INLINES), (strong INLINES), (code TEXT), (link DESTINATION TITLE INLINES), (image DESTINATION TITLE INLINES), (html-inline TEXT), (softbreak), (hardbreak)."
        (returns LIST "The document's blocks")
        (example "(Markdown parse \"- a\\n- b\")" "(('list #f () #t ((('paragraph (\"a\"))) (('paragraph (\"b\"))))))")
        (example "(Markdown parse \"[x][1]\\n\\n[1]: /u\")" "(('paragraph (('link \"/u\" () (\"x\")))))"))
      (def refs (pair () ()))
      (%md-tree (%md-blocks text refs) refs))
    (method html (self (param blocks LIST "Blocks, as (Markdown parse) answers them"))
      (doc "Render blocks as HTML, line for line as the CommonMark reference renderer does: a tight list's paragraphs without <p>, an ordered list's start when it is not 1, a code block's info as language-INFO."
        (returns STRING "HTML text")
        (example "(Markdown html (Markdown parse \"> *a*\"))" "\"<blockquote>\\n<p><em>a</em></p>\\n</blockquote>\\n\""))
      (%md-html blocks))))

(provide x/codec/markdown Markdown)
