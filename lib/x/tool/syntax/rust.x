; rust.x -- the Rust highlighting grammar
;
; x/tool/syntax's catalogue names this module for .rs files and imports it
; the first time a file needs the grammar.
;
; A comment is a comment, a doc comment (/// or //!) too; a block comment
; ends at its first */, so a nested one ends early.  A string, a byte
; string and a raw string with up to three #s is a string; a character or a
; byte constant is a character, and a lifetime or a loop label ('a) a
; class.  An attribute, #[...] or #![...], is a keyword.  A number is a
; number with its suffix and its _s.  A keyword is a keyword, true and
; false constants, a primitive type, Self and a name starting with a
; capital a class, and a name before ! a macro, a name.  A bracket, a comma
; or a semicolon is punctuation, every other operator an operator.  A name
; before != reads as a macro.  A comment, a string or an attribute still
; open at the end of the text runs to it; a comment and a string span
; lines, so a text is read from its start.

(module x/tool/syntax/rust)
(import x/type/list)
(import x/type/str)
(import x/reader/lexer)
(import x/tool/syntax)
(import x/core/doors char->int str-byte-len str-byte-ref)

(def %sxr-keywords
  (list "as" "async" "await" "break" "const" "continue" "crate" "dyn" "else"
        "enum" "extern" "fn" "for" "if" "impl" "in" "let" "loop" "match" "mod"
        "move" "mut" "pub" "ref" "return" "self" "static" "struct" "super"
        "trait" "type" "union" "unsafe" "use" "where" "while" "yield"
        "abstract" "become" "box" "do" "final" "macro" "override" "priv"
        "try" "typeof" "unsized" "virtual"))

(def %sxr-types
  (list "i8" "i16" "i32" "i64" "i128" "isize" "u8" "u16" "u32" "u64" "u128"
        "usize" "f32" "f64" "bool" "char" "str" "Self"))

(def %sxr-ops
  (list "{" "}" "(" ")" "[" "]" ";" ","
        "+" "-" "*" "/" "%" "^" "!" "&" "|" "=" "<" ">" "@" "." ":" "?" "~" "$" "#"
        "&&" "||" "<<" ">>" "+=" "-=" "*=" "/=" "%=" "^=" "&=" "|=" "<<=" ">>="
        "==" "!=" "<=" ">=" ".." "..." "..=" "::" "->" "=>"))

; a space, a tab, a carriage return, a newline and a form feed
(def %sxr-blanks (list 32 9 13 10 12))
(def %sxr-start (list (pair 65 90) (pair 97 122) 95 (pair 128 255) (pair -128 -1)))
(def %sxr-rest (list (pair 48 57) (pair 65 90) (pair 97 122) 95 (pair 128 255) (pair -128 -1)))
(def %sxr-suffix (list (pair 48 57) (pair 65 90) (pair 97 122) 95))
; a character constant's one byte: any but a quote, a backslash and a newline
(def %sxr-ascii (list (pair 0 9) (pair 11 38) (pair 40 91) (pair 93 127)))
(def %sxr-high (list (pair 128 255) (pair -128 -1)))
; an escape's bytes after the backslash: any but a quote and a newline
(def %sxr-escaped (list (pair 0 9) (pair 11 38) (pair 40 255) (pair -128 -1)))

(def %sxr-string
  (fn (_ open)
    (Lexer nested (lit string) open (lit body) (list (list (lit body) 34 92 ())) (lit to-end))))

(def %sxr-raw
  (fn (_ prefix hashes)
    (Lexer until (lit string) (Str8 append prefix (Str8 append hashes "\""))
      (Str8 append "\"" hashes) (lit take) (lit to-end))))

(def %sxr-char
  (fn (_ open)
    (list (Lexer pattern (lit char) (list (list open 1 1) (list %sxr-ascii 1 1) (list "'" 1 1)))
          (Lexer pattern (lit char) (list (list open 1 1) (list %sxr-high 2 4) (list "'" 1 1)))
          (Lexer pattern (lit char) (list (list open 1 1) (list "\\" 1 1) (list %sxr-escaped 1 10) (list "'" 1 1)))
          (Lexer table (lit char) (list (Str8 append open "\\''"))))))

(def %sxr-rules
  (fn (_)
    (List append
      (list (Lexer run (lit blank) %sxr-blanks %sxr-blanks)
            (Lexer until (lit comment) "//" "\n" (lit to-end))
            (Lexer until (lit comment) "/*" "*/" (lit to-end))
            (Lexer nested (lit attribute) "#[" (lit attr)
              (list (list (lit attr) 93 () (list (pair "[" (lit attr)) (pair "\"" (lit dq))))
                    (list (lit dq) 34 92 ()))
              (lit to-end))
            (Lexer nested (lit attribute) "#![" (lit attr)
              (list (list (lit attr) 93 () (list (pair "[" (lit attr)) (pair "\"" (lit dq))))
                    (list (lit dq) 34 92 ()))
              (lit to-end))
            (%sxr-string "\"")
            (%sxr-string "b\"")
            (%sxr-string "c\""))
      (List flat-map (fn (_ p) (List map (fn (_ h) (%sxr-raw p h)) (list "" "#" "##" "###")))
        (list "r" "br" "cr"))
      (%sxr-char "'")
      (%sxr-char "b'")
      (list (Lexer pattern (lit lifetime) (list (list "'" 1 1) (list %sxr-start 1 1) (list %sxr-rest 0 ())))
            (Lexer run (lit macro) %sxr-start %sxr-rest "!")
            (Lexer run (lit name) %sxr-start %sxr-rest)
            (Lexer number (lit number) %sxr-suffix)
            (Lexer table (lit op) %sxr-ops)
            (Lexer any (lit other))))))

(def %sxr-name
  (fn (_ t)
    (let ((c (char->int (str-byte-ref t 0))))
      (match ((List includes? t %sxr-keywords) (lit keyword))
             ((List includes? t (list "true" "false")) (lit constant))
             ((List includes? t %sxr-types) (lit class))
             ((if (>= c 65) (<= c 90) #f) (lit class))
             (#t ())))))

(def %sxr-op
  (fn (_ t)
    (if (List includes? t (list "{" "}" "(" ")" "[" "]" ";" ",")) (lit punct) (lit operator))))

(Syntax register!
  (let ((g (Syntax make (lit rust) (%sxr-rules)
             (list (pair (lit comment) (lit comment)) (pair (lit string) (lit string))
                   (pair (lit char) (lit char)) (pair (lit lifetime) (lit class))
                   (pair (lit attribute) (lit keyword)) (pair (lit macro) (lit name))
                   (pair (lit number) (lit number)) (pair (lit name) %sxr-name)
                   (pair (lit op) %sxr-op)))))
    (g files (list ".rs"))
    g))

(doc (provide x/tool/syntax/rust)
  (note "Imported by x/tool/syntax the first time a .rs file needs the grammar; (Syntax named 'rust) loads it.")
  (example "((Syntax named 'rust) spans \"fn f<'a>(s: &'a str) -> u8 { 1 }\")" "((0 2 'keyword) (4 1 'operator) (5 2 'class) (7 1 'operator) (8 1 'punct) (10 1 'operator) (12 1 'operator) (13 2 'class) (16 3 'class) (19 1 'punct) (21 2 'operator) (24 2 'class) (27 1 'punct) (29 1 'number) (31 1 'punct))")
  "The Rust highlighting grammar: keywords, types, lifetimes, macros, attributes, numbers, characters, strings and comments.")
