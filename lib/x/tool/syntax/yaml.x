; yaml.x -- the YAML highlighting grammar
;
; x/tool/syntax's catalogue names this module for .yaml and .yml files and
; imports it the first time a file needs the grammar.
;
; A token is a comment, a quoted string, a flow collection's bracket or
; comma, or a word: the bytes up to a blank, a newline or one of those.  A
; word ending in a colon is a mapping's key and its colon; a dash, a
; question mark, a colon or a block scalar's indicator (| or >, with its
; chomping and indent) alone is punctuation; an anchor (&a) or an alias
; (*a) is a private, a tag (!t) a class, a directive (%YAML) a keyword, a
; document's start or end (--- ...) punctuation; true, false, null, ~ and
; the other words YAML 1.1 read as booleans are constants, and a number is
; a number.  Every other word is plain.  A quoted string still open at the
; end of the text runs to it.  A quoted string and a block scalar span
; lines, so a text is read from its start.

(module x/tool/syntax/yaml)
(import x/type/list)
(import x/type/str)
(import x/reader/lexer)
(import x/tool/syntax)
(import x/core/doors char->int int+ int- str-byte-len str-byte-ref)

(def %sxy-dq (list (list (lit dq) 34 92 ())))
(def %sxy-word-bytes (list (pair 1 8) (pair 11 12) (pair 14 31) (pair 33 43) (pair 45 90) 92 (pair 94 122) 124 (pair 126 255) (pair -128 -1)))

(def %sxy-rules
  (fn (_)
    (list (Lexer run (lit blank) " \t\r" " \t\r")
          (Lexer table (lit nl) (list "\n"))
          (Lexer until (lit comment) "#" "\n" (lit to-end))
          (Lexer until (lit string) "'" "'" (lit take) (lit to-end))
          (Lexer nested (lit string) "\"" (lit dq) %sxy-dq (lit to-end))
          (Lexer table (lit punct) (list "[" "]" "{" "}" ","))
          (Lexer run (lit word) %sxy-word-bytes %sxy-word-bytes)
          (Lexer any (lit other)))))

(def %sxy-constants
  (list "true" "false" "null" "~" "True" "False" "Null" "TRUE" "FALSE" "NULL"
        "yes" "no" "on" "off" "Yes" "No" "On" "Off" "YES" "NO" "ON" "OFF"))

(def %sxy-byte (fn (_ t i) (char->int (str-byte-ref t i))))

(def %sxy-digit? (fn (_ c) (if (>= c 48) (<= c 57) #f)))

; Whether t reads as a number: a sign, then a digit or a point and a digit,
; then digits, points, exponents and underscores; or .inf and .nan.
(def %sxy-number?
  (fn (_ t)
    (let ((n (str-byte-len t)))
      (if (List includes? t (list ".inf" "-.inf" "+.inf" ".nan" ".Inf" ".NaN"))
        #t
        (let ((s (if (List includes? (%sxy-byte t 0) (list 43 45)) 1 0)))
          (if (>= s n) #f
            (if (if (%sxy-digit? (%sxy-byte t s)) #t
                  (if (= (%sxy-byte t s) 46) (if (< (int+ s 1) n) (%sxy-digit? (%sxy-byte t (int+ s 1))) #f) #f))
              ((fn (self i)
                 (if (>= i n) #t
                   (let ((c (%sxy-byte t i)))
                     (if (if (%sxy-digit? c) #t (List includes? c (list 46 95 101 69 43 45 120 111 97 98 99 100 102 65 66 67 68 70)))
                       (self (int+ i 1)) #f))))
               s)
              #f)))))))

; A block scalar's indicator: | or >, then a chomping sign and an indent
; digit in either order.
(def %sxy-block?
  (fn (_ t)
    (if (List includes? (%sxy-byte t 0) (list 124 62))
      ((fn (self i)
         (if (>= i (str-byte-len t)) #t
           (if (List includes? (%sxy-byte t i) (list 43 45 49 50 51 52 53 54 55 56 57)) (self (int+ i 1)) #f)))
       1)
      #f)))

; A word's class, apart from a key's colon.
(def %sxy-scalar
  (fn (_ t)
    (let ((c (%sxy-byte t 0)))
      (match ((List includes? t (list "-" "?" ":" "---" "...")) (lit punct))
             ((%sxy-block? t) (lit punct))
             ((List includes? t %sxy-constants) (lit constant))
             ((if (= c 38) #t (= c 42)) (lit private))
             ((= c 33) (lit class))
             ((= c 37) (lit keyword))
             ((%sxy-number? t) (lit number))
             (#t ())))))

; A word's class, or a key's pieces: its text a name and its colon
; punctuation.
(def %sxy-word
  (fn (_ t)
    (let ((n (str-byte-len t)))
      (if (if (< 1 n) (= (%sxy-byte t (int- n 1)) 58) #f)
        (list (list 0 (int- n 1) (lit name)) (list (int- n 1) 1 (lit punct)))
        (%sxy-scalar t)))))

(Syntax register!
  (let ((g (Syntax make (lit yaml) (%sxy-rules)
             (list (pair (lit comment) (lit comment)) (pair (lit string) (lit string))
                   (pair (lit punct) (lit punct)) (pair (lit word) %sxy-word)))))
    (g files (list ".yaml" ".yml"))
    g))

(doc (provide x/tool/syntax/yaml)
  (note "Imported by x/tool/syntax the first time a .yaml or .yml file needs the grammar; (Syntax named 'yaml) loads it.")
  (example "((Syntax named 'yaml) spans \"a: 1 # c\\n- &x \\\"s\\\"\\n\")" "((0 1 'name) (1 1 'punct) (3 1 'number) (5 3 'comment) (9 1 'punct) (11 2 'private) (14 3 'string))")
  "The YAML highlighting grammar: keys, scalars, anchors, aliases, tags, block indicators and comments.")
