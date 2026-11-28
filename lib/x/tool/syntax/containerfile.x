; containerfile.x -- the Containerfile highlighting grammar
;
; x/tool/syntax's catalogue names this module for files named Containerfile
; or Dockerfile and for .containerfile and .dockerfile files, and imports it
; the first time a file needs the grammar.
;
; A token is a line.  A line whose first byte past its blanks is a # is a
; comment, a parser directive (# syntax=...) too.  An instruction, the
; line's first word when it is one in any case, is a keyword, and FROM's AS
; too.  After it, a --flag is a constant up to its =, a "string" or a
; 'string' a string, a $NAME or ${NAME} a name, a bracket or a comma of a
; JSON form punctuation, and a \ ending the line, which continues the
; instruction, an operator.  A line alone cannot tell it follows a \, so a
; continued line whose first word is an instruction's reads as one.  Every
; line starts a token, so a window colours without reading from the start.

(module x/tool/syntax/containerfile)
(import x/type/list)
(import x/type/str)
(import x/reader/lexer)
(import x/tool/syntax)
(import x/core/doors char->int int+ int- str-byte-len str-byte-ref)

(def %sxk-instructions
  (list "ADD" "ARG" "CMD" "COPY" "ENTRYPOINT" "ENV" "EXPOSE" "FROM"
        "HEALTHCHECK" "LABEL" "MAINTAINER" "ONBUILD" "RUN" "SHELL"
        "STOPSIGNAL" "USER" "VOLUME" "WORKDIR"))

(def %sxk-line-bytes (list (pair 0 9) (pair 11 255) (pair -128 -1)))

(def %sxk-rules
  (fn (_)
    (list (Lexer table (lit nl) (list "\n"))
          (Lexer run (lit line) %sxk-line-bytes %sxk-line-bytes)
          (Lexer any (lit other)))))

(def %sxk-byte (fn (_ t i n) (if (< i n) (char->int (str-byte-ref t i)) -1)))
(def %sxk-blank? (fn (_ c) (List includes? c (list 32 9 13))))
(def %sxk-name? (fn (_ c) (match ((if (>= c 65) (<= c 90) #f) #t) ((if (>= c 97) (<= c 122) #f) #t)
                                 ((if (>= c 48) (<= c 57) #f) #t) (#t (= c 95)))))

(def %sxk-skip
  (fn (self t i n) (if (%sxk-blank? (%sxk-byte t i n)) (self t (int+ i 1) n) i)))

; The end of a word from i: at a blank or the line's end.
(def %sxk-word-end
  (fn (self t i n) (if (if (< i n) (not (%sxk-blank? (%sxk-byte t i n))) #f) (self t (int+ i 1) n) i)))

; The end of the bytes from i that pred holds.
(def %sxk-while
  (fn (self pred t i n) (if (if (< i n) (pred (%sxk-byte t i n)) #f) (self pred t (int+ i 1) n) i)))

; The end of a string whose quote q is at i: past its closing quote, a \
; taking the next byte, or at the line's end.
(def %sxk-string-end
  (fn (self t i n q)
    (let ((c (%sxk-byte t i n)))
      (match ((>= i n) n)
             ((= c 92) (self t (int+ i 2) n q))
             ((= c q) (int+ i 1))
             (#t (self t (int+ i 1) n q))))))

; The end of a variable whose $ is at i: ${...} to its }, else a name.
(def %sxk-variable-end
  (fn (self t i n)
    (if (= (%sxk-byte t (int+ i 1) n) 123)
      ((fn (me j) (match ((>= j n) n) ((= (%sxk-byte t j n) 125) (int+ j 1)) (#t (me (int+ j 1)))))
       (int+ i 2))
      (%sxk-while %sxk-name? t (int+ i 1) n))))

; Whether i starts a word: the line's start or a blank before it.
(def %sxk-word-start? (fn (_ t i n) (if (= i 0) #t (%sxk-blank? (%sxk-byte t (int- i 1) n)))))

; The pieces of an instruction's arguments from i, onto acc in reverse;
; from? for FROM's, whose AS is a keyword.
(def %sxk-args
  (fn (self t i n from? acc)
    (let ((c (%sxk-byte t i n)))
      (match ((>= i n) acc)
             ((List includes? c (list 34 39))
               (let ((e (%sxk-string-end t (int+ i 1) n c)))
                 (self t e n from? (pair (list i (int- e i) (lit string)) acc))))
             ((if (= c 36) (if (= (%sxk-byte t (int+ i 1) n) 123) #t (%sxk-name? (%sxk-byte t (int+ i 1) n))) #f)
               (let ((e (%sxk-variable-end t i n)))
                 (self t e n from? (pair (list i (int- e i) (lit name)) acc))))
             ((if (= c 45) (if (= (%sxk-byte t (int+ i 1) n) 45) (%sxk-word-start? t i n) #f) #f)
               (let ((e (%sxk-while (fn (_ b) (if (%sxk-blank? b) #f (not (= b 61)))) t i n)))
                 (self t e n from? (pair (list i (int- e i) (lit constant)) acc))))
             ((if (= c 92) (= (%sxk-skip t (int+ i 1) n) n) #f)
               (self t n n from? (pair (list i 1 (lit operator)) acc)))
             ((List includes? c (list 91 93 44))
               (self t (int+ i 1) n from? (pair (list i 1 (lit punct)) acc)))
             ((if from? (if (%sxk-word-start? t i n) (Str8 =? (Str8 upcase (Str8 sub i (int- (%sxk-word-end t i n) i) t)) "AS") #f) #f)
               (self t (int+ i 2) n from? (pair (list i 2 (lit keyword)) acc)))
             (#t (self t (int+ i 1) n from? acc))))))

(def %sxk-line
  (fn (_ t)
    (let ((n (str-byte-len t)))
      (let ((s (%sxk-skip t 0 n)))
        (let ((e (%sxk-word-end t s n)))
          (List reverse
            (match ((= (%sxk-byte t s n) 35) (list (list s (int- n s) (lit comment))))
                   ((List includes? (Str8 upcase (Str8 sub s (int- e s) t)) %sxk-instructions)
                     (%sxk-args t e n (Str8 =? (Str8 upcase (Str8 sub s (int- e s) t)) "FROM") (list (list s (int- e s) (lit keyword)))))
                   (#t (%sxk-args t s n #f ())))))))))

(Syntax register!
  (let ((g (Syntax make (lit containerfile) (%sxk-rules) (list (pair (lit line) %sxk-line)))))
    (g sync (fn (_ _ _) #t))
    (g files (list ".containerfile" ".dockerfile"))
    (g names (list "Containerfile" "Dockerfile"))
    g))

(doc (provide x/tool/syntax/containerfile)
  (note "Imported by x/tool/syntax the first time a Containerfile, a Dockerfile or a .containerfile or .dockerfile file needs the grammar; (Syntax named 'containerfile) loads it.")
  (example "((Syntax named 'containerfile) spans \"# base\\nFROM alpine AS b\\nRUN echo \\\"$HOME\\\" \\\\\\n\")" "((0 6 'comment) (7 4 'keyword) (19 2 'keyword) (24 3 'keyword) (33 7 'string) (41 1 'operator))")
  "The Containerfile highlighting grammar: instructions, flags, strings, variables and comments.")
