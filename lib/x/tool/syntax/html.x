; html.x -- the HTML and XML highlighting grammars
;
; x/tool/syntax's catalogue names this module for HTML files (the html
; grammar) and XML ones (the xml grammar), and imports it the first time a
; file needs either.  The two share their rules and classes; XML has no
; script or style element, so its every < opens a tag, and an element's
; name may start with _ or :.
;
; In a tag, the < and > and a / are punctuation, the element's name a
; keyword, an attribute's name a name, its = punctuation and its value,
; quoted or not, a string.  A declaration (<!DOCTYPE ...>) or a processing
; instruction (<?...?>) is a keyword, a comment a comment, a CDATA section
; a string and a character reference (&amp; &#38;) an escape.  A script or
; style element's tags are coloured and its body left plain, so a < in the
; body opens no tag.  A < before a byte that starts no tag is text.
;
; A comment, a CDATA section, a script and a style span lines, so a text is
; read from its start, and one still open at the end of the text runs to
; it.  A tag still open at the end is text, as is a lone < in text.

(module x/tool/syntax/html)
(import x/type/list)
(import x/type/str)
(import x/reader/lexer)
(import x/tool/syntax)
(import x/core/doors char->int int+ int- str-byte-len str-byte-ref)

(def %sxh-contexts
  (list (list (lit tag) 62 () (list (pair "\"" (lit dq)) (pair "'" (lit sq))))
        (list (lit dq) 34 () ())
        (list (lit sq) 39 () ())))

(def %sxh-text-bytes (list (pair 1 37) (pair 39 59) (pair 61 255) (pair -128 -1)))
(def %sxh-alnum (list (pair 48 57) (pair 65 90) (pair 97 122)))

; HTML's rules with raw? true, XML's without the script and style rules.
(def %sxh-rules
  (fn (_ raw?)
    (List append
      (list (Lexer until (lit comment) "<!--" "-->" (lit to-end))
            (Lexer until (lit cdata) "<![CDATA[" "]]>" (lit to-end)))
      (if raw?
        (list (Lexer until (lit raw) "<script" "</script>" (lit to-end))
              (Lexer until (lit raw) "<SCRIPT" "</SCRIPT>" (lit to-end))
              (Lexer until (lit raw) "<style" "</style>" (lit to-end))
              (Lexer until (lit raw) "<STYLE" "</STYLE>" (lit to-end)))
        ())
      (list (Lexer nested (lit tag) "<" (lit tag) %sxh-contexts)
            (Lexer pattern (lit ref) (list (list "&" 1 1) (list "#" 0 1) (list %sxh-alnum 1 ()) (list ";" 1 1)))
            (Lexer run (lit text) %sxh-text-bytes %sxh-text-bytes)
            (Lexer any (lit other))))))

; Byte i of t, or -1 at or past e.
(def %sxh-byte (fn (_ t i e) (if (>= i e) -1 (char->int (str-byte-ref t i)))))

(def %sxh-blank? (fn (_ c) (List includes? c (list 32 9 10 13 12))))

; A byte that starts an element's name: a letter, or XML's _ and :.
(def %sxh-letter?
  (fn (_ c) (if (if (>= c 65) (<= c 90) #f) #t (if (if (>= c 97) (<= c 122) #f) #t (List includes? c (list 95 58))))))

; The offset of the first byte from i before e that stop? holds, else e.
(def %sxh-until
  (fn (self t i e stop?)
    (if (if (< i e) (not (stop? (%sxh-byte t i e))) #f) (self t (int+ i 1) e stop?) i)))

(def %sxh-name-end?
  (fn (_ c) (if (%sxh-blank? c) #t (List includes? c (list 61 62 47)))))

; The pieces of a tag's attributes from i before e, onto acc in reverse.
(def %sxh-attrs
  (fn (self t i e acc)
    (let ((c (%sxh-byte t i e)))
      (match
        ((>= i e) acc)
        ((%sxh-blank? c) (self t (int+ i 1) e acc))
        ((if (= c 62) #t (= c 47)) (self t (int+ i 1) e (pair (list i 1 (lit punct)) acc)))
        ((= c 61)
          (let ((q (%sxh-byte t (int+ i 1) e)) (p (list i 1 (lit punct))))
            (if (if (= q 34) #t (= q 39))
              (let ((z (%sxh-until t (int+ i 2) e (fn (_ b) (= b q)))))
                (let ((v (if (< z e) (int+ z 1) e)))
                  (self t v e (pair (list (int+ i 1) (int- v (int+ i 1)) (lit string)) (pair p acc)))))
              (let ((v (%sxh-until t (int+ i 1) e (fn (_ b) (if (%sxh-blank? b) #t (= b 62))))))
                (self t v e (if (= v (int+ i 1)) (pair p acc)
                              (pair (list (int+ i 1) (int- v (int+ i 1)) (lit string)) (pair p acc))))))))
        (#t (let ((v (%sxh-until t (int+ i 1) e %sxh-name-end?)))
              (self t v e (pair (list i (int- v i) (lit name)) acc))))))))

; The pieces of the tag from s before e: nil for a < that starts none.
(def %sxh-tag-pieces
  (fn (_ t s e)
    (let ((c (%sxh-byte t (int+ s 1) e)))
      (match
        ((if (= c 33) #t (= c 63)) (list (list s (int- e s) (lit keyword))))
        ((%sxh-letter? c)
          (let ((v (%sxh-until t (int+ s 1) e %sxh-name-end?)))
            (pair (list s 1 (lit punct))
                  (pair (list (int+ s 1) (int- v (int+ s 1)) (lit keyword))
                        (List reverse (%sxh-attrs t v e ()))))))
        ((if (= c 47) (%sxh-letter? (%sxh-byte t (int+ s 2) e)) #f)
          (let ((v (%sxh-until t (int+ s 2) e %sxh-name-end?)))
            (pair (list s 2 (lit punct))
                  (pair (list (int+ s 2) (int- v (int+ s 2)) (lit keyword))
                        (List reverse (%sxh-attrs t v e ()))))))
        (#t ())))))

(def %sxh-tag (fn (_ t) (%sxh-tag-pieces t 0 (str-byte-len t))))

; A script or style element: its open tag's pieces, its body plain, and its
; close tag's pieces when it has one.
(def %sxh-raw
  (fn (_ t)
    (let ((n (str-byte-len t)))
      (let ((o (%sxh-until t 0 n (fn (_ b) (= b 62)))))
        (let ((open (%sxh-tag-pieces t 0 (if (< o n) (int+ o 1) n)))
              (c ((fn (self i) (match ((<= i o) ())
                                      ((if (= (%sxh-byte t i n) 60) (= (%sxh-byte t (int+ i 1) n) 47) #f) i)
                                      (#t (self (int- i 1)))))
                  (int- n 1))))
          (if (if (null? c) #t (not (= (%sxh-byte t (int- n 1) n) 62))) open
            (List append open (%sxh-tag-pieces t c n))))))))

(def %sxh-classes
  (list (pair (lit comment) (lit comment)) (pair (lit cdata) (lit string))
        (pair (lit raw) %sxh-raw) (pair (lit tag) %sxh-tag)
        (pair (lit ref) (lit escape))))

(Syntax register!
  (let ((g (Syntax make (lit html) (%sxh-rules #t) %sxh-classes)))
    (g files (list ".html" ".htm" ".xhtml"))
    g))

(Syntax register!
  (let ((g (Syntax make (lit xml) (%sxh-rules #f) %sxh-classes)))
    (g files (list ".xml" ".svg" ".xsl" ".xslt" ".xsd" ".plist"))
    g))

(doc (provide x/tool/syntax/html)
  (note "Imported by x/tool/syntax the first time an HTML or XML file needs a grammar; (Syntax named 'html) and (Syntax named 'xml) load it.")
  (example "((Syntax named 'html) spans \"<a href=\\\"x\\\">&amp;</a>\")" "((0 1 'punct) (1 1 'keyword) (3 4 'name) (7 1 'punct) (8 3 'string) (11 1 'punct) (12 5 'escape) (17 2 'punct) (19 1 'keyword) (20 1 'punct))")
  (example "((Syntax named 'xml) spans \"<?xml?><x:a b='1'/>\")" "((0 7 'keyword) (7 1 'punct) (8 3 'keyword) (12 1 'name) (13 1 'punct) (14 3 'string) (17 1 'punct) (18 1 'punct))")
  "HTML's and XML's highlighting grammars: tags, attributes, comments, declarations and character references.")
