; toml.x -- the TOML and INI highlighting grammars
;
; x/tool/syntax's catalogue names this module for .toml files (the toml
; grammar) and .ini and .cfg files (the ini grammar), and imports it the
; first time a file needs either.  The two read alike; each is registered
; under its own name so a modeline can name either.
;
; A comment (# or ;) and a string (" ' """ ''') are tokens of their own,
; and the bytes between them a run.  In a run, a table's header ([t] or
; [[t]], alone on its line) is a keyword; a key, the bytes before the first
; =, a name, and the = punctuation; after it, a bracket, a brace or a comma
; is punctuation, true, false, inf and nan constants, a number, date or
; time a number, and every other word plain.  A ; opens a comment anywhere
; outside a string, as many INI readers have it, so a value holding one is
; cut there.  A string still open at the end of the text runs to it; a
; multi-line string spans lines, so a text is read from its start.

(module x/tool/syntax/toml)
(import x/type/list)
(import x/type/str)
(import x/reader/lexer)
(import x/tool/syntax)
(import x/core/doors char->int int+ int- str-byte-len str-byte-ref str-byte-sub)

(def %sxt-dq (list (list (lit dq) 34 92 ())))
(def %sxt-run-bytes (list (pair 1 9) (pair 11 33) (pair 36 38) (pair 40 58) (pair 60 255) (pair -128 -1)))

(def %sxt-rules
  (fn (_)
    (list (Lexer table (lit nl) (list "\n"))
          (Lexer until (lit comment) "#" "\n" (lit to-end))
          (Lexer until (lit comment) ";" "\n" (lit to-end))
          (Lexer until (lit string) "\"\"\"" "\"\"\"" (lit to-end))
          (Lexer until (lit string) "'''" "'''" (lit to-end))
          (Lexer nested (lit string) "\"" (lit dq) %sxt-dq (lit to-end))
          (Lexer until (lit string) "'" "'" (lit take) (lit to-end))
          (Lexer run (lit run) %sxt-run-bytes %sxt-run-bytes)
          (Lexer any (lit other)))))

; Byte i of t, or -1 at or past n.
(def %sxt-byte (fn (_ t i n) (if (>= i n) -1 (char->int (str-byte-ref t i)))))

(def %sxt-blank? (fn (_ c) (List includes? c (list 32 9 13))))
(def %sxt-punct? (fn (_ c) (List includes? c (list 91 93 123 125 44 61))))
(def %sxt-digit? (fn (_ c) (if (>= c 48) (<= c 57) #f)))

; The offset of the first byte from i that stop? holds, else n.
(def %sxt-until
  (fn (self t i n stop?)
    (if (if (< i n) (not (stop? (%sxt-byte t i n))) #f) (self t (int+ i 1) n stop?) i)))

; The offset of the first byte c from i before n, nil for none.
(def %sxt-find
  (fn (self t i n c)
    (match ((>= i n) ()) ((= (%sxt-byte t i n) c) i) (#t (self t (int+ i 1) n c)))))

; The offset of the last byte c before n from i, nil for none.
(def %sxt-find-last
  (fn (self t i n c)
    (match ((<= n i) ()) ((= (%sxt-byte t (int- n 1) n) c) (int- n 1)) (#t (self t i (int- n 1) c)))))

(def %sxt-word-class
  (fn (_ w)
    (let ((c (char->int (str-byte-ref w 0))) (n (str-byte-len w)))
      (match ((List includes? w (list "true" "false" "inf" "+inf" "-inf" "nan" "+nan" "-nan")) (lit constant))
             ((%sxt-digit? c) (lit number))
             ((if (List includes? c (list 43 45)) (if (< 1 n) (%sxt-digit? (char->int (str-byte-ref w 1))) #f) #f)
               (lit number))
             (#t ())))))

; The pieces of a value from i before n, onto acc in reverse.
(def %sxt-value
  (fn (self t i n acc)
    (let ((c (%sxt-byte t i n)))
      (match ((>= i n) acc)
             ((%sxt-blank? c) (self t (int+ i 1) n acc))
             ((%sxt-punct? c) (self t (int+ i 1) n (pair (list i 1 (lit punct)) acc)))
             (#t (let ((e (%sxt-until t i n (fn (_ b) (if (%sxt-blank? b) #t (%sxt-punct? b))))))
                   (let ((k (%sxt-word-class (str-byte-sub t i (int- e i)))))
                     (self t e n (if (null? k) acc (pair (list i (int- e i) k) acc))))))))))

; A run's pieces: a table's header, else a key and its =, then a value.
(def %sxt-run
  (fn (_ t)
    (let ((n (str-byte-len t)))
      (let ((s (%sxt-until t 0 n (fn (_ b) (not (%sxt-blank? b))))))
        (let ((r (if (= (%sxt-byte t s n) 91) (%sxt-find-last t s n 93) ())))
          (if (if (null? r) #f
                (if (null? (%sxt-find t s r 44))
                  (= (%sxt-until t (int+ r 1) n (fn (_ b) (not (%sxt-blank? b)))) n) #f))
            (list (list s (int- (int+ r 1) s) (lit keyword)))
            (let ((e (%sxt-find t s n 61)))
              (if (null? e) (List reverse (%sxt-value t s n ()))
                (let ((k ((fn (self j) (if (if (< s j) (%sxt-blank? (%sxt-byte t (int- j 1) n)) #f) (self (int- j 1)) j)) e)))
                  (List append
                    (if (< s k) (list (list s (int- k s) (lit name))) ())
                    (list (list e 1 (lit punct)))
                    (List reverse (%sxt-value t (int+ e 1) n ()))))))))))))

(def %sxt-classes
  (list (pair (lit comment) (lit comment)) (pair (lit string) (lit string)) (pair (lit run) %sxt-run)))

(Syntax register!
  (let ((g (Syntax make (lit toml) (%sxt-rules) %sxt-classes)))
    (g end "\n")
    (g files (list ".toml"))
    g))

(Syntax register!
  (let ((g (Syntax make (lit ini) (%sxt-rules) %sxt-classes)))
    (g end "\n")
    (g files (list ".ini" ".cfg"))
    g))

(doc (provide x/tool/syntax/toml)
  (note "Imported by x/tool/syntax the first time a .toml, .ini or .cfg file needs a grammar; (Syntax named 'toml) and (Syntax named 'ini) load it.")
  (example "((Syntax named 'toml) spans \"[t]\\nk = [1, true] # c\\n\")" "((0 3 'keyword) (4 1 'name) (6 1 'punct) (8 1 'punct) (9 1 'number) (10 1 'punct) (12 4 'constant) (16 1 'punct) (18 3 'comment))")
  "The TOML and INI highlighting grammars: table headers, keys, strings, numbers, constants and comments.")
