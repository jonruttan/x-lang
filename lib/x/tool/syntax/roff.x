; roff.x -- the roff highlighting grammar
;
; x/tool/syntax's catalogue names this module for manual pages (.1 to .9,
; .man, .mdoc) and roff files (.roff, .ms, .me, .mm, .tr) and imports it the
; first time a file needs the grammar.
;
; A token is a line.  A control line, starting with . or ', has its
; control byte and the request's or macro's name after it a keyword, and a
; "quoted" argument a string.  On every line an escape is an escape: \ and
; one byte, or a font, a string, a register, a glyph or a size with its
; name (\fB, \f(CW, \f[CR], \*(Tm, \n[x], \(em, \[em], \s+2), or one with
; a delimited argument (\w'text', \h'1i'); a \" or a \# and the rest of its
; line is a comment.  Every line starts a token, so a window colours
; without reading from the start.

(module x/tool/syntax/roff)
(import x/type/list)
(import x/reader/lexer)
(import x/tool/syntax)
(import x/core/doors char->int int+ int- str-byte-len str-byte-ref)

(def %sxf-line-bytes (list (pair 0 9) (pair 11 255) (pair -128 -1)))

(def %sxf-rules
  (fn (_)
    (list (Lexer table (lit nl) (list "\n"))
          (Lexer run (lit line) %sxf-line-bytes %sxf-line-bytes)
          (Lexer any (lit other)))))

(def %sxf-byte (fn (_ t i n) (if (< i n) (char->int (str-byte-ref t i)) -1)))
(def %sxf-blank? (fn (_ c) (if (= c 32) #t (= c 9))))
(def %sxf-digit? (fn (_ c) (if (>= c 48) (<= c 57) #f)))

; the escapes taking a name, f n * g F Y m M k V $: one byte, ( and two, or [ to ]
(def %sxf-named (list 102 110 42 103 70 89 109 77 107 86 36))
; the escapes taking an argument between two of a delimiter, w h v l L o D X Z b A B N R S C x
(def %sxf-delimited (list 119 104 118 108 76 111 68 88 90 98 65 66 78 82 83 67 120))

; The offset of byte c from i in t, else n.
(def %sxf-find
  (fn (self t i n c) (if (if (< i n) (not (= (%sxf-byte t i n) c)) #f) (self t (int+ i 1) n c) i)))

(def %sxf-min (fn (_ a b) (if (< a b) a b)))

; The end of a name from i: [ to its ], ( and two bytes, or one byte.
(def %sxf-name-end
  (fn (_ t i n)
    (let ((c (%sxf-byte t i n)))
      (match ((= c 91) (%sxf-min n (int+ (%sxf-find t i n 93) 1)))
             ((= c 40) (%sxf-min n (int+ i 3)))
             (#t (%sxf-min n (int+ i 1)))))))

; The end of a size from i: a sign, then [..], (NN or one or two digits.
(def %sxf-size-end
  (fn (_ t i n)
    (let ((j (if (List includes? (%sxf-byte t i n) (list 43 45)) (int+ i 1) i)))
      (match ((List includes? (%sxf-byte t j n) (list 40 91)) (%sxf-name-end t j n))
             ((not (%sxf-digit? (%sxf-byte t j n))) j)
             ((%sxf-digit? (%sxf-byte t (int+ j 1) n)) (int+ j 2))
             (#t (int+ j 1))))))

; The end of an escape whose \ is at i.
(def %sxf-escape-end
  (fn (_ t i n)
    (let ((c (%sxf-byte t (int+ i 1) n)))
      (match ((< c 0) n)
             ((List includes? c %sxf-named) (%sxf-name-end t (int+ i 2) n))
             ((= c 40) (%sxf-min n (int+ i 4)))
             ((= c 91) (%sxf-min n (int+ (%sxf-find t (int+ i 2) n 93) 1)))
             ((= c 115) (%sxf-size-end t (int+ i 2) n))
             ((List includes? c %sxf-delimited)
               (let ((d (%sxf-byte t (int+ i 2) n)))
                 (if (< d 0) n (%sxf-min n (int+ (%sxf-find t (int+ i 3) n d) 1)))))
             (#t (int+ i 2))))))

; The pieces from i to n, onto acc in reverse: escapes, a comment to the
; end, and on a control line's arguments (args? true) quoted strings.
(def %sxf-scan
  (fn (self t i n args? acc)
    (let ((c (%sxf-byte t i n)))
      (match ((>= i n) acc)
             ((if (= c 92) (List includes? (%sxf-byte t (int+ i 1) n) (list 34 35)) #f)
               (pair (list i (int- n i) (lit comment)) acc))
             ((= c 92)
               (let ((e (%sxf-escape-end t i n)))
                 (self t e n args? (pair (list i (int- e i) (lit escape)) acc))))
             ((if args? (= c 34) #f)
               (let ((e (%sxf-quote-end t (int+ i 1) n)))
                 (self t e n args? (pair (list i (int- e i) (lit string)) acc))))
             (#t (self t (int+ i 1) n args? acc))))))

; The end of a quoted argument from i: past its closing quote, a doubled
; quote one of its bytes, or at the line's end.
(def %sxf-quote-end
  (fn (self t i n)
    (let ((c (%sxf-byte t i n)))
      (match ((>= i n) n)
             ((not (= c 34)) (self t (int+ i 1) n))
             ((= (%sxf-byte t (int+ i 1) n) 34) (self t (int+ i 2) n))
             (#t (int+ i 1))))))

; The end of the blanks from i.
(def %sxf-skip
  (fn (self t i n) (if (%sxf-blank? (%sxf-byte t i n)) (self t (int+ i 1) n) i)))

; The end of a request's name from i: at a blank, a \ or the line's end.
(def %sxf-word-end
  (fn (self t i n)
    (let ((c (%sxf-byte t i n)))
      (if (if (< i n) (not (if (%sxf-blank? c) #t (= c 92))) #f) (self t (int+ i 1) n) i))))

(def %sxf-line
  (fn (_ t)
    (let ((n (str-byte-len t)))
      (List reverse
        (if (List includes? (%sxf-byte t 0 n) (list 46 39))
          (let ((s (%sxf-skip t 1 n)))
            (let ((e (%sxf-word-end t s n)))
              (if (= e s)
                (%sxf-scan t 1 n #f (list (list 0 1 (lit keyword))))
                (%sxf-scan t e n #t (list (list 0 e (lit keyword)))))))
          (%sxf-scan t 0 n #f ()))))))

(Syntax register!
  (let ((g (Syntax make (lit roff) (%sxf-rules) (list (pair (lit line) %sxf-line)))))
    (g sync (fn (_ _ _) #t))
    (g files (list ".1" ".2" ".3" ".4" ".5" ".6" ".7" ".8" ".9" ".man" ".mdoc"
                   ".roff" ".ms" ".me" ".mm" ".tr"))
    g))

(doc (provide x/tool/syntax/roff)
  (note "Imported by x/tool/syntax the first time a manual page or roff file needs the grammar; (Syntax named 'roff) loads it.")
  (example "((Syntax named 'roff) spans \".TH X 1 \\\"2026\\\"\\n\\\\fBx\\\\fR \\\\(em y \\\\\\\" note\\n\")" "((0 3 'keyword) (8 6 'string) (15 3 'escape) (19 3 'escape) (23 4 'escape) (30 7 'comment))")
  "The roff highlighting grammar: requests and macros, their quoted arguments, escapes and comments.")
