; json.x -- the JSON highlighting grammar
;
; x/tool/syntax's catalogue names this module for .json files and imports
; it the first time a file needs the grammar.
;
; A token is a word: the bytes up to a blank, a comma or a bracket, a
; string inside it read whole, so a comma or a bracket in a string is part
; of it.  A string followed by a colon is a member's name; any other string
; is a string.  true, false and null are constants, a number is a number,
; a colon, a comma or a bracket is punctuation, and every other word is an
; error.  A string still open at the end of the text runs to it, as a line
; being typed leaves one.  No string holds a newline, so every line starts
; outside one.

(module x/tool/syntax/json)
(import x/type/list)
(import x/type/str)
(import x/reader/lexer)
(import x/tool/syntax)
(import x/core/doors char->int int+ int- str-byte-len str-byte-ref str-byte-sub)

(def %sxj-byte (fn (_ s i) (char->int (str-byte-ref s i))))

(def %sxj-contexts
  (list (list (lit w) () () (list (pair "\"" (lit dq))))
        (list (lit dq) 34 92 ())))

(def %sxj-rules
  (fn (_)
    (list (Lexer run (lit blank) " \t\r\n" " \t\r\n")
          (Lexer table (lit punct) (list "{" "}" "[" "]" ","))
          (Lexer word (lit word) (lit w) %sxj-contexts " \t\r\n{}[]," (lit to-end)))))

; The offset past the string that opens at i, or the text's end.
(def %sxj-string-end
  (fn (self s i n)
    (match ((>= i n) n)
           ((= (%sxj-byte s i) 92) (self s (int+ i 2) n))
           ((= (%sxj-byte s i) 34) (int+ i 1))
           (#t (self s (int+ i 1) n)))))

; Whether bytes i on of t are a number's: digits, signs, a point, an e.
(def %sxj-number-bytes?
  (fn (self t i n)
    (if (>= i n) #t
      (let ((c (%sxj-byte t i)))
        (if (if (if (>= c 48) (<= c 57) #f) #t (List includes? c (list 43 45 46 69 101)))
          (self t (int+ i 1) n)
          #f)))))

(def %sxj-number?
  (fn (_ t)
    (let ((c (%sxj-byte t 0)))
      (if (if (= c 45) #t (if (>= c 48) (<= c 57) #f))
        (%sxj-number-bytes? t 1 (str-byte-len t))
        #f))))

; A scalar's class: a constant, a number, a lone colon, else an error.
(def %sxj-scalar
  (fn (_ t)
    (match ((List includes? t (list "true" "false" "null")) (lit constant))
           ((str=? t ":") (lit punct))
           ((%sxj-number? t) (lit number))
           (#t (lit error)))))

; A word's class, or its pieces when it is a string and more: a member's
; name and its colon, then whatever follows the colon.
(def %sxj-word
  (fn (_ t)
    (let ((n (str-byte-len t)))
     (if (not (= (%sxj-byte t 0) 34)) (%sxj-scalar t)
      (let ((e (%sxj-string-end t 1 n)))
        (match ((= e n) (lit string))
               ((not (= (%sxj-byte t e) 58))
                 (list (list 0 e (lit string)) (list e (int- n e) (lit error))))
               ((= (int+ e 1) n) (list (list 0 e (lit name)) (list e 1 (lit punct))))
               (#t (let ((more (str-byte-sub t (int+ e 1) (int- n (int+ e 1)))))
                     (list (list 0 e (lit name)) (list e 1 (lit punct))
                           (list (int+ e 1) (str-byte-len more)
                                 (if (= (%sxj-byte more 0) 34)
                                   (if (= (%sxj-string-end more 1 (str-byte-len more)) (str-byte-len more))
                                     (lit string) (lit error))
                                   (%sxj-scalar more))))))))))))

(Syntax register!
  (let ((g (Syntax make (lit json) (%sxj-rules)
             (list (pair (lit punct) (lit punct)) (pair (lit word) %sxj-word)))))
    (g sync (fn (_ _ _) #t))
    (g files (list ".json"))
    g))

(doc (provide x/tool/syntax/json)
  (note "Imported by x/tool/syntax the first time a .json file needs the grammar; (Syntax named 'json) loads it.")
  (example "((Syntax named 'json) spans \"{\\\"a\\\": [1, true]}\")" "((0 1 'punct) (1 3 'name) (4 1 'punct) (6 1 'punct) (7 1 'number) (8 1 'punct) (10 4 'constant) (14 1 'punct) (15 1 'punct))")
  "JSON's highlighting grammar: names, strings, numbers, constants and punctuation.")
