; css.x -- the CSS highlighting grammar
;
; x/tool/syntax's catalogue names this module for .css files and imports it
; the first time a file needs the grammar.
;
; A comment is a comment, a string a string, an at-rule (@media) a keyword,
; and a brace, a bracket, a parenthesis, a semicolon, a comma or a
; combinator punctuation.  The rest are words: a word ending in a colon is
; a property and its colon, !important a keyword, a number with or without
; its unit a number, and a # with three, four, six or eight hex digits a
; colour, a number.  In any other word, a .class is a class, a #id a name
; and a :pseudo or ::pseudo a constant, the element's name before them
; plain; a word with none of them, a value's keyword or a function's name,
; is plain.  A word holds its colons, so color:red with no blank reads as
; an element and a pseudo-class, and #add or #bad, all hex, as a colour.
; A comment or a string still open at the end of the text runs to it; a
; comment spans lines, so a text is read from its start.

(module x/tool/syntax/css)
(import x/type/list)
(import x/type/str)
(import x/reader/lexer)
(import x/tool/syntax)
(import x/core/doors char->int int+ int- str-byte-len str-byte-ref)

(def %sxc-contexts
  (list (list (lit dq) 34 92 ()) (list (lit sq) 39 92 ())))

; a space, a tab, a carriage return, a newline and a form feed
(def %sxc-blanks (list 32 9 13 10 12))
(def %sxc-ident (list (pair 48 57) (pair 65 90) (pair 97 122) 95 45 92 (pair 128 255) (pair -128 -1)))
(def %sxc-word (list (pair 48 57) (pair 65 90) (pair 97 122) 95 45 92 46 35 58 37 33 (pair 128 255) (pair -128 -1)))

(def %sxc-rules
  (fn (_)
    (list (Lexer run (lit blank) %sxc-blanks %sxc-blanks)
          (Lexer until (lit comment) "/*" "*/" (lit to-end))
          (Lexer nested (lit string) "\"" (lit dq) %sxc-contexts (lit to-end))
          (Lexer nested (lit string) "'" (lit sq) %sxc-contexts (lit to-end))
          (Lexer pattern (lit at) (list (list "@" 1 1) (list %sxc-ident 1 ())))
          (Lexer table (lit punct)
            (list "{" "}" "(" ")" "[" "]" ";" "," ">" "~" "+" "*" "=" "|" "^=" "$=" "*=" "~=" "|="))
          (Lexer run (lit word) %sxc-word %sxc-word)
          (Lexer any (lit other)))))

(def %sxc-byte (fn (_ t i n) (if (>= i n) -1 (char->int (str-byte-ref t i)))))

(def %sxc-digit? (fn (_ c) (if (>= c 48) (<= c 57) #f)))

(def %sxc-hex?
  (fn (_ c)
    (match ((%sxc-digit? c) #t)
           ((if (>= c 97) (<= c 102) #f) #t)
           (#t (if (>= c 65) (<= c 70) #f)))))

; Whether bytes i to n of t are all hex digits.
(def %sxc-all-hex?
  (fn (self t i n) (if (>= i n) #t (if (%sxc-hex? (%sxc-byte t i n)) (self t (int+ i 1) n) #f))))

; Whether t starts as a number does: a digit, or a point or a sign before
; one, or a sign and a point before one.
(def %sxc-number?
  (fn (_ t n)
    (let ((c (%sxc-byte t 0 n)) (d (%sxc-byte t 1 n)))
      (match ((%sxc-digit? c) #t)
             ((not (List includes? c (list 46 45 43))) #f)
             ((%sxc-digit? d) #t)
             ((= c 46) #f)
             (#t (if (= d 46) (%sxc-digit? (%sxc-byte t 2 n)) #f))))))

(def %sxc-colour?
  (fn (_ t n)
    (if (= (%sxc-byte t 0 n) 35)
      (if (List includes? (int- n 1) (list 3 4 6 8)) (%sxc-all-hex? t 1 n) #f)
      #f)))

; The class of a selector's part by its first byte.
(def %sxc-part
  (fn (_ c) (match ((= c 46) (lit class)) ((= c 35) (lit name)) ((= c 58) (lit constant)) (#t ()))))

; The pieces of a selector word from i, a part starting at each . # or :
; (a :: one part), onto acc in reverse.
(def %sxc-parts
  (fn (self t i n acc)
    (if (>= i n) acc
      (let ((c (%sxc-byte t i n)))
        (let ((e ((fn (me j)
                    (if (if (< j n) (not (List includes? (%sxc-byte t j n) (list 46 35 58))) #f) (me (int+ j 1)) j))
                  (if (if (= c 58) (= (%sxc-byte t (int+ i 1) n) 58) #f) (int+ i 2) (int+ i 1)))))
          (let ((k (%sxc-part c)))
            (self t e n (if (null? k) acc (pair (list i (int- e i) k) acc)))))))))

; A word's class, or its pieces.
(def %sxc-word-class
  (fn (_ t)
    (let ((n (str-byte-len t)))
      (match ((if (< 1 n) (if (= (%sxc-byte t (int- n 1) n) 58) (not (= (%sxc-byte t (int- n 2) n) 58)) #f) #f)
               (list (list 0 (int- n 1) (lit name)) (list (int- n 1) 1 (lit punct))))
             ((= (%sxc-byte t 0 n) 33) (lit keyword))
             ((%sxc-number? t n) (lit number))
             ((%sxc-colour? t n) (lit number))
             (#t (let ((ps (List reverse (%sxc-parts t 0 n ()))))
                   (if (null? ps) () ps)))))))

(Syntax register!
  (let ((g (Syntax make (lit css) (%sxc-rules)
             (list (pair (lit comment) (lit comment)) (pair (lit string) (lit string))
                   (pair (lit at) (lit keyword)) (pair (lit punct) (lit punct))
                   (pair (lit word) %sxc-word-class)))))
    (g files (list ".css"))
    g))

(doc (provide x/tool/syntax/css)
  (note "Imported by x/tool/syntax the first time a .css file needs the grammar; (Syntax named 'css) loads it.")
  (example "((Syntax named 'css) spans \"a.b:hover { color: #fff; }\")" "((1 2 'class) (3 6 'constant) (10 1 'punct) (12 5 'name) (17 1 'punct) (19 4 'number) (23 1 'punct) (25 1 'punct))")
  "The CSS highlighting grammar: at-rules, selectors, properties, numbers, colours, strings and comments.")
