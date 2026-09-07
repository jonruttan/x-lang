; ansi.x -- Ansi: terminal color support, homed on the Ansi class.
;
; Detects terminal capabilities; the color codes live as Ansi static MEMBERS
; (computed once at class definition -- empty strings when color is off, so
; every use is a zero-cost no-op). When stdout is not a terminal, or NO_COLOR
; is set, or TERM is "dumb", or --no-color was passed, color is off.
;
; Color scheme follows LSP semantic token types mapped to standard ANSI:
;   number=yellow, string=green, variable/symbol=blue, keyword=bold-red,
;   function=cyan, string.escape/char=magenta, regexp=red, nil=dim
;
; Load-time wiring (by design, the module's integration job): fills doc.x's
; %c-* color stubs and installs the syntax-highlighted REPL printer.
;
; Requires: posix.x (Sys isatty/getenv), type.x (%type-push-write)

(import x/sys/posix)
; Fetch the tokenizer prims from the catalog (ns `buf`/`tok` are de-registered, R5).
(def %token-read-string (prim-ref 'tok 'read-str))

; Fetch the string prims from the catalog (ns `str` is de-registered, R5).
(def %str-append (prim-ref 'str 'append))

; Fetch the type-system helpers from the catalog (registered by sys/type.x).
(def %type-push-write (prim-ref 'type 'push-write))

(import x/type/struct)
(import x/type/class)

; --- Terminal detection ---

(def %no-color-env (Sys getenv "NO_COLOR"))
(def %term-env (Sys getenv "TERM"))
(def %no-color-arg
  (%fold
    (fn (_ acc a) (or acc (str=? a "--no-color")))
    ()
    args))

(def %ansi?
  (and (Sys isatty 1)
       (null? %no-color-env)
       (not (and (not (null? %term-env)) (str=? %term-env "dumb")))
       (not %no-color-arg)))

; --- Escape sequence builder ---

(def %esc "\x1b")
(def %sgr (fn (_ code) (if %ansi? (%str-append %esc (%str-append "[" (%str-append code "m"))) "")))

; --- The Ansi class: color members + operations ---
; Members evaluate once, here, at class definition. Methods referencing the
; %-helpers below resolve them at call time (deferred, the List precedent).

(def-class Ansi ()
  (static
    (reset   (%sgr "0")  "Reset all attributes")
    (bold    (%sgr "1")  "Bold")
    (dim     (%sgr "2")  "Dim")
    (red     (%sgr "31") "Red foreground")
    (green   (%sgr "32") "Green foreground")
    (yellow  (%sgr "33") "Yellow foreground")
    (blue    (%sgr "34") "Blue foreground")
    (magenta (%sgr "35") "Magenta foreground")
    (cyan    (%sgr "36") "Cyan foreground")
    (bold-cyan   (%str-append (%sgr "1") (%sgr "36")) "Bold cyan foreground")
    (bold-green  (%str-append (%sgr "1") (%sgr "32")) "Bold green foreground")
    (bold-yellow (%str-append (%sgr "1") (%sgr "33")) "Bold yellow foreground")
    (bold-red    (%str-append (%sgr "1") (%sgr "31")) "Bold red foreground")
    (bold-blue   (%str-append (%sgr "1") (%sgr "34")) "Bold blue foreground")
    (method enabled? (self)
      (doc "Check whether ANSI color support is active."
        (returns BOOL "True if ANSI color output is enabled"))
      %ansi?)
    (method wrap (self (param style STRING "ANSI escape sequence") (param text STRING "Text to wrap"))
      (doc "Wrap text in an ANSI style code with automatic reset."
        (returns STRING "Text wrapped in ANSI codes, or plain text if colors disabled"))
      (%str-append style (%str-append text (Ansi reset))))
    (method highlight (self (param code STRING "Source code string to highlight"))
      (doc "Syntax-highlight a code string and display it. Keywords in bold magenta, symbols in blue, numbers in yellow, strings in green."
        (returns ANY "Displays highlighted code to stdout")
        (example "(Ansi highlight \"(def x 42)\")" "(def x 42)"))
      (if (not %ansi?)
        (display code)
        ; Terminated read, local on purpose: this file is boot-included,
        ; so it cannot import the shared door (x/codec/xon).  Without the
        ; appended space, read-str drops an unterminated final token
        ; (#161) -- and highlight routinely sees mid-edit text whose last
        ; token IS unterminated.
        (let ((%toks (%token-read-string (%base) (Str8 append code " ")))
              (%go
                (fn (self toks first?)
                  (unless (null? toks)
                    (do
                      (unless first? (display " "))
                      (%ansi-write-code (first toks))
                      (self (rest toks) ()))))))
          (%go %toks #t))))
    (method enable-repl (self)
      (doc "Enable syntax-highlighted REPL output using LSP semantic token colors.")
      (unless (not %ansi?)
        (set! %repl-print
          (fn (_ result)
            (unless (null? result) (%ansi-write result))
            (newline)))))
    (method disable-repl (self)
      (doc "Restore plain REPL output.")
      (set! %repl-print %saved-repl-print))
    (method install (self)
      (doc "Detect the terminal and (re)install every colour this file owns -- the class statics, the printer's %c-* globals, doc.x's stubs and the REPL printer. Called when this file loads and again by the image recache hook, since whether there is a terminal is a fact of the PROCESS and the colours are strings a state image would otherwise carry from the writer's pipe."
        (returns NIL "Nothing; the colours are installed as a side effect"))
      (do
        (set! %no-color-env (Sys getenv "NO_COLOR"))
        (set! %term-env (Sys getenv "TERM"))
        (set! %no-color-arg
          (%fold (fn (_ acc a) (or acc (str=? a "--no-color"))) () args))
        (set! %ansi?
          (and (Sys isatty 1)
               (null? %no-color-env)
               (not (and (not (null? %term-env)) (str=? %term-env "dumb")))
               (not %no-color-arg)))
        ; The class statics, through the class's own setter.  %sgr answers ""
        ; for every code when colour is off, so one pass covers both ways.
        (Ansi reset       (%sgr "0"))
        (Ansi bold        (%sgr "1"))
        (Ansi dim         (%sgr "2"))
        (Ansi red         (%sgr "31"))
        (Ansi green       (%sgr "32"))
        (Ansi yellow      (%sgr "33"))
        (Ansi blue        (%sgr "34"))
        (Ansi magenta     (%sgr "35"))
        (Ansi cyan        (%sgr "36"))
        (Ansi bold-cyan   (%str-append (%sgr "1") (%sgr "36")))
        (Ansi bold-green  (%str-append (%sgr "1") (%sgr "32")))
        (Ansi bold-yellow (%str-append (%sgr "1") (%sgr "33")))
        (Ansi bold-red    (%str-append (%sgr "1") (%sgr "31")))
        (Ansi bold-blue   (%str-append (%sgr "1") (%sgr "34")))
        ; The printer's own colours.
        (set! %c-number   (Ansi yellow))
        (set! %c-string   (Ansi green))
        (set! %c-symbol   (Ansi blue))
        (set! %c-char     (Ansi magenta))
        (set! %c-bool     (Ansi bold-red))
        (set! %c-nil-val  (Ansi dim))
        (set! %c-function (Ansi cyan))
        (set! %c-rst      (Ansi reset))
        (set! %c-keyword  (%str-append (%sgr "1") (%sgr "35")))
        ; doc.x's stubs (it defines them as "" and this file owns their value).
        (set! %c-reset   (Ansi reset))
        (set! %c-bold    (Ansi bold))
        (set! %c-dim     (Ansi dim))
        (set! %c-name    (Ansi bold-cyan))
        (set! %c-type    (Ansi green))
        (set! %c-param   (Ansi yellow))
        (set! %c-example (Ansi cyan))
        (set! %c-error   (Ansi bold-red))
        (set! %c-module  (Ansi bold))
        ; Both directions, so a re-run with no terminal puts the plain ones
        ; back rather than leaving a half-coloured session behind.
        (set! %highlight-code (if %ansi? (method-ref Ansi highlight) display))
        (if %ansi? (Ansi enable-repl) (Ansi disable-repl))
        ()))
))

; --- LSP semantic token colors ---
; number=yellow, string=green, symbol=blue, char=magenta,
; keyword/bool=bold-red, function=cyan, regexp=red, nil=dim

(def %c-number   (Ansi yellow))
(def %c-string   (Ansi green))
(def %c-symbol   (Ansi blue))
(def %c-char     (Ansi magenta))
(def %c-bool     (Ansi bold-red))
(def %c-nil-val  (Ansi dim))
(def %c-function (Ansi cyan))
(def %c-rst      (Ansi reset))

; --- Syntax-highlighted recursive writer ---
;
; Walks the value structure, emitting ANSI codes per type.
; Uses (write obj) for atomic values (delegates to C handlers),
; and (display ...) for color codes (bypasses type dispatch).

; Forward declaration for mutual recursion
(def %ansi-write ())

(def %ansi-write-list
  (fn (self obj)
    (if (null? (first obj))
      (do (display %c-nil-val "()" %c-rst))
      (%ansi-write (first obj)))
    (unless (null? (rest obj))
      (if (not (pair? (rest obj)))
        ; Dotted pair
        (do (display " . ") (%ansi-write (rest obj)))
        ; Continue list
        (do (display " ") (self (rest obj)))))))

(set! %ansi-write
  (fn (self obj)
    (if (null? obj)
      (do (display %c-nil-val "()" %c-rst))
    (if (eq? obj #t)
      (do (display %c-bool "#t" %c-rst))
    (if (eq? obj #f)
      (do (display %c-bool "#f" %c-rst))
    (if (pair? obj)
      (do (display "(") (%ansi-write-list obj) (display ")"))
    (if (number? obj)
      (do (display %c-number) (write obj) (display %c-rst))
    (if (str? obj)
      (do (display %c-string) (write obj) (display %c-rst))
    (if (symbol? obj)
      (do (display %c-symbol) (write obj) (display %c-rst))
    (if (char? obj)
      (do (display %c-char) (write obj) (display %c-rst))
    (if (procedure? obj)
      (do (display %c-function) (write obj) (display %c-rst))
    ; Default (regex, custom types, etc.): write without color
    (write obj))))))))))))

; --- Source code syntax highlighting ---
;
; Tokenizes a code string on the current base, then walks the token
; tree with keyword-aware coloring. Keywords (special forms) get bold
; magenta; regular symbols get blue; numbers/strings/chars/bools get
; their LSP semantic token colors.

(def %c-keyword  (%str-append (%sgr "1") (%sgr "35")))

; Keyword set — x-lang special forms and core operatives
(def %keywords
  (list 'def 'fn 'op 'if 'let 'do
        'match 'guard 'set! 'lit 'quasi
        'import 'include 'provide
        'and 'or 'not
        'apply 'eval 'begin
        'when 'unless 'letrec
        'cond 'case 'doc 'note))

(def %keyword?
  (fn (_ sym) (%memq? sym %keywords)))

; Forward declaration for mutual recursion
(def %ansi-write-code ())

(def %ansi-write-code-list
  (fn (self obj)
    (if (null? (first obj))
      (do (display %c-nil-val "()" %c-rst))
      (%ansi-write-code (first obj)))
    (unless (null? (rest obj))
      (if (not (pair? (rest obj)))
        (do (display " . ") (%ansi-write-code (rest obj)))
        (do (display " ") (self (rest obj)))))))

; Quote-family shorthand: the tokenizer expands 'x to (lit x) (and `,
; ,@ likewise), so re-rendering parsed code must fold them back or help
; samples written as 'rdonly display as (lit rdonly) -- the R1/R8 echo
; regression jon caught in (help File).
(def %code-sugar
  (fn (_ obj)
    (if (pair? obj)
      (if (pair? (rest obj))
        (if (null? (rest (rest obj)))
          (match
            ((eq? (first obj) 'lit) "'")
            ((eq? (first obj) 'quasi) "`")
            ((eq? (first obj) 'unquote) ",")
            ((eq? (first obj) 'unquote-splicing) ",@")
            (#t ()))
          ())
        ())
      ())))

(set! %ansi-write-code
  (fn (self obj)
    (if (null? obj)
      (do (display %c-nil-val "()" %c-rst))
    (if (eq? obj #t)
      (do (display %c-bool "#t" %c-rst))
    (if (eq? obj #f)
      (do (display %c-bool "#f" %c-rst))
    (if (pair? obj)
      (let ((sugar (%code-sugar obj)))
        (if (null? sugar)
          (do (display "(") (%ansi-write-code-list obj) (display ")"))
          (do (display %c-keyword sugar %c-rst)
              (%ansi-write-code (first (rest obj))))))
    (if (number? obj)
      (do (display %c-number) (write obj) (display %c-rst))
    (if (str? obj)
      (do (display %c-string) (write obj) (display %c-rst))
    (if (symbol? obj)
      (if (%keyword? obj)
        (do (display %c-keyword obj %c-rst))
        (do (display %c-symbol obj %c-rst)))
    (if (char? obj)
      (do (display %c-char) (write obj) (display %c-rst))
    (write obj)))))))))))

; --- REPL integration ---

(def %saved-repl-print %repl-print)

; --- Detection and installation, in ONE place ---------------------------
; WHETHER THERE IS A TERMINAL IS A FACT OF THE PROCESS, not of the heap, and
; every colour above is a STRING baked when this file loaded: the class
; statics at class definition, the %c-* globals here.  A state image carries
; those strings.  The writer's child has a pipe for stdout, so it decides
; `no colour` and bakes fourteen empty statics, and without this every boot
; from an image had colour off for good -- (help) came out plain in a
; terminal that could show it.  So detection and installation are one
; function: the load calls it, and an image's recache hook calls it again in
; the process that has the terminal, after the loader has put back the real
; `args` (which --no-color is read from).
(Ansi install)
(set! %image-recache-hooks (pair (fn (_) (Ansi install)) %image-recache-hooks))

(doc (provide x/repl/ansi Ansi)
  (note "Color scheme: LSP semantic tokens — number=yellow, string=green, symbol=blue, char=magenta, bool=bold-red, function=cyan.")
  (note "Colors are Ansi static members ((Ansi red), (Ansi bold-cyan), ...); empty strings when color is off.")
  (note "Respects NO_COLOR and TERM=dumb; pass --no-color to disable.")
  "ANSI terminal color support, homed on the Ansi class.")
