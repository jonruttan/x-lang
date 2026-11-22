; markdown.x -- the Markdown highlighting grammar
;
; x/tool/syntax's catalogue names this module for .md and .markdown files
; and imports it the first time a file needs the grammar.
;
; A token is a line, a fenced code block or an HTML comment; a block or a
; comment spans lines, so a text is read from its start, and one still open
; at the end of the text runs to it.  A fence's marker lines are
; punctuation and its body a string; a comment is a comment.
;
; A line is read by its start, then inline:
;   - a heading (#s and a space) is a keyword, and a line of three or more
;     -, *, _ or = alone is punctuation;
;   - a quote's > and a list item's marker are punctuation;
;   - inline, a code span is a string, a link's or image's text a name and
;     its destination a string, a reference definition's label a name and
;     the rest of its line a string, an autolink a string, emphasis strong
;     or not a constant, and a backslash before punctuation an escape.
; Emphasis by _ opens and closes only beside a blank, punctuation or the
; line's end, so a snake_case name is no emphasis; by * it may sit inside a
; word.

(module x/tool/syntax/markdown)
(import x/type/list)
(import x/type/str)
(import x/reader/lexer)
(import x/tool/syntax)
(import x/core/doors char->int int+ int- str-byte-len str-byte-ref)

(def %sxm-line-bytes (list (pair 1 9) (pair 11 255) (pair -128 -1)))

(def %sxm-rules
  (fn (_)
    (list (Lexer table (lit nl) (list "\n"))
          (Lexer until (lit comment) "<!--" "-->" (lit to-end))
          (Lexer until (lit fence) "```" "```" (lit to-end))
          (Lexer until (lit fence) "~~~" "~~~" (lit to-end))
          (Lexer run (lit line) %sxm-line-bytes %sxm-line-bytes)
          (Lexer any (lit other)))))

; Byte i of t, or -1 past either end.
(def %sxm-byte
  (fn (_ t i n) (if (if (< i 0) #t (>= i n)) -1 (char->int (str-byte-ref t i)))))

(def %sxm-blank? (fn (_ c) (if (= c 32) #t (if (= c 9) #t (= c -1)))))

(def %sxm-digit? (fn (_ c) (if (>= c 48) (<= c 57) #f)))

(def %sxm-punct?
  (fn (_ c)
    (match ((< c 33) #f)
           ((<= c 47) #t)
           ((< c 58) #f)
           ((<= c 64) #t)
           ((< c 91) #f)
           ((<= c 96) #t)
           ((< c 123) #f)
           (#t (<= c 126)))))

; The offset of the first byte c from i, nil for none.
(def %sxm-find
  (fn (self t i n c)
    (match ((>= i n) ())
           ((= (%sxm-byte t i n) c) i)
           (#t (self t (int+ i 1) n c)))))

; How many bytes c run from i.
(def %sxm-run
  (fn (self t i n c)
    (if (= (%sxm-byte t i n) c) (int+ 1 (self t (int+ i 1) n c)) 0)))

; The offset of the next run of exactly k bytes c from i, nil for none.
(def %sxm-find-run
  (fn (self t i n c k)
    (let ((j (%sxm-find t i n c)))
      (if (null? j) ()
        (let ((r (%sxm-run t j n c)))
          (if (= r k) j (self t (int+ j r) n c k)))))))

; Whether a run of c may sit beside byte b: always for *, for _ only beside
; a blank, punctuation or the line's end.
(def %sxm-flank? (fn (_ c b) (if (= c 42) #t (if (%sxm-blank? b) #t (%sxm-punct? b)))))

; The offset past the emphasis closing a run of k bytes c from i: a run of
; exactly k with no blank before it; nil for none.
(def %sxm-emph-close
  (fn (self t i n c k)
    (let ((j (%sxm-find-run t i n c k)))
      (match ((null? j) ())
             ((if (not (%sxm-blank? (%sxm-byte t (int- j 1) n)))
                (%sxm-flank? c (%sxm-byte t (int+ j k) n)) #f)
               (int+ j k))
             (#t (self t (int+ j k) n c k))))))

; Whether bytes i to n are three or more of one of - * _ =, blanks between.
(def %sxm-rule-line?
  (fn (_ t i n)
    (let ((c (%sxm-byte t i n)))
      (if (List includes? c (list 45 42 95 61))
        ((fn (self j k)
           (match ((>= j n) (>= k 3))
                  ((= (%sxm-byte t j n) c) (self (int+ j 1) (int+ k 1)))
                  ((%sxm-blank? (%sxm-byte t j n)) (self (int+ j 1) k))
                  (#t #f)))
         i 0)
        #f))))

; The offset past a list item's marker at i and its blank, nil for none.
(def %sxm-marker
  (fn (_ t i n)
    (let ((c (%sxm-byte t i n)))
      (if (List includes? c (list 45 42 43))
        (if (%sxm-blank? (%sxm-byte t (int+ i 1) n)) (int+ i 1) ())
        (let ((d (%sxm-run-digits t i n)))
          (if (if (< 0 d) (<= d 9) #f)
            (if (List includes? (%sxm-byte t (int+ i d) n) (list 46 41))
              (if (%sxm-blank? (%sxm-byte t (int+ i (int+ d 1)) n)) (int+ i (int+ d 1)) ())
              ())
            ()))))))

(def %sxm-run-digits
  (fn (self t i n) (if (%sxm-digit? (%sxm-byte t i n)) (int+ 1 (self t (int+ i 1) n)) 0)))

; How many blanks from i, at most three: a line's indent.
(def %sxm-indent
  (fn (self t i n k) (if (if (< k 3) (= (%sxm-byte t i n) 32) #f) (self t (int+ i 1) n (int+ k 1)) k)))

; The pieces of a link or image whose [ is at b, the line's text from s, as
; (PIECES . NEXT); nil when no ] closes it.
(def %sxm-link
  (fn (_ t s b n at-start?)
    (let ((e (%sxm-find t (int+ b 1) n 93)))
      (if (null? e) ()
        (let ((after (%sxm-byte t (int+ e 1) n)) (label (list s (int- (int+ e 1) s) (lit name))))
          (match ((= after 40)
                   (let ((p (%sxm-find t (int+ e 2) n 41)))
                     (if (null? p) ()
                       (pair (list label (list (int+ e 1) (int- p e) (lit string))) (int+ p 1)))))
                 ((= after 91)
                   (let ((p (%sxm-find t (int+ e 2) n 93)))
                     (if (null? p) ()
                       (pair (list label (list (int+ e 1) (int- p e) (lit name))) (int+ p 1)))))
                 ((if at-start? (= after 58) #f)
                   (pair (if (< (int+ e 2) n)
                           (list (list s (int- (int+ e 2) s) (lit name))
                                 (list (int+ e 2) (int- n (int+ e 2)) (lit string)))
                           (list (list s (int- (int+ e 2) s) (lit name))))
                         n))
                 (#t ())))))))

; The inline pieces of t from i, onto acc in reverse.
(def %sxm-inline
  (fn (self t i n acc at)
    (let ((c (%sxm-byte t i n)))
      (match
        ((>= i n) acc)
        ((if (= c 92) (%sxm-punct? (%sxm-byte t (int+ i 1) n)) #f)
          (self t (int+ i 2) n (pair (list i 2 (lit escape)) acc) at))
        ((= c 96)
          (let ((k (%sxm-run t i n 96)))
            (let ((j (%sxm-find-run t (int+ i k) n 96 k)))
              (if (null? j) (self t (int+ i k) n acc at)
                (self t (int+ j k) n (pair (list i (int- (int+ j k) i) (lit string)) acc) at)))))
        ((if (= c 91) #t (if (= c 33) (= (%sxm-byte t (int+ i 1) n) 91) #f))
          (let ((l (%sxm-link t i (if (= c 33) (int+ i 1) i) n (= i at))))
            (if (null? l) (self t (int+ i 1) n acc at)
              (self t (rest l) n (List append (List reverse (first l)) acc) at))))
        ((= c 60)
          (let ((e (%sxm-find t (int+ i 1) n 62)))
            (if (if (null? e) #f
                  (if (not (null? (%sxm-find t i e 58))) (null? (%sxm-find t i e 32)) #f))
              (self t (int+ e 1) n (pair (list i (int- (int+ e 1) i) (lit string)) acc) at)
              (self t (int+ i 1) n acc at))))
        ((if (if (= c 42) #t (= c 95)) (%sxm-flank? c (%sxm-byte t (int- i 1) n)) #f)
          (let ((k (%sxm-run t i n c)))
            (let ((e (if (if (<= k 3) (not (%sxm-blank? (%sxm-byte t (int+ i k) n))) #f)
                       (%sxm-emph-close t (int+ i k) n c k) ())))
              (if (null? e) (self t (int+ i k) n acc at)
                (self t e n (pair (list i (int- e i) (lit constant)) acc) at)))))
        (#t (self t (int+ i 1) n acc at))))))

; A line's class, or its pieces.
(def %sxm-line
  (fn (_ t)
    (let ((n (str-byte-len t)))
      (let ((i (%sxm-indent t 0 n 0)))
        (match
          ((let ((h (%sxm-run t i n 35)))
             (if (if (< 0 h) (<= h 6) #f) (%sxm-blank? (%sxm-byte t (int+ i h) n)) #f))
            (lit keyword))
          ((%sxm-rule-line? t i n) (lit punct))
          (#t
            (let ((q ((fn (self j) (if (= (%sxm-byte t j n) 62)
                                     (self (if (= (%sxm-byte t (int+ j 1) n) 32) (int+ j 2) (int+ j 1)))
                                     j))
                      i)))
              (let ((m (%sxm-marker t q n)))
                (let ((at (if (null? m) q (int+ m 1)))
                      (head (List append (if (= q i) () (list (list i (int- q i) (lit punct))))
                                         (if (null? m) () (list (list q (int- m q) (lit punct)))))))
                  (List append head (List reverse (%sxm-inline t at n () at))))))))))))

; A fence's class, or its pieces: its marker lines and its body.
(def %sxm-fence
  (fn (_ t)
    (let ((n (str-byte-len t)))
      (let ((a (%sxm-find t 0 n 10)))
        (if (null? a) (lit punct)
          (let ((closed? (if (> n (int+ a 3))
                           (List includes? (%sxm-byte t (int- n 1) n) (list 96 126)) #f)))
            (let ((b (if closed? (int- n 3) n)))
              (List append (list (list 0 a (lit punct)) (list a (int- b a) (lit string)))
                           (if closed? (list (list b 3 (lit punct))) ())))))))))

(Syntax register!
  (let ((g (Syntax make (lit markdown) (%sxm-rules)
             (list (pair (lit comment) (lit comment)) (pair (lit fence) %sxm-fence)
                   (pair (lit line) %sxm-line)))))
    (g files (list ".md" ".markdown"))
    g))

(doc (provide x/tool/syntax/markdown)
  (note "Imported by x/tool/syntax the first time a .md or .markdown file needs the grammar; (Syntax named 'markdown) loads it.")
  (example "((Syntax named 'markdown) spans \"# Title\\n- a `b` [c](d)\\n\")" "((0 7 'keyword) (8 1 'punct) (12 3 'string) (16 3 'name) (19 3 'string))")
  "Markdown's highlighting grammar: headings, quotes, list markers, fences, code spans, links, emphasis and escapes.")
