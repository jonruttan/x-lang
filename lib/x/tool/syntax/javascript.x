; javascript.x -- the JavaScript highlighting grammar
;
; x/tool/syntax's catalogue names this module for .js, .mjs and .cjs files
; and a #! line running node, and imports it the first time a file needs
; the grammar.
;
; A comment is a comment, the #! line too.  A string is a string, and a
; template literal is one string to its closing `, its ${...} holding
; strings, templates and braces of their own.  A keyword is a keyword,
; true, false, null, undefined, NaN and Infinity constants, a name
; starting with a capital a class, and a #name a private.  A number is a
; number with its n or its _s.  A bracket, a comma or a semicolon is
; punctuation, every other operator an operator.
;
; A / divides after an operand and starts a regular expression anywhere
; else.  The Lexer carries no context, so an operand -- a name, a number,
; a ) or a ] -- with the / after it and the byte after that is one token,
; its pieces the operand's, the operator's and that byte's; a / with a /,
; a * or a quote after it is left for a comment or the next token.  A /
; that no operand comes before opens a regular expression, a string, its
; body taking \ escapes and a [...] class, which may hold a /; one left
; unclosed is no regular expression, and its / an operator.  So return
; /x/ and x/"y" read the other way.  A comment, a string or a template
; still open at the end of the text runs to it; they span lines, so a text
; is read from its start.

(module x/tool/syntax/javascript)
(import x/type/list)
(import x/type/str)
(import x/reader/lexer)
(import x/tool/syntax)
(import x/core/doors char->int int+ int- str-byte-len str-byte-ref)

(def %sxs-keywords
  (list "async" "await" "break" "case" "catch" "class" "const" "continue"
        "debugger" "default" "delete" "do" "else" "export" "extends" "finally"
        "for" "from" "function" "get" "if" "import" "in" "instanceof" "let"
        "new" "of" "return" "set" "static" "super" "switch" "this" "throw"
        "try" "typeof" "var" "void" "while" "with" "yield"))

(def %sxs-constants (list "true" "false" "null" "undefined" "NaN" "Infinity"))

(def %sxs-ops
  (list "{" "}" "(" ")" "[" "]" ";" ","
        "+" "-" "*" "/" "%" "**" "=" "<" ">" "!" "~" "&" "|" "^" "?" ":" "." "@"
        "++" "--" "<<" ">>" ">>>" "<=" ">=" "==" "!=" "===" "!==" "&&" "||" "??"
        "?." "=>" "..." "+=" "-=" "*=" "/=" "%=" "**=" "<<=" ">>=" ">>>=" "&="
        "|=" "^=" "&&=" "||=" "??="))

; a space, a tab, a carriage return, a newline and a form feed
(def %sxs-blanks (list 32 9 13 10 12))
(def %sxs-start (list (pair 65 90) (pair 97 122) 95 36 (pair 128 255) (pair -128 -1)))
(def %sxs-rest (list (pair 48 57) (pair 65 90) (pair 97 122) 95 36 (pair 128 255) (pair -128 -1)))
(def %sxs-suffix (list (pair 48 57) (pair 65 90) (pair 97 122) 95))
; an operand's bytes: a name's, a number's, a point and a closing bracket
(def %sxs-operand (list (pair 48 57) (pair 65 90) (pair 97 122) 95 36 46 41 93 (pair 128 255) (pair -128 -1)))
; the byte after a division's /: any but a /, a *, a quote and a newline
(def %sxs-after (list (pair 0 9) (pair 11 33) (pair 35 38) (pair 40 41) (pair 43 46) (pair 48 95) (pair 97 255) (pair -128 -1)))

(def %sxs-contexts
  (list (list (lit tmpl) 96 92 (list (pair "${" (lit expr))))
        (list (lit expr) 125 () (list (pair "{" (lit expr)) (pair "`" (lit tmpl))
                                     (pair "\"" (lit dq)) (pair "'" (lit sq))))
        (list (lit dq) 34 92 ())
        (list (lit sq) 39 92 ())
        (list (lit re) 47 92 (list (pair "[" (lit cls))))
        (list (lit cls) 93 92 ())))

(def %sxs-rules
  (fn (_)
    (list (Lexer run (lit blank) %sxs-blanks %sxs-blanks)
          (Lexer until (lit comment) "#!" "\n" (lit to-end))
          (Lexer until (lit comment) "//" "\n" (lit to-end))
          (Lexer until (lit comment) "/*" "*/" (lit to-end))
          (Lexer nested (lit string) "\"" (lit dq) %sxs-contexts (lit to-end))
          (Lexer nested (lit string) "'" (lit sq) %sxs-contexts (lit to-end))
          (Lexer nested (lit string) "`" (lit tmpl) %sxs-contexts (lit to-end))
          (Lexer nested (lit regex) "/" (lit re) %sxs-contexts)
          (Lexer pattern (lit divide)
            (list (list %sxs-operand 1 ()) (list " \t" 0 ()) (list "/" 1 1) (list %sxs-after 1 1)))
          (Lexer pattern (lit private) (list (list "#" 1 1) (list %sxs-start 1 1) (list %sxs-rest 0 ())))
          (Lexer run (lit name) %sxs-start %sxs-rest)
          (Lexer number (lit number) %sxs-suffix)
          (Lexer table (lit op) %sxs-ops)
          (Lexer any (lit other)))))

(def %sxs-byte (fn (_ t i) (char->int (str-byte-ref t i))))
(def %sxs-digit? (fn (_ c) (if (>= c 48) (<= c 57) #f)))

(def %sxs-name
  (fn (_ t)
    (let ((c (%sxs-byte t 0)))
      (match ((List includes? t %sxs-keywords) (lit keyword))
             ((List includes? t %sxs-constants) (lit constant))
             ((if (>= c 65) (<= c 90) #f) (lit class))
             (#t ())))))

(def %sxs-op
  (fn (_ t)
    (if (List includes? t (list "{" "}" "(" ")" "[" "]" ";" ",")) (lit punct) (lit operator))))

; The end of the bytes from i in t that are a name's or a number's; a
; name's ends at a point, so this in this.n / 2 is a keyword.
(def %sxs-word-end
  (fn (self t i n)
    (let ((stops (if (%sxs-digit? (%sxs-byte t 0)) (list 41 93 32 9 47) (list 41 93 32 9 47 46))))
      (if (if (< i n) (List includes? (%sxs-byte t i) stops) #t) i (self t (int+ i 1) n)))))

; The offset of the / from i in t.
(def %sxs-slash (fn (self t i) (if (= (%sxs-byte t i) 47) i (self t (int+ i 1)))))

; A word's pieces, a name's class or a number, from 0 to w.
(def %sxs-word
  (fn (_ t w)
    (if (= w 0) ()
      (let ((c (%sxs-byte t 0)))
        (let ((k (if (if (%sxs-digit? c) #t (= c 46)) (lit number) (%sxs-name (Str8 sub 0 w t)))))
          (if (null? k) () (list (list 0 w k))))))))

; An operand, its /, and the byte after: the word's class, the closing
; brackets, the operator, and the byte a digit's number or a bracket's punct.
(def %sxs-divide
  (fn (_ t)
    (let ((n (str-byte-len t)))
      (let ((w (%sxs-word-end t 0 n)) (s (%sxs-slash t 0)))
        (let ((last (%sxs-byte t (int- n 1))))
          (List append
            (%sxs-word t w)
            (List map (fn (_ i) (list i 1 (lit punct)))
              (List filter (fn (_ i) (List includes? (%sxs-byte t i) (list 41 93)))
                (List range w s)))
            (list (list s 1 (lit operator)))
            (match ((%sxs-digit? last) (list (list (int- n 1) 1 (lit number))))
                   ((List includes? last (list 40 41 91 93 123 125 59 44)) (list (list (int- n 1) 1 (lit punct))))
                   (#t ()))))))))

(Syntax register!
  (let ((g (Syntax make (lit javascript) (%sxs-rules)
             (list (pair (lit comment) (lit comment)) (pair (lit string) (lit string))
                   (pair (lit regex) (lit string)) (pair (lit divide) %sxs-divide)
                   (pair (lit private) (lit private)) (pair (lit number) (lit number))
                   (pair (lit name) %sxs-name) (pair (lit op) %sxs-op)))))
    (g files (list ".js" ".mjs" ".cjs"))
    (g interpreters (list "node"))
    g))

(doc (provide x/tool/syntax/javascript)
  (note "Imported by x/tool/syntax the first time a .js, .mjs or .cjs file, or a #! line running node, needs the grammar; (Syntax named 'javascript) loads it.")
  (example "((Syntax named 'javascript) spans \"const r = /a\\\\/b/g, x = n / 2;\")" "((0 5 'keyword) (8 1 'operator) (10 6 'string) (17 1 'punct) (21 1 'operator) (25 1 'operator) (27 1 'number) (28 1 'punct))")
  "The JavaScript highlighting grammar: keywords, constants, classes, privates, numbers, strings, templates, regular expressions and comments.")
