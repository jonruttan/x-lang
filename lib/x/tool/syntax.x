; syntax.x -- Syntax: lexical highlighting, a grammar a language
;
; A grammar is a Lexer whose rules read every byte, and a table from each
; token's tag to its class: what the token is (comment, string, keyword ...)
; in one vocabulary every renderer shares.  A grammar answers spans, each
; (offset length class) in source order, and a renderer turns them into what
; its output needs: ANSI codes for a terminal, Rouge's span markup for HTML,
; or a class byte a text byte for a screen editor that lays out its own rows.
;
; A grammar reads from a line its lexer can start at, one outside any string
; or comment.  Its sync test names such lines, and spans walks back to one
; from the first byte asked for, a bounded number of lines; a grammar with no
; sync test reads from the start of the text.  So a string opened above a
; window colours the window's start.
;
; x-lang's own grammar is (Syntax x).  An atom's class is the reader's
; answer: the bytes are read on the base and the value's type decides, so a
; colour cannot disagree with the evaluator, and a literal a lang adds
; classifies without this file knowing its syntax.  The constructs are
; lib/x/constructs.x, the list the formatter, the linter and the
; documentation read.
;
; How a terminal draws each class is a theme: a Style (x/tui/style) a class,
; data apart from any grammar.  The theme in use is the default unless the
; user's theme file names another; the file is read on first use, so a
; process that never colours does not open it.

(module x/tool/syntax)
(import x/type/class)
(import x/type/str)
(import x/type/dict)
(import x/type/list)
(import x/reader/lexer)
(import x/repl/ansi)
(import x/sys/posix)
(import x/sys/file)
(import x/sys/stream)
(import x/tui/style)

; The walks run per token and per byte, so they ride cached prims: a class
; door costs a dispatch and allocates.
(def %sx-bref   (prim-ref (lit str)  (lit byte-ref)))
(def %sx-blen   (prim-ref (lit str)  (lit byte-len)))
(def %sx-bsub   (prim-ref (lit str)  (lit byte-sub)))
(def %sx-append (prim-ref (lit str)  (lit append)))
(def %sx-cint   (prim-ref (lit char) (lit ->int)))
(def %sx+       (prim-ref (lit int)  (lit +)))
(def %sx-       (prim-ref (lit int)  (lit -)))
(def %sx-read   (prim-ref (lit tok)  (lit read-str)))
(def %sx-bytes  (prim-ref (lit str)  (lit from-list)))
(def %sx-byte (fn (_ s i) (%sx-cint (%sx-bref s i))))

; --- the classes --------------------------------------------------------------

; Each class and its Rouge token class.  A class's index is its place here
; from 1, the byte a cell row holds being 64 plus it; a byte of no class is a
; space.
(def %sx-table
  (list (list (lit comment)  "c1")
        (list (lit string)   "s")
        (list (lit char)     "sc")
        (list (lit number)   "m")
        (list (lit keyword)  "k")
        (list (lit constant) "kc")
        (list (lit class)    "nc")
        (list (lit private)  "nv")
        (list (lit name)     "n")
        (list (lit punct)    "p")
        (list (lit operator) "o")
        (list (lit escape)   "se")
        (list (lit error)    "err")))

; The default theme, each row (CLASS ATTRIBUTES FOREGROUND BACKGROUND) as
; Style make takes them; punct and operator are drawn plain.
(def %sx-default-rows
  (list (list (lit comment)  (lit (dim))  () ())
        (list (lit string)   ()           2  ())
        (list (lit char)     ()           5  ())
        (list (lit number)   ()           3  ())
        (list (lit keyword)  (lit (bold)) 5  ())
        (list (lit constant) (lit (bold)) 1  ())
        (list (lit class)    (lit (bold)) 6  ())
        (list (lit private)  (lit (dim))  () ())
        (list (lit name)     ()           4  ())
        (list (lit escape)   ()           5  ())
        (list (lit error)    (lit (bold)) 1  ())))

(def %sx-row
  (fn (self cls rows)
    (match
      ((null? rows) ())
      ((eq? cls (first (first rows))) (first rows))
      (#t (self cls (rest rows))))))

(def %sx-index
  (fn (self cls rows i)
    (match
      ((null? rows) 0)
      ((eq? cls (first (first rows))) i)
      (#t (self cls (rest rows) (%sx+ i 1))))))

(def %sx-reset "\x1b[0m")

; --- themes -------------------------------------------------------------------

; A class's sequence sets its style over the plain one: every renderer resets
; after a span, so the reset Style's sequence starts with is left off, and a
; plain style has no sequence.
(def %sx-code
  (fn (_ style)
    (if (= style 0) ""
      (let ((s (Style sgr style)))
        (%sx-append "\x1b[" (%sx-bsub s 4 (%sx- (%sx-blen s) 4)))))))

; Each (CLASS . STYLE) of rows (CLASS ATTRIBUTES FOREGROUND BACKGROUND).
(def %sx-styles
  (fn (_ rows)
    (List map
      (fn (_ row)
        (if (= (%sx-index (first row) %sx-table 1) 0)
          (Err raise (lit value) "Theme: no such class" (first row))
          (pair (first row)
                (Style make (first (rest row)) (first (rest (rest row)))
                            (first (rest (rest (rest row))))))))
      rows)))

; Styles over base's: a class in over replaces base's.
(def %sx-over
  (fn (_ base over)
    (List append over (List filter (fn (_ p) (null? (%sx-row (first p) over))) base))))

; The SGR sequence of a class in the codes a theme holds, empty for a class
; drawn plain.
(def %sx-sgr
  (fn (_ codes cls)
    (let ((row (%sx-row cls codes))) (if (null? row) "" (rest row)))))

(def %sx-theme (pair () ()))
(def %sx-default (pair () ()))
; Themes register! added, kept in an image; and the user's file's, read on
; first use and dropped by forget!, as (THEMES) once read.
(def %sx-themes (pair () ()))
(def %sx-user (pair () ()))

; $X_THEME, else $XDG_CONFIG_HOME/x/theme.x, else ~/.config/x/theme.x; nil
; for an empty X_THEME or no home.
(def %sx-theme-file
  (fn (_)
    (let ((o (Sys getenv "X_THEME")))
      (if (not (null? o)) (if (= (%sx-blen o) 0) () o)
        (let ((c (Sys getenv "XDG_CONFIG_HOME")) (h (Sys getenv "HOME")))
          (if (not (null? c)) (%sx-append c "/x/theme.x")
            (if (null? h) () (%sx-append h "/.config/x/theme.x"))))))))

; The user's file, read once.  No file is no themes; one that does not read
; is one line on stderr and the default, as an unreadable construct list is.
(def %sx-read-user!
  (fn (_)
    (if (null? (first %sx-user))
      (let ((path (%sx-theme-file)))
        (%set-first! %sx-user (list ()))
        (if (if (null? path) #f (File exists? path))
          (guard (e (Stream with-fd 2
                      (fn (_)
                        (display "x/tool/syntax: theme file " path " unreadable (" e
                                 ") -- the default theme is used\n"))))
            (Theme load! path))
          ()))
      ())))

; The themes and the theme to use a theme file's forms name, (THEMES . USE),
; nothing registered yet: each (theme NAME ROW ...) is ROWS over the theme of
; that name the file or the registry already has, else over the default, and
; (use NAME) the theme to use.
(def %sx-theme-forms
  (fn (self forms themes use)
    (if (null? forms) (pair themes use)
      (let ((f (first forms)))
        (match
          ((if (pair? f) (eq? (first f) (lit theme)) #f)
            (let ((name (first (rest f))))
              (def base (let ((t (List find (fn (_ t) (eq? (t name) name)) themes)))
                          (if (null? t) (Theme named name) t)))
              (self (rest forms)
                    (pair ((if (null? base) (Theme default) base) with (rest (rest f)) name)
                          themes)
                    use)))
          ((if (pair? f) (eq? (first f) (lit use)) #f)
            (self (rest forms) themes (first (rest f))))
          (#t (Err raise (lit value) "Theme: a theme file holds (theme NAME ROW ...) and (use NAME)" f)))))))

; --- reading ------------------------------------------------------------------

; The start of the line holding byte i.
(def %sx-line-start
  (fn (self s i)
    (match
      ((<= i 0) 0)
      ((= (%sx-byte s (%sx- i 1)) 10) i)
      (#t (self s (%sx- i 1))))))

; One past the end of the line holding byte i, its newline included, and
; never past lim.
(def %sx-line-end
  (fn (self s i lim)
    (match
      ((>= i lim) lim)
      ((= (%sx-byte s i) 10) (%sx+ i 1))
      (#t (self s (%sx+ i 1) lim)))))

; Where to read from to colour byte at: a line start the sync test passes,
; at most `lines` lines back, or the line that many back; the text's start
; when the grammar has no test.
(def %sx-sync-from
  (fn (_ g s at)
    (def ok? (g sync))
    (if (null? ok?) 0
      ((fn (self ls k)
         (match
           ((= ls 0) 0)
           ((ok? s ls) ls)
           ((>= k (g lines)) ls)
           (#t (self (%sx-line-start s (%sx- ls 1)) (%sx+ k 1)))))
       (%sx-line-start s at) 0))))

; A token's class from the grammar's table: the entry's class, or a function
; of the token's text answering one; nil for a tag with no entry.
(def %sx-class-of
  (fn (_ table tag text)
    (def hit
      ((fn (self es) (if (null? es) () (if (eq? (first (first es)) tag) (first es) (self (rest es)))))
       table))
    (if (null? hit) ()
      (let ((c (rest hit))) (if (if (null? c) #t (symbol? c)) c (if (str? c) c (c text)))))))

; The tokens' spans inside [lo, hi), each (offset length class), offsets
; counted in the text the tokens were read from from base.  A token with no
; class is left out; bytes after the lexer stops are plain.
(def %sx-walk
  (fn (self table toks at lo hi acc)
    (if (if (null? toks) #t (>= at hi)) (%reverse acc)
      (let ((tag (first (first toks))) (text (first (rest (first toks)))))
        (let ((e (%sx+ at (%sx-blen text))))
          (if (<= e lo) (self table (rest toks) e lo hi acc)
            (let ((cls (%sx-class-of table tag text)))
              (if (null? cls) (self table (rest toks) e lo hi acc)
                (let ((s0 (if (< at lo) lo at)) (e0 (if (> e hi) hi e)))
                  (self table (rest toks) e lo hi
                    (pair (list s0 (%sx- e0 s0) cls) acc)))))))))))

(def %sx-spans
  (fn (_ g s start len lim)
    (def from (%sx-sync-from g s start))
    (def hi (%sx+ start len))
    (def to (if (>= hi lim) lim (%sx-line-end s hi lim)))
    (def whole? (if (= from 0) (= to (%sx-blen s)) #f))
    (def toks ((g %lexer) read-str (if whole? s (%sx-bsub s from (%sx- to from)))))
    (%sx-walk (g classes) toks from start hi ())))

; --- rendering ----------------------------------------------------------------

; Each renderer walks the spans over [start, start + len), the pieces it
; makes in order: (plain at n) for the bytes between spans, (styled span at n)
; for a span's, cut at the edges of the range.
(def %sx-render
  (fn (self spans pos hi plain styled acc)
    (def sp (if (null? spans) () (first spans)))
    (def o (if (null? sp) hi (first sp)))
    (def e (if (null? sp) hi (%sx+ o (first (rest sp)))))
    (match
      ((if (null? sp) #t (>= o hi))
        (%reverse (if (< pos hi) (pair (plain pos (%sx- hi pos)) acc) acc)))
      ((<= e pos) (self (rest spans) pos hi plain styled acc))
      (#t
        (let ((o0 (if (< o pos) pos o)) (e0 (if (> e hi) hi e)))
          (self (rest spans) e0 hi plain styled
            (pair (styled sp o0 (%sx- e0 o0))
                  (if (< pos o0) (pair (plain pos (%sx- o0 pos)) acc) acc))))))))

(def %sx-html-escape
  (fn (_ s)
    (Str8 replace ">" "&gt;" (Str8 replace "<" "&lt;" (Str8 replace "&" "&amp;" s)))))

; A run of n copies of byte b, from a run string grown as long as asked.
(def %sx-runs (pair () ()))
(def %sx-run
  (fn (_ b n)
    (def hit ((fn (self rs) (if (null? rs) () (if (= (first (first rs)) b) (first rs) (self (rest rs)))))
              (first %sx-runs)))
    (def have (if (null? hit) "" (rest hit)))
    (if (<= n (%sx-blen have)) (%sx-bsub have 0 n)
      (let ((grown ((fn (self r) (if (< (%sx-blen r) n) (self (%sx-append r r)) r))
                    (if (= (%sx-blen have) 0) (%sx-bytes (list b)) have))))
        (%set-first! %sx-runs (pair (pair b grown) (first %sx-runs)))
        (%sx-bsub grown 0 n)))))

; --- x-lang's grammar -----------------------------------------------------------

; The constructs, as a Dict used as a set.  An unreadable file yields an empty
; set and one line on stderr: losing a colour is not worth refusing to start
; a session over, and an empty set otherwise looks like a line with no
; construct on it.
(def %sx-load-keywords
  (fn (_)
    (guard (e (do (Stream with-fd 2
                    (fn (_)
                      (display "x/tool/syntax: construct vocabulary unreadable ("
                               e ") -- constructs will not colour\n")))
                  (Dict make)))
      (let ((path (%module-resolve-file "x/constructs.x")) (d (Dict make)))
        (List for-each
          (fn (_ entry) (d set! (Str8 str (first entry)) #t))
          (first (%sx-read (%base) (File read-all path))))
        d))))

; The construct set and the memo of atom classes, made on first use and
; dropped by forget!: a lang that registers literal syntax changes what the
; reader answers.
(def %sx-kw (pair () ()))
(def %sx-memo (pair () ()))

(def %sx-keywords
  (fn (_)
    (if (null? (first %sx-kw)) (%set-first! %sx-kw (%sx-load-keywords)) ())
    (first %sx-kw)))

; A name's class by the conventions the library follows: a leading % marks
; a private, a leading capital a class.
(def %sx-name-class
  (fn (_ text)
    (def b0 (if (= 0 (%sx-blen text)) 0 (%sx-byte text 0)))
    (match
      ((= b0 37) (lit private))
      ((if (>= b0 65) (<= b0 90) #f) (lit class))
      (#t (lit name)))))

; Ask the reader what an atom is.  The trailing space ends the token, which
; a read otherwise drops as unfinished; an atom the reader refuses -- half a
; literal, as a line being typed often holds -- is a name.
(def %sx-ask
  (fn (_ text)
    (if ((%sx-keywords) get-or #f text) (lit keyword)
      (let ((v (guard (_ (lit %unreadable)) (first (%sx-read (%base) (%sx-append text " "))))))
        (match
          ((eq? v (lit %unreadable)) (lit name))
          ((number? v) (lit number))
          ((str? v)    (lit string))
          ((char? v)   (lit char))
          ((eq? v #t)  (lit constant))
          ((eq? v #f)  (lit constant))
          ((null? v)   (lit constant))
          (#t (%sx-name-class text)))))))

(def %sx-atom-class
  (fn (_ text)
    (if (null? (first %sx-memo)) (%set-first! %sx-memo (Dict make)) ())
    (let ((hit ((first %sx-memo) get-or () text)))
      (if (null? hit)
        (let ((cls (%sx-ask text))) ((first %sx-memo) set! text cls) cls)
        hit))))

; An atom runs to a blank, a paren or a semicolon, and does not start with a
; quote; a byte above 127 is part of one, whichever sign the engine reads it
; with.
(def %sx-atom-first (list (pair 33 33) (pair 35 39) (pair 42 58) (pair 60 255) (pair -128 -1)))
(def %sx-atom-rest  (list (pair 33 39) (pair 42 58) (pair 60 255) (pair -128 -1)))
(def %sx-dq (list (list (lit dq) 34 92 ())))

(def %sx-x-rules
  (fn (_)
    (list (Lexer until (lit comment) ";" "\n" (lit to-end))
          (Lexer nested (lit string) "\"" (lit dq) %sx-dq (lit to-end))
          (Lexer nested (lit string) "#\"" (lit dq) %sx-dq (lit to-end))
          (Lexer pattern (lit char) (list (list "#" 1 1) (list "\\" 1 1) (list #t 1 1)
                                          (list %sx-atom-rest 0 ())))
          (Lexer run (lit blank) (list (pair 0 32)) (list (pair 0 32)))
          (Lexer table (lit paren) (list "(" ")"))
          (Lexer run (lit atom) %sx-atom-first %sx-atom-rest)
          (Lexer any (lit bad)))))

; A line that opens a top-level form starts outside any string or comment.
(def %sx-x-sync (fn (_ s ls) (= (%sx-byte s ls) 40)))

(def %sx-x (pair () ()))
(def %sx-registry (pair () ()))

; --- the Theme class ------------------------------------------------------------

(def-class Theme ()
  (doc "How a terminal draws each class: a Style (x/tui/style) a class, a class the theme leaves out drawn plain. The theme in use, (Theme current), is what Syntax ansi, sgr and code draw with."
    (note "The user's theme file is $X_THEME, else $XDG_CONFIG_HOME/x/theme.x, else ~/.config/x/theme.x, and an empty X_THEME reads none. It is data, read and never evaluated: each (theme NAME ROW ...) is a theme, its rows over the theme of that name already known, else over the default, and (use NAME) the theme to use. A row is (CLASS ATTRIBUTES FOREGROUND BACKGROUND) as Style make takes them, so (theme default (comment (italic) 8 ())) changes only comments.")
    (note "The file is read on the first use of a theme, and again after forget!; one that does not read is one line on stderr and the default theme.")
    (example "((Theme default) style 'keyword)" "1537")
    (example "((Theme default) sgr 'number)" "\"\\x1b[33m\""))
  (doc (name ()) "The theme's name, a symbol")
  (doc (styles ()) "Each (CLASS . STYLE): STYLE a Style integer")
  (doc (codes ()) "Each (CLASS . SEQUENCE): the SGR sequence that draws the class, as sgr answers it")

  (method style (self (param cls SYMBOL "A class"))
    (doc "The Style the theme draws a class with, 0 (plain) for one it leaves out."
      (returns INTEGER "A Style")
      (example "((Theme default) style 'punct)" "0"))
    (let ((row (%sx-row cls (self styles)))) (if (null? row) 0 (rest row))))

  (method sgr (self (param cls SYMBOL "A class"))
    (doc "The SGR sequence that draws a class over the plain style, empty for a class drawn plain. A renderer resets after each span, so the sequence does not reset first."
      (returns STRING "The escape sequence")
      (example "((Theme default) sgr 'keyword)" "\"\\x1b[1;35m\""))
    (%sx-sgr (self codes) cls))

  (method with (self (param rows LIST "Rows (CLASS ATTRIBUTES FOREGROUND BACKGROUND), as make takes them")
                     . (param name LIST "Optionally the new theme's name; the same name if left out"))
    (doc "A theme with the rows over this one's: a class in rows is drawn as they say, every other as before."
      (returns Theme "The theme")
      (example "(((Theme default) with '((number (bold) 3 ()))) sgr 'number)" "\"\\x1b[1;33m\""))
    (let ((styles (%sx-over (self styles) (%sx-styles rows)))
          (called (if (null? name) (self name) (first name))))
      (def codes (List map (fn (_ p) (pair (first p) (%sx-code (rest p)))) styles))
      (new Theme name called styles styles codes codes)))

  (static
    (method make (self (param name SYMBOL "The theme's name")
                       (param rows LIST "Rows (CLASS ATTRIBUTES FOREGROUND BACKGROUND), ATTRIBUTES, FOREGROUND and BACKGROUND as Style make takes them"))
      (doc "A theme drawing each class in rows as it says, and every other plain. Register it to have named and the theme file find it."
        (returns Theme "The theme")
        (example "((Theme make 'mono '((keyword (bold) () ()))) sgr 'string)" "\"\""))
      (let ((styles ()) (codes ())) ((new Theme name name styles styles codes codes) with rows)))

    (method default (self)
      (doc "The default theme: comments and privates dim; strings green, numbers yellow, names blue, characters and escapes magenta; keywords, constants and classes bold in magenta, red and cyan; errors bold red; punctuation and operators plain."
        (returns Theme "The theme"))
      (if (null? (first %sx-default))
        (%set-first! %sx-default (Theme make (lit default) %sx-default-rows))
        ())
      (first %sx-default))

    (method register! (self (param t Theme "A theme"))
      (doc "Add a theme to the ones named finds; one of the same name is replaced. A theme file's themes are found before registered ones."
        (returns Theme "The theme"))
      (%set-first! %sx-themes
        (pair t (List filter (fn (_ h) (not (eq? (h name) (t name)))) (first %sx-themes))))
      t)

    (method named (self (param name SYMBOL "A theme's name"))
      (doc "The theme of that name: the user's theme file's, else a registered one, else the default for default; nil for none."
        (returns Theme "The theme, or nil")
        (example "(eq? (Theme named 'default) (Theme default))" "#t"))
      (%sx-read-user!)
      (let ((t (List find (fn (_ t) (eq? (t name) name))
                 (List append (first (first %sx-user)) (first %sx-themes)))))
        (match ((not (null? t)) t) ((eq? name (lit default)) (Theme default)) (#t ()))))

    (method names (self)
      (doc "The names named answers a theme for, the default's last."
        (returns LIST "Theme names")
        (example "(List last (Theme names))" "'default"))
      (%sx-read-user!)
      (List distinct
        (List append (List map (fn (_ t) (t name)) (List append (first (first %sx-user)) (first %sx-themes)))
                     (list (lit default)))))

    (method current (self)
      (doc "The theme in use: the one use! set, else the one the user's theme file names with (use NAME), else the default."
        (returns Theme "The theme"))
      (%sx-read-user!)
      (if (null? (first %sx-theme)) (%set-first! %sx-theme (Theme default)) ())
      (first %sx-theme))

    (method use! (self (param t Theme "A theme"))
      (doc "Draw with a theme from now on."
        (returns Theme "The theme"))
      (%sx-read-user!)
      (%set-first! %sx-theme t)
      t)

    (method file (self)
      (doc "The user's theme file: $X_THEME, else $XDG_CONFIG_HOME/x/theme.x, else ~/.config/x/theme.x; nil for an empty X_THEME or no home. The file need not exist."
        (returns STRING "The path, or nil"))
      (%sx-theme-file))

    (method load! (self (param path STRING "A theme file"))
      (doc "Read a theme file: its themes join the ones named finds, ahead of any of the same name, and its (use NAME) becomes the theme in use. Nothing changes when the file does not read."
        (returns LIST "The file's themes")
        (sample "(Theme load! \"/home/me/.config/x/theme.x\")" "its themes"))
      (let ((r (%sx-theme-forms (%sx-read (%base) (File read-all path)) () ())))
        (def themes (List reverse (first r)))
        (def use (if (null? (rest r)) ()
                   (let ((t (List find (fn (_ t) (eq? (t name) (rest r))) themes)))
                     (if (null? t) (Theme named (rest r)) t))))
        (if (if (null? use) (not (null? (rest r))) #f)
          (Err raise (lit value) "Theme: use names no theme" (rest r))
          ())
        (def known (if (null? (first %sx-user)) () (first (first %sx-user))))
        (%set-first! %sx-user
          (list (List append themes
                  (List filter (fn (_ h) (null? (List find (fn (_ t) (eq? (t name) (h name))) themes)))
                    known))))
        (if (null? use) () (%set-first! %sx-theme use))
        themes))

    (method forget! (self)
      (doc "Drop the theme in use and the theme file's themes, read again on next use; registered themes stay."
        (returns NIL "Nothing"))
      (%set-first! %sx-theme ())
      (%set-first! %sx-user ())
      ())))

; --- the Syntax class: the API -------------------------------------------------

(def-class Syntax ()
  (doc "A lexical grammar for highlighting: a Lexer whose rules read every byte, and a table from each token's tag to its class. spans answers (offset length class) for a stretch of text; ansi, html and cells render spans for a terminal, a web page and a screen editor. (Syntax x) is x-lang's own grammar."
    (note "The classes are one vocabulary, (Syntax classes), so a renderer knows every grammar's output: comment string char number keyword constant class private name punct operator escape error.")
    (note "A grammar's lexer is made on its first read, not when the grammar is: making a Lexer compiles its states, which a process that never highlights should not pay for.")
    (example "((Syntax x) spans \"(def x 42) ; hi\")" "((0 1 'punct) (1 3 'keyword) (5 1 'name) (7 2 'number) (9 1 'punct) (11 4 'comment))"))
  (doc (name ()) "The grammar's name, a symbol")
  (doc (rules ()) "The Lexer rules, each token's tag looked up in classes")
  (doc (end " ") "The Lexer's end text: see Lexer's end field")
  (doc (classes ()) "Each (TAG . CLASS): CLASS a class symbol, nil to leave the token plain, or a function of the token's text answering one")
  (doc (sync ()) "A test (fn (_ text offset)) of a line start, true where the lexer can start outside any string or comment; nil to read from the text's start")
  (doc (lines 100) "How many lines spans walks back looking for a line the sync test passes")
  (doc (files ()) "The file name endings the grammar is for, as \".x\"")
  (doc (lexer ()) "The Lexer, made from the rules on the first read")

  (method spans (self (param text STRING "The text")
                      . (param range LIST "Optionally the start, the length, and the end of the meaningful text"))
    (doc "The spans of text from start for length bytes, each (offset length class) in order, offsets into text and clipped to the range. The lexer reads from a line the sync test passes, so a string or comment opened before start colours the range's start, and to the end of the line the range ends in, never past the end given. Tokens with no class are left out."
      (returns LIST "((offset length class) ...)")
      (example "((Syntax x) spans \"\\\"a b\\\" c\" 3 4)" "((3 2 'string) (6 1 'name))"))
    (def n (%sx-blen text))
    (def start (if (null? range) 0 (first range)))
    (def len (if (if (null? range) #t (null? (rest range))) (%sx- n start) (first (rest range))))
    (def lim (if (if (null? range) #t (if (null? (rest range)) #t (null? (rest (rest range))))) n
               (first (rest (rest range)))))
    (%sx-spans self text start len lim))

  (method class-of (self (param tag SYMBOL "A token's tag") (param text STRING "The token's text"))
    (doc "The class the grammar gives a token, or nil for one it leaves plain."
      (returns SYMBOL "A class")
      (example "((Syntax x) class-of 'atom \"Str8\")" "'class"))
    (%sx-class-of (self classes) tag text))

  (method %lexer (self)
    (if (null? (self lexer)) (self lexer (Lexer make (self rules) (self end))) ())
    (self lexer))

  (static
    (method make (self (param name SYMBOL "The grammar's name")
                       (param rules LIST "Lexer rules that read every byte: blanks a run, comments tagged")
                       (param classes LIST "Each (TAG . CLASS), as the classes field takes them"))
      (doc "A grammar. Set sync, lines and files on it after, and register! it to have for-file find it."
        (returns Syntax "The grammar")
        (sample "(Syntax make 'ini (list (Lexer until 'comment \";\" \"\\n\" 'to-end) (Lexer run 'blank \" \\t\\n\" \" \\t\\n\") (Lexer any 'text)) (list (pair 'comment 'comment)))" "comments coloured, everything else plain"))
      (let ((lexer ()) (sync ()) (lines 100) (files ()) (end " "))
        (new Syntax name name rules rules end end classes classes sync sync lines lines files files lexer lexer)))

    (method over (self (param l Lexer "A Lexer whose rules read every byte")
                       (param classes LIST "Each (TAG . CLASS), as the classes field takes them"))
      (doc "A grammar over a Lexer already made, reading from the text's start."
        (returns Syntax "The grammar"))
      (let ((g (Syntax make (lit lexer) (l rules) classes))) (g lexer l) g))

    (method x (self)
      (doc "x-lang's grammar: comments, strings, character literals and parens by their syntax, and every other atom by what the reader reads it as -- a keyword when lib/x/constructs.x lists it, a number, string, character or constant by its value, and otherwise a name, a private (a leading %) or a class (a leading capital)."
        (returns Syntax "The grammar")
        (example "((Syntax x) class-of 'atom \"3\")" "'number"))
      (if (null? (first %sx-x))
        (let ((g (Syntax make (lit x) (%sx-x-rules)
                   (list (pair (lit comment) (lit comment)) (pair (lit string) (lit string))
                         (pair (lit char) (lit char)) (pair (lit paren) (lit punct))
                         (pair (lit atom) %sx-atom-class) (pair (lit bad) (lit error))))))
          (g sync %sx-x-sync)
          (g files (list ".x" ".xon"))
          (%set-first! %sx-x g)
          (Syntax register! g))
        (first %sx-x)))

    (method register! (self (param g Syntax "A grammar"))
      (doc "Add a grammar to the ones named and for-file finds; one of the same name is replaced."
        (returns Syntax "The grammar"))
      (%set-first! %sx-registry
        (pair g (List filter (fn (_ h) (not (eq? (h name) (g name)))) (first %sx-registry))))
      g)

    (method named (self (param name SYMBOL "A grammar's name"))
      (doc "The registered grammar of that name, or nil."
        (returns Syntax "The grammar, or nil")
        (example "(eq? (Syntax named 'x) (Syntax x))" "#t"))
      (Syntax x)
      (List find (fn (_ g) (eq? (g name) name)) (first %sx-registry)))

    (method for-file (self (param path STRING "A file name"))
      (doc "The registered grammar whose files the name ends with, or nil."
        (returns Syntax "The grammar, or nil")
        (example "((Syntax for-file \"lib/x/tool/syntax.x\") name)" "'x"))
      (Syntax x)
      (List find
        (fn (_ g) (List any? (fn (_ suffix) (Str8 ends? suffix path)) (g files)))
        (first %sx-registry)))

    (method classes (self)
      (doc "Every class a grammar's table may answer, in index order."
        (returns LIST "Class symbols"))
      (List map (fn (_ row) (first row)) %sx-table))

    (method index (self (param cls SYMBOL "A class"))
      (doc "The class's index, from 1 in classes order; 0 for nil or a symbol not among them."
        (returns INTEGER "The index")
        (example "(Syntax index 'string)" "2"))
      (%sx-index cls %sx-table 1))

    (method rouge (self (param cls SYMBOL "A class"))
      (doc "The Rouge token class a class is written with in HTML, nil for none."
        (returns STRING "The token class")
        (example "(Syntax rouge 'keyword)" "\"k\""))
      (let ((row (%sx-row cls %sx-table))) (if (null? row) () (first (rest row)))))

    (method sgr (self (param cls SYMBOL "A class"))
      (doc "The SGR sequence a class is drawn with in the theme in use, whether or not standard output takes colour: for a screen editor that writes to its own terminal. Empty for a class drawn plain."
        (returns STRING "The escape sequence")
        (sample "(Syntax sgr 'number)" "\"\\x1b[33m\" in the default theme"))
      ((Theme current) sgr cls))

    (method code (self (param cls SYMBOL "A class"))
      (doc "The SGR sequence a class is drawn with in the theme in use when standard output takes colour (Ansi enabled?), else empty."
        (returns STRING "The escape sequence, or empty"))
      (if (Ansi enabled?) ((Theme current) sgr cls) ""))

    (method ansi (self (param text STRING "The text the spans index")
                       (param spans LIST "Spans, as spans answers them")
                       (param start INTEGER "The first byte to draw")
                       (param len INTEGER "How many bytes")
                       . (param code-of LIST "Optionally (fn (_ span)) answering a span's escape sequence, or nil for its class's"))
      (doc "The bytes of text from start, each span's wrapped in its class's sequence and a reset, the rest plain. The sequences are code's, the theme in use's and empty when colour is off, unless code-of answers one."
        (returns STRING "The text with escape sequences inserted")
        (sample "(Syntax ansi s ((Syntax x) spans s) 0 (Str8 length s))" "s coloured as x-lang"))
      (def own (if (null? code-of) () (first code-of)))
      (def on? (Ansi enabled?))
      (def codes ((Theme current) codes))
      (Str8 join ""
        (%sx-render spans start (%sx+ start len)
          (fn (_ a n) (%sx-bsub text a n))
          (fn (_ sp a n)
            (def t (%sx-bsub text a n))
            (let ((c (let ((o (if (null? own) () (own sp))))
                       (if (null? o) (if on? (%sx-sgr codes (first (rest (rest sp)))) "") o))))
              (if (= (%sx-blen c) 0) t (%sx-append c (%sx-append t %sx-reset)))))
          ())))

    (method html (self (param text STRING "The text the spans index")
                       (param spans LIST "Spans, as spans answers them")
                       (param start INTEGER "The first byte to write")
                       (param len INTEGER "How many bytes"))
      (doc "The bytes of text from start as HTML: each span's in a span element whose class is its Rouge token class, so a Rouge or Pygments stylesheet styles it; every byte escaped."
        (returns STRING "The markup")
        (example "(let ((s \"(f 1)\")) (Syntax html s ((Syntax x) spans s) 0 5))" "\"<span class=\\\"p\\\">(</span><span class=\\\"n\\\">f</span> <span class=\\\"m\\\">1</span><span class=\\\"p\\\">)</span>\""))
      (Str8 join ""
        (%sx-render spans start (%sx+ start len)
          (fn (_ a n) (%sx-html-escape (%sx-bsub text a n)))
          (fn (_ sp a n)
            (def t (%sx-bsub text a n))
            (let ((r (Syntax rouge (first (rest (rest sp))))))
              (if (null? r) (%sx-html-escape t)
                (Str8 append "<span class=\"" r "\">" (%sx-html-escape t) "</span>"))))
          ())))

    (method cells (self (param spans LIST "Spans, as spans answers them")
                        (param start INTEGER "The first byte")
                        (param len INTEGER "How many bytes"))
      (doc "A byte a text byte from start: 64 plus the index of the byte's class, a space for a byte of none. A screen editor that lays out its own rows -- tabs widened, control bytes shown as ^X -- carries a row of these beside its text and draws each cell in its class's sgr."
        (returns STRING "len bytes")
        (example "(let ((s \"(f 1)\")) (Syntax cells ((Syntax x) spans s) 0 5))" "\"JI DJ\""))
      (Str8 join ""
        (%sx-render spans start (%sx+ start len)
          (fn (_ a n) (%sx-run 32 n))
          (fn (_ sp a n) (%sx-run (%sx+ 64 (%sx-index (first (rest (rest sp))) %sx-table 1)) n))
          ())))

    (method cell-class (self (param b ANY "A byte from cells, as a code or a character"))
      (doc "The class a cell byte stands for, nil for a space."
        (returns SYMBOL "The class, or nil")
        (example "(Syntax cell-class 66)" "'string"))
      ((fn (self rows i) (if (null? rows) () (if (= i 1) (first (first rows)) (self (rest rows) (%sx- i 1)))))
       %sx-table (%sx- (if (char? b) (%sx-cint b) b) 64)))

    (method classify (self (param text STRING "One atom's bytes"))
      (doc "The class x-lang's grammar gives an atom: the reader's answer for its bytes, a construct a keyword. Memoised per distinct atom; forget! drops the memo."
        (returns SYMBOL "The class")
        (example "(List map (fn (_ s) (Syntax classify s)) (list \"def\" \"-\" \"#t\" \"%x\"))" "('keyword 'name 'constant 'private)"))
      (%sx-atom-class text))

    (method keywords (self)
      (doc "x-lang's constructs, as a Dict used as a set."
        (returns Dict "Construct name -> #t"))
      (%sx-keywords))

    (method forget! (self)
      (doc "Drop the construct set and the memo of atom classes, read again on next use: a lang that registers literal syntax changes what the reader answers."
        (returns NIL "Nothing"))
      (%set-first! %sx-kw ())
      (%set-first! %sx-memo ())
      ())))

; A run string holds no state an image cannot carry, but what the reader
; answers can change across a load, so the memo goes with it.  The theme in
; use goes too: the theme file an image is made under is not its user's.
(set! %image-recache-hooks
  (pair (fn (_) (do (Syntax forget!) (Theme forget!))) %image-recache-hooks))

(doc (provide x/tool/syntax Syntax Theme)
  (note "One vocabulary of classes, one span shape, three renderers: a grammar never writes markup, and a renderer never reads text.")
  (note "Theme says how a terminal draws each class; the user's theme file chooses one.")
  (note "x/repl/paint colours the REPL line and x/tool/highlight the documentation from (Syntax x).")
  "Syntax: lexical grammars and the renderers that draw their spans.")
