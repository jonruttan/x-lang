; codec/markdown-write.x -- MarkdownWrite: a document as Markdown text.
;
; (MarkdownWrite text BLOCKS) answers CommonMark that (Markdown parse)
; reads back as the same document tree (x/codec/document): a heading as
; number signs, emphasis in asterisks, code in backticks and fences long
; enough for what they hold, a quote led by >, a list's items by - or their
; numbers, and a blank line between blocks, none in a tight list.
;
; Text is escaped so it stays text: a backslash before each character
; Markdown would read as markup, an ampersand that would begin a character
; reference, and whatever at the start of a line would begin a heading, a
; quote, a list, a rule or a fence.  A line's leading spaces are dropped,
; as the reader drops them.
;
; Raw HTML is written as it is.  A form's field is its value.

(module x/codec/markdown-write)
(import x/type/class)
(import x/core/list)

(import x/core/doors int+ int- int< int= str-byte-len str-byte-ref str-byte-sub)

(def %mw-rep
  (fn (self s n) (match ((int< n 1) "") (#t (Str8 append s (self s (int- n 1)))))))
(def %mw-lines
  (fn (_ s) (match ((null? (Str8 index-of "\n" s)) (list s)) (#t (Str8 split "\n" s)))))
(def %mw-at (fn (_ s i) (match ((int< i (str-byte-len s)) (str-byte-ref s i)) (#t 0))))
(def %mw-alnum?
  (fn (_ c)
    (match ((int< c 48) #f) ((int< c 58) #t) ((int< c 65) #f) ((int< c 91) #t) ((int< c 97) #f) ((int< c 123) #t)
           (#t #f))))
(def %mw-digit? (fn (_ c) (match ((int< c 48) #f) ((int< c 58) #t) (#t #f))))

; Whether the bytes of S from I spell the rest of a character reference:
; a name or a number, then a semicolon.
(def %mw-reference?
  (fn (self s i n)
    (def c (%mw-at s i))
    (match ((int= c 59) (int< 0 n))
           ((int< 32 n) #f)
           ((match ((%mw-alnum? c) #t) (#t (match ((int= n 0) (int= c 35)) (#t #f)))) (self s (int+ i 1) (int+ n 1)))
           (#t #f))))
; S with each ampersand that would begin a character reference escaped.
(def %mw-ampersands
  (fn (self s from)
    (def at (Str8 index-of "&" (str-byte-sub s from (int- (str-byte-len s) from))))
    (match ((null? at) (str-byte-sub s from (int- (str-byte-len s) from)))
           (#t ((fn (_ i)
                  (Str8 append (str-byte-sub s from (int- i from))
                               (match ((%mw-reference? s (int+ i 1) 0) "\\&") (#t "&"))
                               (self s (int+ i 1))))
                (int+ from at))))))
; Text with the characters Markdown reads as markup escaped.
(def %mw-escape
  (fn (_ s)
    (def swap (fn (_ c t) (match ((null? (Str8 index-of c t)) t) (#t (Str8 replace c (Str8 append "\\" c) t)))))
    (%mw-ampersands
      (swap "<" (swap "]" (swap "[" (swap "_" (swap "*" (swap "`" (swap "\\" s)))))))
      0)))

(def %mw-left (fn (self s i) (match ((int= (%mw-at s i) 32) (self s (int+ i 1))) (#t i))))
(def %mw-right
  (fn (self s n) (match ((int< n 1) 0) ((int= (%mw-at s (int- n 1)) 32) (self s (int- n 1))) (#t n))))
; Whether S is one character C and no other, as a setext underline is.
(def %mw-all?
  (fn (self s c i)
    (match ((int= i (str-byte-len s)) (int< 0 i)) ((int= (%mw-at s i) c) (self s c (int+ i 1))) (#t #f))))
(def %mw-digits (fn (self s i) (match ((%mw-digit? (%mw-at s i)) (self s (int+ i 1))) (#t i))))
(def %mw-gap? (fn (_ c) (match ((int= c 32) #t) ((int= c 0) #t) (#t #f))))
; A paragraph's line, its leading spaces dropped, escaped where its start
; would begin a block.
(def %mw-line
  (fn (_ line)
    (def s ((fn (_ i) (str-byte-sub line i (int- (str-byte-len line) i))) (%mw-left line 0)))
    (def c (%mw-at s 0))
    (def d (%mw-digits s 0))
    (match
      ((match ((int= c 35) #t) ((int= c 62) #t) ((%mw-all? s 61 0) #t) ((%mw-all? s 45 0) #t)
              ((Str8 starts? "~~~" s) #t)
              ((match ((int= c 43) #t) ((int= c 45) #t) (#t #f)) (%mw-gap? (%mw-at s 1)))
              (#t #f))
        (Str8 append "\\" s))
      ((match ((int< 0 d) (match ((match ((int= (%mw-at s d) 46) #t) ((int= (%mw-at s d) 41) #t) (#t #f))
                                   (%mw-gap? (%mw-at s (int+ d 1))))
                                  (#t #f)))
              (#t #f))
        (Str8 append (str-byte-sub s 0 d) "\\" (str-byte-sub s d (int- (str-byte-len s) d))))
      (#t s))))

; The longest run of the character C in S.
(def %mw-run
  (fn (self s c i run best)
    (match ((int= i (str-byte-len s)) (match ((int< best run) run) (#t best)))
           ((int= (%mw-at s i) c) (self s c (int+ i 1) (int+ run 1) best))
           (#t (self s c (int+ i 1) 0 (match ((int< best run) run) (#t best)))))))
(def %mw-code
  (fn (_ text)
    (def ticks (%mw-rep "`" (int+ (%mw-run text 96 0 0 0) 1)))
    (def pad (match ((str=? text "") "")
                    ((match ((int= (%mw-at text 0) 96) #t) (#t (int= (%mw-at text (int- (str-byte-len text) 1)) 96))) " ")
                    (#t "")))
    (Str8 append ticks pad text pad ticks)))
; A destination, in angle brackets when it could not stand bare.
(def %mw-destination
  (fn (_ d)
    (match ((match ((str=? d "") #t) ((not (null? (Str8 index-of " " d))) #t) ((not (null? (Str8 index-of "(" d))) #t)
                   (#t (not (null? (Str8 index-of ")" d)))))
             (Str8 append "<" (Str8 replace ">" "\\>" (Str8 replace "<" "\\<" d)) ">"))
           (#t d))))
(def %mw-target
  (fn (_ x)
    (Str8 append "(" (%mw-destination (List ref 1 x))
      (match ((null? (List ref 2 x)) "")
             (#t (Str8 append " \"" (Str8 replace "\"" "\\\"" (Str8 replace "\\" "\\\\" (List ref 2 x))) "\"")))
      ")")))
; MARK around TEXT, the spaces at TEXT's ends kept outside the marks, where
; a mark beside a space would not open or close.
(def %mw-marked
  (fn (_ mark text)
    (def a (%mw-left text 0))
    (def b (%mw-right text (str-byte-len text)))
    (match ((int< a b)
             (Str8 append (str-byte-sub text 0 a) mark (str-byte-sub text a (int- b a)) mark
                          (str-byte-sub text b (int- (str-byte-len text) b))))
           (#t text))))
(def %mw-inlines
  (fn (self inlines)
    (Str8 join ""
      (List map
        (fn (_ x)
          (def t (match ((str? x) ()) (#t (first x))))
          (match
            ((str? x) (%mw-escape x))
            ((eq? t (lit emph)) (%mw-marked "*" (self (List ref 1 x))))
            ((eq? t (lit strong)) (%mw-marked "**" (self (List ref 1 x))))
            ((eq? t (lit code)) (%mw-code (List ref 1 x)))
            ((eq? t (lit softbreak)) "\n")
            ((eq? t (lit hardbreak)) "\\\n")
            ((eq? t (lit html-inline)) (List ref 1 x))
            ((eq? t (lit link)) (Str8 append "[" (self (List ref 3 x)) "]" (%mw-target x)))
            ((eq? t (lit image)) (Str8 append "![" (self (List ref 3 x)) "]" (%mw-target x)))
            ((eq? t (lit field)) (match ((str? (List ref 3 x)) (%mw-escape (List ref 3 x))) (#t "")))
            (#t "")))
        inlines))))

; TEXT with FIRST before its first line and REST before each other, a
; blank line given REST without the spaces at its end.
(def %mw-prefixed
  (fn (_ text lead more)
    (def bare (str-byte-sub more 0 (%mw-right more (str-byte-len more))))
    (def lines (%mw-lines text))
    (Str8 join "\n"
      (pair (Str8 append lead (first lines))
            (List map (fn (_ l) (match ((str=? l "") bare) (#t (Str8 append more l)))) (rest lines))))))
(def %mw-fenced
  (fn (_ info text)
    (def fence (%mw-rep "`" ((fn (_ n) (match ((int< n 3) 3) (#t (int+ n 1)))) (%mw-run text 96 0 0 0))))
    (Str8 append fence info "\n" text
      (match ((str=? text "") "") ((int= (%mw-at text (int- (str-byte-len text) 1)) 10) "") (#t "\n"))
      fence)))
(def %mw-left-trimmed (fn (_ s) ((fn (_ i) (str-byte-sub s i (int- (str-byte-len s) i))) (%mw-left s 0))))
; Each of ITEMS through F with its marker: "- ", or its number from N.
(def %mw-items
  (fn (self f items n)
    (match ((null? items) ())
           ((null? n) (pair (f (first items) "- ") (self f (rest items) ())))
           (#t (pair (f (first items) (Str8 append (Str8 str n) ". ")) (self f (rest items) (int+ n 1)))))))
(def %mw-block
  (fn (self b)
    (def t (first b))
    (def all (fn (_ blocks gap) (Str8 join gap (List map (fn (_ k) (self k)) blocks))))
    (match
      ((eq? t (lit heading))
        (Str8 append (%mw-rep "#" (List ref 1 b)) " "
          (Str8 join " " (List map %mw-left-trimmed (%mw-lines (%mw-inlines (List ref 2 b)))))))
      ((eq? t (lit paragraph)) (Str8 join "\n" (List map %mw-line (%mw-lines (%mw-inlines (List ref 1 b))))))
      ((eq? t (lit code-block)) (%mw-fenced (List ref 1 b) (List ref 2 b)))
      ((eq? t (lit block-quote)) (%mw-prefixed (all (List ref 1 b) "\n\n") "> " "> "))
      ((eq? t (lit thematic-break)) "---")
      ((eq? t (lit html-block))
        ((fn (_ s) (str-byte-sub s 0 (match ((int= (%mw-at s (int- (str-byte-len s) 1)) 10) (int- (str-byte-len s) 1)) (#t (str-byte-len s)))))
         (List ref 1 b)))
      ((eq? t (lit list))
        ((fn (_ gap)
           (Str8 join gap
             (%mw-items
               (fn (_ item mark) (%mw-prefixed (all item gap) mark (%mw-rep " " (str-byte-len mark))))
               (List ref 4 b)
               (match ((List ref 1 b) (match ((null? (List ref 2 b)) 1) (#t (List ref 2 b)))) (#t ())))))
         (match ((List ref 3 b) "\n") (#t "\n\n"))))
      (#t ""))))
(def-class MarkdownWrite ()
  (doc "A document as Markdown: (MarkdownWrite text blocks) writes the document tree (x/codec/document) as CommonMark that (Markdown parse) reads back as the same tree."
    (example "(MarkdownWrite text (list (list 'heading 1 (list \"Hi \" (list 'emph (list \"there\"))))))" "\"# Hi *there*\\n\"")
    (see text))
  (static
    (method text (self (param blocks LIST "A document's blocks"))
      (doc "The blocks as Markdown text: headings as number signs, emph and strong in asterisks, code in backticks, a code block fenced, a quote led by >, list items by - or their numbers, a rule as ---, a blank line between blocks and none in a tight list. Text is escaped where Markdown would read it as markup. Raw HTML is written as it is and a form's field is its value."
        (returns STRING "Markdown text, empty for no blocks")
        (example "(MarkdownWrite text (list (list 'paragraph (list \"2 * 3 \" (list 'code \"x\") \" \" (list 'link \"/u\" () (list \"here\"))))))" "\"2 \\\\* 3 `x` [here](/u)\\n\"")
        (example "(MarkdownWrite text (list (list 'list #t 3 #t (list (list (list 'paragraph (list \"a\"))) (list (list 'paragraph (list \"b\")))))))" "\"3. a\\n4. b\\n\""))
      (match ((null? blocks) "")
             (#t (Str8 append (Str8 join "\n\n" (List map (fn (_ b) (%mw-block b)) blocks)) "\n"))))))

(doc (provide x/codec/markdown-write MarkdownWrite)
  (example "(do (import x/codec/markdown) (def b (Markdown parse \"> a **b**\\n\\n- c\\n- d\")) (equal? b (Markdown parse (MarkdownWrite text b))))" "#t")
  (see Markdown)
  "A document tree written as CommonMark text, homed on the MarkdownWrite class.")
